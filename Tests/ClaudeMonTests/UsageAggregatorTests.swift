import Foundation
@testable import ClaudeMonKit

@MainActor
func runUsageAggregatorSuite(_ r: Runner) {
    // Fixed UTC calendar so day/week/month boundaries are deterministic regardless
    // of the machine's locale.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    // 2026-04-25 12:00:00 UTC — mid-month, mid-day so day/week/month windows
    // each have safe headroom on either side.
    let now = Date(timeIntervalSince1970: 1_777_120_800)

    func entry(id: String, daysAgo: Double, hourOffset: Double = 0, cost: Double = 1.0,
               model: String = "claude-sonnet-4") -> UsageEntry {
        let tokens = Int(cost / 3e-6)   // sonnet input gives a known cost
        return UsageEntry(
            id: id,
            timestamp: now.addingTimeInterval(-daysAgo * 86400 + hourOffset * 3600),
            sessionId: "s",
            model: model,
            inputTokens: tokens,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            projectDir: "-test"
        )
    }

    r.test("today_includesOnlyEntriesAfterStartOfDay") {
        let entries = [
            entry(id: "yesterday", daysAgo: 1),                  // before today
            entry(id: "this-morning", daysAgo: 0, hourOffset: -6), // 06:00 today
            entry(id: "right-now", daysAgo: 0),
        ]
        let t = UsageAggregator.today(from: entries, now: now, calendar: cal)
        try expectEqual(t.messages, 2)   // this-morning + right-now
    }

    r.test("thisWeek_isRolling7DaysEndingNow") {
        let entries = [
            entry(id: "8d-ago", daysAgo: 8),    // outside window
            entry(id: "5d-ago", daysAgo: 5),    // inside
            entry(id: "today",  daysAgo: 0),    // inside
        ]
        let w = UsageAggregator.thisWeek(from: entries, now: now, calendar: cal)
        try expectEqual(w.messages, 2)
    }

    r.test("previousWeek_endsSevenDaysAgo_notNow") {
        let entries = [
            entry(id: "13d-ago", daysAgo: 13),   // inside prev-week
            entry(id: "9d-ago",  daysAgo: 9),    // inside prev-week
            entry(id: "5d-ago",  daysAgo: 5),    // inside THIS week, not prev
            entry(id: "today",   daysAgo: 0),    // inside this week
        ]
        let p = UsageAggregator.previousWeek(from: entries, now: now, calendar: cal)
        try expectEqual(p.messages, 2)
    }

    r.test("thisMonth_respectsCalendarMonthBoundary") {
        // April starts 30 days before May 1; for now=2026-04-25 12:00 UTC,
        // the month start is 2026-04-01 00:00 UTC. 25 days before now plus headroom.
        let entries = [
            entry(id: "march-15", daysAgo: 41),  // outside (in March)
            entry(id: "april-3",  daysAgo: 22),  // inside April
            entry(id: "today",    daysAgo: 0),   // inside April
        ]
        let m = UsageAggregator.thisMonth(from: entries, now: now, calendar: cal)
        try expectEqual(m.messages, 2)
    }

    r.test("last7Days_returnsExactly7BucketsWithGapsAsZeros") {
        // Activity on day-6-ago and day-0-ago only; the other 5 days should be zero.
        let entries = [
            entry(id: "old",    daysAgo: 6, cost: 2.0),
            entry(id: "today",  daysAgo: 0, cost: 4.0),
        ]
        let history = UsageAggregator.last7Days(from: entries, now: now, calendar: cal)
        try expectEqual(history.count, 7)
        let nonZero = history.filter { $0.totalCost > 0.001 }
        try expectEqual(nonZero.count, 2)
    }

    r.test("rollingWindow_arbitraryDayCount_3days") {
        let entries = [
            entry(id: "5d-ago", daysAgo: 5),     // outside
            entry(id: "2d-ago", daysAgo: 2),     // inside
            entry(id: "1d-ago", daysAgo: 1),     // inside
            entry(id: "now",    daysAgo: 0),     // inside
        ]
        let w = UsageAggregator.rollingWindow(from: entries, days: 3, endingAt: now)
        try expectEqual(w.messages, 3)
    }

    r.test("rollingWindow_arbitraryDayCount_14days") {
        let entries = [
            entry(id: "16d", daysAgo: 16),    // outside
            entry(id: "10d", daysAgo: 10),    // inside
            entry(id: "now", daysAgo: 0),     // inside
        ]
        let w = UsageAggregator.rollingWindow(from: entries, days: 14, endingAt: now)
        try expectEqual(w.messages, 2)
    }

    r.test("totals_modelBreakdown_groupsAndSortsByCostDesc") {
        // Verifies that the dedup commit (totals → modelBreakdownAggregates)
        // didn't change behaviour: one Sonnet entry, two Opus entries (Opus is
        // ~5× cost of Sonnet at the same token count, so should sort first).
        let entries = [
            entry(id: "s", daysAgo: 0, cost: 1.0, model: "claude-sonnet-4"),
            entry(id: "o1", daysAgo: 0, cost: 1.0, model: "claude-opus-4"),
            entry(id: "o2", daysAgo: 0, cost: 1.0, model: "claude-opus-4"),
        ]
        let t = UsageAggregator.today(from: entries, now: now, calendar: cal)
        try expectEqual(t.modelBreakdown.count, 2)
        try expectEqual(t.modelBreakdown[0].model, "Opus")     // higher total cost first
        try expectEqual(t.modelBreakdown[1].model, "Sonnet")
    }
}
