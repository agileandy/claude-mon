import Foundation

actor JournalReader {
    private let projectsURL: URL
    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Single decoder reused for every line. JSONDecoder isn't `Sendable` but the
    /// actor isolates it; hoisting saves an allocation per line (~146K/refresh in
    /// production).
    private let decoder = JSONDecoder()

    /// Substring that must appear in any line we care about. Cheap byte-wise scan
    /// rejects ~all `user`/`permission-mode`/etc. lines before we hand them to the
    /// JSON parser. False positives (a content string containing the literal) fall
    /// through to the `raw.type == "assistant"` check below — correct, just slower.
    private static let assistantMarker = "\"type\":\"assistant\""

    // MARK: - Incremental state

    /// Per-file read cursor. Persists across `loadEntries` calls so subsequent
    /// refreshes only read appended bytes instead of re-slurping the whole file.
    private struct FileCursor {
        var modDate: Date
        var byteOffset: UInt64
    }

    private var cursors: [URL: FileCursor] = [:]

    /// Accumulated assistant entries across all refreshes since the last
    /// `lastStartDate` reset. Sorted by timestamp ascending.
    private var entries: [UsageEntry] = []

    /// Global dedup of message IDs we've already accepted. The journal layout
    /// occasionally writes the same `message.id` to two project dirs (e.g. resumed
    /// sessions); first-wins matches the pre-incremental behaviour.
    private var seenIds: Set<String> = []

    /// The `since` argument from the most recent call. If the user moves the
    /// "Usage Start Date" backward, every cursor is invalidated and we full-reload
    /// — incremental can't conjure entries we previously dropped.
    private var lastStartDate: Date?

    /// Default points at `~/.claude/projects`. Tests inject a fixture URL; production
    /// code calls the no-arg form unchanged.
    init(projectsURL: URL? = nil) {
        if let projectsURL {
            self.projectsURL = projectsURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.projectsURL = home.appendingPathComponent(".claude/projects")
        }
    }

    /// Refresh entrypoint: read any new journal bytes and return a fully-aggregated
    /// bundle. AppState never sees raw `[UsageEntry]` — the array stays on this actor.
    func loadAndBundle(
        since startDate: Date,
        filter: String?,
        weeklyBudget: Double,
        now: Date = Date()
    ) throws -> RefreshBundle {
        try loadIncremental(since: startDate)
        return computeBundle(filter: filter, weeklyBudget: weeklyBudget, now: now)
    }

    /// Filter-only re-bundle: when the user toggles `selectedProjectFilter` we need
    /// fresh filter-aware aggregates without re-reading any files.
    func rebundle(
        filter: String?,
        weeklyBudget: Double,
        now: Date = Date()
    ) -> RefreshBundle {
        return computeBundle(filter: filter, weeklyBudget: weeklyBudget, now: now)
    }

    /// Existing test-only entry point — preserved so the suite keeps compiling and
    /// keeps validating the parse/dedup contract. Production code uses
    /// `loadAndBundle` / `rebundle`.
    func loadEntries(since startDate: Date) throws -> [UsageEntry] {
        try loadIncremental(since: startDate)
        return entries
    }

    /// Existing test-only entry point — same shape as the pre-Branch-5 bundle so the
    /// `loadBundle_aggregatesAcrossProjects` fixture test keeps working unchanged.
    func loadBundle(since startDate: Date, now: Date = Date()) throws -> RefreshBundle {
        return try loadAndBundle(since: startDate, filter: nil, weeklyBudget: 0, now: now)
    }

    // MARK: - Bundle assembly

    private func computeBundle(filter: String?, weeklyBudget: Double, now: Date) -> RefreshBundle {
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        let activeBlock = SessionAnalyzer.activeBlock(in: blocks)

        // Global aggregates — used by the budget UI and by callers that want the
        // unfiltered picture.
        let todayG    = UsageAggregator.today(from: entries, now: now)
        let weekG     = UsageAggregator.thisWeek(from: entries, now: now)
        let prevWeekG = UsageAggregator.previousWeek(from: entries, now: now)
        let lifetimeG = UsageAggregator.lifetime(from: entries)
        let dailyG    = UsageAggregator.last7Days(from: entries, now: now)
        let projects  = UsageAggregator.byProject(from: entries, now: now)

        // Filter-aware aggregates — when no filter is active these alias the global
        // values, otherwise they're derived from the scoped subset.
        let scoped: [UsageEntry]
        let displayedToday: PeriodTotals
        let displayedWeek: PeriodTotals
        let displayedPrevWeek: PeriodTotals
        let displayedLifetime: PeriodTotals
        let displayedDaily: [DailyAggregate]
        let displayedBlocks: [SessionBlock]
        if let dir = filter {
            scoped = entries.filter { $0.projectDir == dir }
            displayedToday    = UsageAggregator.today(from: scoped, now: now)
            displayedWeek     = UsageAggregator.thisWeek(from: scoped, now: now)
            displayedPrevWeek = UsageAggregator.previousWeek(from: scoped, now: now)
            displayedLifetime = UsageAggregator.lifetime(from: scoped)
            displayedDaily    = UsageAggregator.last7Days(from: scoped, now: now)
            displayedBlocks   = SessionAnalyzer.analyze(entries: scoped, now: now)
        } else {
            scoped = entries
            displayedToday    = todayG
            displayedWeek     = weekG
            displayedPrevWeek = prevWeekG
            displayedLifetime = lifetimeG
            displayedDaily    = dailyG
            displayedBlocks   = blocks
        }

        let timeline = UsageAggregator.aggregatedTimeline(from: scoped, now: now)

        // Forecast is intentionally global — the forecast UI is hidden when a
        // filter is set, so always feeding the unfiltered series keeps the
        // computation cheap and consistent.
        let forecast = WeeklyForecast.compute(
            entries: entries,
            weekTotalsCost: weekG.cost,
            weeklyBudget: weeklyBudget,
            now: now
        )

        // Spike detector buckets: last hour, clamped to the active block start so
        // we don't compare apples to oranges across a 5h window boundary.
        let recent: [BurnRateEstimator.Bucket]
        if let block = activeBlock {
            let hourAgo = now.addingTimeInterval(-3600)
            let bucketStart = max(block.startTime, hourAgo)
            let recentEntries = entries.filter {
                $0.timestamp >= bucketStart && $0.timestamp < now
            }
            recent = BurnRateEstimator.bucketize(entries: recentEntries, from: bucketStart, to: now)
        } else {
            recent = []
        }

        return RefreshBundle(
            entries: entries,
            blocks: blocks,
            activeBlock: activeBlock,
            dailyHistory: dailyG,
            today: todayG,
            week: weekG,
            prevWeek: prevWeekG,
            lifetime: lifetimeG,
            projects: projects,
            displayedToday: displayedToday,
            displayedWeek: displayedWeek,
            displayedPrevWeek: displayedPrevWeek,
            displayedLifetime: displayedLifetime,
            displayedDailyHistory: displayedDaily,
            displayedSessionBlocks: displayedBlocks,
            timelineBuckets: timeline,
            weeklyForecast: forecast,
            recentBurnBuckets: recent
        )
    }

    /// Read any new bytes appended since the last call. Maintains the per-file
    /// cursor cache and the global entries/seenIds accumulators. Pure I/O —
    /// callers that want aggregates use `loadAndBundle` / `rebundle`.
    private func loadIncremental(since startDate: Date) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsURL.path) else {
            throw ReadError.projectsDirNotFound
        }

        // Start-date moved → invalidate everything. Easier and correct than trying
        // to retroactively splice older entries back into the cache.
        if lastStartDate != startDate {
            cursors.removeAll(keepingCapacity: true)
            entries.removeAll(keepingCapacity: true)
            seenIds.removeAll(keepingCapacity: true)
            lastStartDate = startDate
        }

        let jsonlFiles = try findJSONLFiles()
        var addedAny = false

        for fileURL in jsonlFiles {
            // Journal layout: `~/.claude/projects/<munged-project-dir>/<session>.jsonl`.
            // The parent dir IS the project key; resolve once per file and tag every
            // entry from that file with it.
            let projectDir = fileURL.deletingLastPathComponent().lastPathComponent

            guard let mtime = modificationDate(of: fileURL) else { continue }

            var cursor = cursors[fileURL]

            if let existing = cursor {
                // Skip files we've fully consumed and that haven't changed since.
                if mtime <= existing.modDate { continue }
            } else {
                // Never seen this file before. Skip cheaply if its entire history
                // predates `startDate` — those entries would be filtered out anyway.
                if mtime < startDate { continue }
                cursor = FileCursor(modDate: .distantPast, byteOffset: 0)
            }

            guard var c = cursor else { continue }

            do {
                let (newEntries, advancedTo) = try readNew(
                    file: fileURL,
                    fromOffset: c.byteOffset,
                    projectDir: projectDir,
                    startDate: startDate
                )
                if !newEntries.isEmpty {
                    entries.append(contentsOf: newEntries)
                    addedAny = true
                }
                c.byteOffset = advancedTo
                c.modDate = mtime
                cursors[fileURL] = c
            } catch {
                // One bad file shouldn't poison the whole refresh. Drop the cursor
                // so the next pass retries from scratch on this file.
                cursors[fileURL] = nil
            }
        }

        if addedAny {
            entries.sort { $0.timestamp < $1.timestamp }
        }
    }

    // MARK: - Private

    /// Read appended bytes from `offset` to end-of-file, parse assistant lines, and
    /// return both the new entries and the byte offset to record as the next
    /// cursor. The cursor only advances to the last `\n` boundary so a partial
    /// trailing line gets re-read on the next refresh once it's complete.
    private func readNew(
        file fileURL: URL,
        fromOffset offset: UInt64,
        projectDir: String,
        startDate: Date
    ) throws -> ([UsageEntry], UInt64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        // File may have been truncated/rewritten — clamp seek to end-of-file. If
        // size shrank below our cursor, re-read from 0.
        let fileSize = (try handle.seekToEnd())
        try handle.seek(toOffset: 0)
        let startAt: UInt64 = (offset > fileSize) ? 0 : offset
        try handle.seek(toOffset: startAt)

        guard let data = try handle.readToEnd(), !data.isEmpty else {
            return ([], startAt)
        }

        // Find the last newline so we don't process a partial trailing line.
        guard let lastNewlineIdx = data.lastIndex(of: UInt8(ascii: "\n")) else {
            // No newline yet — leave cursor where it was, wait for more bytes.
            return ([], startAt)
        }
        let processable = data.prefix(through: lastNewlineIdx)
        let advanceBy = UInt64(processable.count)

        var newEntries: [UsageEntry] = []
        // Iterate by splitting on \n. Substring slicing on Data is cheap (no copy).
        var lineStart = processable.startIndex
        let end = processable.endIndex
        while lineStart < end {
            let lineEnd = processable[lineStart..<end].firstIndex(of: UInt8(ascii: "\n")) ?? end
            let lineRange = lineStart..<lineEnd
            if lineEnd > lineStart {
                let lineData = processable[lineRange]
                if let entry = parseAssistantLine(
                    data: lineData,
                    projectDir: projectDir,
                    startDate: startDate
                ) {
                    newEntries.append(entry)
                }
            }
            lineStart = lineEnd < end ? processable.index(after: lineEnd) : end
        }

        return (newEntries, startAt + advanceBy)
    }

    /// Parse a single JSONL line into a UsageEntry, applying the same prefilter +
    /// dedup semantics as the original loader. Returns nil for any line that isn't
    /// a fresh assistant message we want to keep.
    private func parseAssistantLine(
        data: Data,
        projectDir: String,
        startDate: Date
    ) -> UsageEntry? {
        // Cheap byte-wise prefilter — most journal lines aren't assistant.
        guard data.range(of: Self.assistantMarkerData) != nil else { return nil }

        guard let raw = try? decoder.decode(RawLine.self, from: data),
              raw.type == "assistant",
              let usage = raw.message?.usage,
              let msgId = raw.message?.id,
              !msgId.isEmpty,
              !seenIds.contains(msgId) else { return nil }

        guard let entry = makeEntry(
            raw: raw,
            msgId: msgId,
            usage: usage,
            projectDir: projectDir,
            startDate: startDate
        ) else { return nil }

        seenIds.insert(msgId)
        return entry
    }

    private static let assistantMarkerData: Data = Data(assistantMarker.utf8)

    /// Maps a parsed JSONL line plus its file's project context into a UsageEntry.
    /// Returns nil when the timestamp is unparseable or older than `startDate` —
    /// the caller silently skips those, matching pre-R1 behaviour.
    private func makeEntry(
        raw: RawLine,
        msgId: String,
        usage: RawUsage,
        projectDir: String,
        startDate: Date
    ) -> UsageEntry? {
        guard let timestamp = parseDate(raw.timestamp ?? ""),
              timestamp >= startDate else { return nil }
        return UsageEntry(
            id: msgId,
            timestamp: timestamp,
            sessionId: raw.sessionId ?? msgId,
            model: raw.message?.model ?? "claude-sonnet",
            inputTokens: usage.input_tokens,
            outputTokens: usage.output_tokens,
            cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            projectDir: projectDir
        )
    }

    private func findJSONLFiles() throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            result.append(url)
        }
        return result
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func parseDate(_ raw: String) -> Date? {
        iso8601.date(from: raw) ?? iso8601NoFrac.date(from: raw)
    }
}

