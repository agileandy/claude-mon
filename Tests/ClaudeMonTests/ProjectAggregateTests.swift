import Foundation
@testable import ClaudeMonKit

@MainActor
func runProjectAggregateSuite(_ r: Runner) {
    let cal = Calendar(identifier: .gregorian)
    // Day 14 noon UTC — gives us 7 days of "this week" + 7 of "prev week" headroom.
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

    r.test("byProject_groupsBySortsByWeekCostDesc") {
        let entries = [
            entry("a1", 1, 5.0, "-Users-andy-foo"),
            entry("a2", 2, 3.0, "-Users-andy-foo"),
            entry("b1", 1, 12.0, "-Users-andy-bar"),
            entry("c1", 3, 1.0, "-Users-andy-baz"),
        ]
        let projects = UsageAggregator.byProject(from: entries, now: now, calendar: cal)
        try expectEqual(projects.count, 3)
        try expectEqual(projects[0].dir, "-Users-andy-bar")  // 12 > 8 > 1
        try expectClose(projects[0].weekCost, 12.0, tolerance: 0.01)
        try expectEqual(projects[1].dir, "-Users-andy-foo")
        try expectClose(projects[1].weekCost, 8.0, tolerance: 0.01)
        try expectEqual(projects[2].dir, "-Users-andy-baz")
    }

    r.test("byProject_messageCountIsPerProject") {
        let entries = [
            entry("a1", 1, 5.0, "-Users-andy-foo"),
            entry("a2", 2, 3.0, "-Users-andy-foo"),
            entry("a3", 3, 1.0, "-Users-andy-foo"),
            entry("b1", 1, 1.0, "-Users-andy-bar"),
        ]
        let projects = UsageAggregator.byProject(from: entries, now: now, calendar: cal)
        let foo = projects.first { $0.dir == "-Users-andy-foo" }
        try expectEqual(foo?.messageCount, 3)
        let bar = projects.first { $0.dir == "-Users-andy-bar" }
        try expectEqual(bar?.messageCount, 1)
    }

    r.test("byProject_prevWeekCostIsSeparateFromCurrent") {
        let entries = [
            // current week
            entry("c1", 2, 5.0, "-Users-andy-foo"),
            // prev week (8-13 days ago)
            entry("p1", 8, 10.0, "-Users-andy-foo"),
            entry("p2", 10, 3.0, "-Users-andy-foo"),
        ]
        let projects = UsageAggregator.byProject(from: entries, now: now, calendar: cal)
        let foo = projects.first { $0.dir == "-Users-andy-foo" }
        try expectClose(foo?.weekCost ?? 0, 5.0, tolerance: 0.01)
        try expectClose(foo?.prevWeekCost ?? 0, 13.0, tolerance: 0.01)
    }

    r.test("byProject_daily7_oldestFirstTodayLast") {
        // Entries 0..6 days ago, $1 each. daily7 should be [1,1,1,1,1,1,1] (oldest=6d ago first).
        let entries: [UsageEntry] = (0..<7).map { d in
            entry("d\(d)", Double(d), 1.0, "-Users-andy-foo")
        }
        let projects = UsageAggregator.byProject(from: entries, now: now, calendar: cal)
        let foo = projects.first { $0.dir == "-Users-andy-foo" }
        try expectEqual(foo?.daily7.count, 7)
        for v in foo?.daily7 ?? [] { try expectClose(v, 1.0, tolerance: 0.01) }
    }

    r.test("byProject_daily7_zeroesGapDays") {
        // Only days 0 and 5 ago have activity. Gaps stay zero.
        let entries = [
            entry("a", 0, 2.0, "-Users-andy-foo"),
            entry("b", 5, 4.0, "-Users-andy-foo"),
        ]
        let projects = UsageAggregator.byProject(from: entries, now: now, calendar: cal)
        let foo = projects.first { $0.dir == "-Users-andy-foo" }
        // Indices: 0=oldest (6d ago), 6=today (0d ago).
        // 5d ago → index 1; today → index 6.
        try expectClose(foo!.daily7[1], 4.0, tolerance: 0.01)
        try expectClose(foo!.daily7[6], 2.0, tolerance: 0.01)
        try expectClose(foo!.daily7[0], 0)
    }

    r.test("byProject_displayNameDecodedFromDir") {
        let entries = [entry("a", 1, 1.0, "-Users-andy-cool-thing")]
        let projects = UsageAggregator.byProject(from: entries, now: now, calendar: cal)
        // Path doesn't exist → fallback last segment.
        try expectEqual(projects.first?.displayName, "thing")
    }
}
