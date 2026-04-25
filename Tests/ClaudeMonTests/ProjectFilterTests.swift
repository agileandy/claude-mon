import Foundation
@testable import ClaudeMonKit

// Pure tests for the filter semantics. AppState's filtered properties are thin
// wrappers around UsageAggregator over `filteredEntries`, so we exercise the same
// shape via the aggregator directly.

@MainActor
func runProjectFilterSuite(_ r: Runner) {
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 14 * 86400 + 12 * 3600)

    func entry(_ id: String, _ daysAgo: Double, _ cost: Double, _ dir: String) -> UsageEntry {
        let tokens = Int(cost / 3e-6)
        return UsageEntry(
            id: id,
            timestamp: now.addingTimeInterval(-daysAgo * 86400),
            sessionId: "s",
            model: "claude-sonnet-4",
            inputTokens: tokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectDir: dir
        )
    }

    let allEntries: [UsageEntry] = [
        entry("a1", 1, 5.0, "-Users-andy-foo"),
        entry("a2", 2, 3.0, "-Users-andy-foo"),
        entry("b1", 1, 12.0, "-Users-andy-bar"),
        entry("c1", 3, 1.0, "-Users-andy-baz"),
    ]

    r.test("filter_nil_returnsAllEntries") {
        // Sanity: with no filter, `filteredEntries` equals `allEntries`. We're not
        // running AppState here, but the filter logic is `entries.filter { $0.projectDir == dir }`
        // — emulate it.
        let filter: String? = nil
        let filtered = filter == nil ? allEntries : allEntries.filter { $0.projectDir == filter }
        try expectEqual(filtered.count, 4)
    }

    r.test("filter_set_isolatesProject") {
        let filter: String? = "-Users-andy-foo"
        let filtered = allEntries.filter { $0.projectDir == filter }
        try expectEqual(filtered.count, 2)
        try expect(filtered.allSatisfy { $0.projectDir == "-Users-andy-foo" })
    }

    r.test("filter_unknownDir_returnsEmpty") {
        let filter: String? = "-nonexistent"
        let filtered = allEntries.filter { $0.projectDir == filter }
        try expectEqual(filtered.count, 0)
    }

    r.test("filter_appliedToAggregator_filtersTotals") {
        // Demonstrate that running thisWeek on the filtered subset yields the
        // expected per-project number, not the global one.
        let filtered = allEntries.filter { $0.projectDir == "-Users-andy-foo" }
        let week = UsageAggregator.rollingWindow(from: filtered, days: 7, endingAt: now)
        try expectClose(week.cost, 8.0, tolerance: 0.01)   // 5 + 3
        try expectEqual(week.messages, 2)
    }
}
