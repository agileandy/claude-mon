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

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        projectsURL = home.appendingPathComponent(".claude/projects")
    }

    /// One-shot computation: parse all journals, build blocks + aggregates. Runs on this actor, off main.
    func loadBundle(since startDate: Date, now: Date = Date()) throws -> RefreshBundle {
        let entries = try loadEntries(since: startDate)
        let blocks = SessionAnalyzer.analyze(entries: entries, now: now)
        return RefreshBundle(
            entries: entries,
            blocks: blocks,
            activeBlock: SessionAnalyzer.activeBlock(in: blocks),
            dailyHistory: UsageAggregator.last7Days(from: entries),
            today: UsageAggregator.today(from: entries),
            week: UsageAggregator.thisWeek(from: entries),
            prevWeek: UsageAggregator.previousWeek(from: entries),
            month: UsageAggregator.thisMonth(from: entries),
            projects: UsageAggregator.byProject(from: entries, now: now)
        )
    }

    func loadEntries(since startDate: Date) throws -> [UsageEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsURL.path) else {
            throw ReadError.projectsDirNotFound
        }

        let jsonlFiles = try findJSONLFiles(since: startDate)
        var seen = Set<String>()
        var entries: [UsageEntry] = []

        for fileURL in jsonlFiles {
            // Journal layout: `~/.claude/projects/<munged-project-dir>/<session>.jsonl`.
            // The parent dir IS the project key; resolve once per file and tag every
            // entry from that file with it.
            let projectDir = fileURL.deletingLastPathComponent().lastPathComponent

            guard let data = fm.contents(atPath: fileURL.path),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8),
                      let raw = try? JSONDecoder().decode(RawLine.self, from: lineData),
                      raw.type == "assistant",
                      let usage = raw.message?.usage,
                      let msgId = raw.message?.id,
                      !msgId.isEmpty,
                      !seen.contains(msgId) else { continue }

                seen.insert(msgId)

                guard let timestamp = parseDate(raw.timestamp ?? "") else { continue }
                guard timestamp >= startDate else { continue }

                let entry = UsageEntry(
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
                entries.append(entry)
            }
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private func findJSONLFiles(since startDate: Date) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            result.append(url)
        }
        return result
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
    let entries: [UsageEntry]
    let blocks: [SessionBlock]
    let activeBlock: SessionBlock?
    let dailyHistory: [DailyAggregate]
    let today: PeriodTotals
    let week: PeriodTotals
    let prevWeek: PeriodTotals
    let month: PeriodTotals
    let projects: [ProjectAggregate]
}
