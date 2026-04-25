import Foundation
@testable import ClaudeMonKit

@MainActor
func runJournalReaderSuite(_ r: Runner) async {
    let journals = Fixtures.subdir("journals")
    let earlyDate = Date(timeIntervalSince1970: 0)   // permissive `since` for most cases

    func reader(_ name: String) -> JournalReader {
        JournalReader(projectsURL: journals.appendingPathComponent(name, isDirectory: true))
    }

    await r.test("journalReader_emptyProjectsDir_returnsNoEntriesAndDoesNotThrow") {
        let r = reader("empty")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 0)
    }

    await r.test("journalReader_singleAssistantMessage_parsesAllFields") {
        let r = reader("single-project")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 1)
        let e = entries[0]
        try expectEqual(e.id, "m1")
        try expectEqual(e.sessionId, "s1")
        try expectEqual(e.model, "claude-sonnet-4")
        try expectEqual(e.inputTokens, 1000)
        try expectEqual(e.outputTokens, 500)
        try expectEqual(e.cacheCreationTokens, 200)
        try expectEqual(e.cacheReadTokens, 100)
        try expectEqual(e.projectDir, "-Users-test-foo")
    }

    await r.test("journalReader_overlappingMessageIds_dedupesToFirstSeen") {
        // Two files in two project dirs, both with `id: shared-msg`. The reader
        // dedupes by message ID (first wins). We don't pin which file is "first"
        // (FileManager enumeration order isn't guaranteed) — just that exactly
        // one entry survives.
        let r = reader("multi-project-dedup")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 1)
        let dir = entries[0].projectDir
        try expect(dir == "-Users-test-foo" || dir == "-Users-test-bar",
                   "unexpected projectDir: \(dir)")
    }

    await r.test("journalReader_filtersOutNonAssistantTypes") {
        // Fixture has 4 lines: user, assistant, user, assistant. Only the two
        // assistants should be parsed.
        let r = reader("mixed-types")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 2)
        try expect(entries.allSatisfy { $0.id.hasPrefix("a") })
    }

    await r.test("journalReader_acceptsBothISO8601Formats") {
        // First line has fractional seconds, second is plain. Both must parse.
        let r = reader("timestamp-formats")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 2)
        let ids = Set(entries.map { $0.id })
        try expect(ids.contains("frac"))
        try expect(ids.contains("nofrac"))
    }

    await r.test("journalReader_missingCacheTokenFields_defaultToZero") {
        // Usage object without cache_creation_input_tokens / cache_read_input_tokens.
        let r = reader("missing-cache-fields")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 1)
        try expectEqual(entries[0].cacheCreationTokens, 0)
        try expectEqual(entries[0].cacheReadTokens, 0)
        try expectEqual(entries[0].inputTokens, 1000)   // sanity
    }

    await r.test("journalReader_sinceFilter_excludesOlderEntries") {
        // Fixture has 3 timestamps: 2026-04-23, 2026-04-24, 2026-04-25.
        // Filter at midnight on the 24th — keeps middle + new, drops old.
        let r = reader("since-filter")
        let cutoff = ISO8601DateFormatter().date(from: "2026-04-24T00:00:00Z")!
        let entries = try await r.loadEntries(since: cutoff)
        let ids = Set(entries.map { $0.id })
        try expectEqual(entries.count, 2)
        try expect(ids.contains("middle"))
        try expect(ids.contains("new"))
        try expect(!ids.contains("old"))
    }

    await r.test("journalReader_malformedJsonLine_isSkippedNotFatal") {
        // Fixture: bad-json + valid-assistant + truncated-json.
        // Reader should skip the broken lines and surface the valid one.
        let r = reader("malformed-line")
        let entries = try await r.loadEntries(since: earlyDate)
        try expectEqual(entries.count, 1)
        try expectEqual(entries[0].id, "valid")
    }

    await r.test("journalReader_loadBundle_aggregatesAcrossProjects") {
        // 2 projects: foo (2 msgs) + bar (1 msg). Bundle should expose both
        // through the `projects` array and the `entries` should total 3.
        let r = reader("two-projects-bundle")
        let bundle = try await r.loadBundle(since: earlyDate, now: Date(timeIntervalSince1970: 1_777_152_000))
        try expectEqual(bundle.entries.count, 3)
        try expectEqual(bundle.projects.count, 2)
        let dirs = Set(bundle.projects.map { $0.dir })
        try expect(dirs.contains("-Users-test-foo"))
        try expect(dirs.contains("-Users-test-bar"))
    }
}