// MARK: - Raw Codable types (private to this file)

private struct RawLine: Decodable {
    let type: String
    let timestamp: String?
    let sessionId: String?
    let message: RawMessage?
}

private struct RawMessage: Decodable {
    let id: String?
    let model: String?
    let usage: RawUsage?
}

private struct RawUsage: Decodable {
    let input_tokens: Int
    let output_tokens: Int
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}

enum ReadError: LocalizedError {
    case projectsDirNotFound

    var errorDescription: String? {
        switch self {
        case .projectsDirNotFound:
            return "~/.claude/projects not found. Is Claude Code installed?"
        }
    }
}

struct RefreshBundle: Sendable {
    // Test-friendly: the test suite asserts on `entries` / `blocks` directly. In
    // production these are fed straight into the actor's display pipeline and the
    // MainActor never reads them.
    let entries: [UsageEntry]
    let blocks: [SessionBlock]

    // Global aggregates (independent of project filter). Used by the budget UI
    // which always shows the unfiltered weekly cost.
    let activeBlock: SessionBlock?
    let dailyHistory: [DailyAggregate]
    let today: PeriodTotals
    let week: PeriodTotals
    let prevWeek: PeriodTotals
    let lifetime: PeriodTotals
    let projects: [ProjectAggregate]

    // Filter-aware aggregates. When no filter is active these alias the global
    // values; under a filter they reflect only the scoped project's entries.
    let displayedToday: PeriodTotals
    let displayedWeek: PeriodTotals
    let displayedPrevWeek: PeriodTotals
    let displayedLifetime: PeriodTotals
    let displayedDailyHistory: [DailyAggregate]
    let displayedSessionBlocks: [SessionBlock]
    let timelineBuckets: [TimeBucket]

    // Cross-cutting derived values, always global (forecast UI hides under a
    // filter; the spike detector watches the active block which is global too).
    let weeklyForecast: WeeklyForecast
    let recentBurnBuckets: [BurnRateEstimator.Bucket]
}
