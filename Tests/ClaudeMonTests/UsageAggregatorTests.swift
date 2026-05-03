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

    r.test("lifetime_includesEveryEntryRegardlessOfDate") {
        // Lifetime ignores calendar boundaries — it's the journal reader's
        // `usageStartDate` filter that bounds the data, not the aggregator.
        let entries = [
            entry(id: "march-15", daysAgo: 41),
            entry(id: "april-3",  daysAgo: 22),
            entry(id: "today",    daysAgo: 0),
        ]
        let m = UsageAggregator.lifetime(from: entries)
        try expectEqual(m.messages, 3)
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

    // MARK: - aggregatedTimeline

    r.test("aggregatedTimeline_emptyEntries_emits7DailyAnd3WeeklyZeroBuckets") {
        let buckets = UsageAggregator.aggregatedTimeline(from: [], now: now, calendar: cal)
        let days  = buckets.filter { $0.granularity == .day }
        let weeks = buckets.filter { $0.granularity == .week }
        let months = buckets.filter { $0.granularity == .month }
        let years = buckets.filter { $0.granularity == .year }
        try expectEqual(days.count, 7)
        try expectEqual(weeks.count, 3)
        try expectEqual(months.count, 0)
        try expectEqual(years.count, 0)
    }

    r.test("aggregatedTimeline_lastSevenDaysAreDailyBuckets") {
        let entries = [
            entry(id: "d0", daysAgo: 0, cost: 1.0),
            entry(id: "d3", daysAgo: 3, cost: 2.0),
            entry(id: "d6", daysAgo: 6, cost: 3.0),
        ]
        let buckets = UsageAggregator.aggregatedTimeline(from: entries, now: now, calendar: cal)
        let days = buckets.filter { $0.granularity == .day }
        try expectEqual(days.count, 7)
        let totalDayCost = days.reduce(0.0) { $0 + $1.totalCost }
        try expectClose(totalDayCost, 6.0)
    }

    r.test("aggregatedTimeline_8To28DaysAgoAreWeeklyBuckets") {
        // Each entry should land in a weekly bucket, not a daily one.
        let entries = [
            entry(id: "w8",  daysAgo: 8,  cost: 1.0),
            entry(id: "w15", daysAgo: 15, cost: 2.0),
            entry(id: "w22", daysAgo: 22, cost: 4.0),
        ]
        let buckets = UsageAggregator.aggregatedTimeline(from: entries, now: now, calendar: cal)
        let weekly = buckets.filter { $0.granularity == .week }
        try expectEqual(weekly.count, 3)
        try expectClose(weekly.reduce(0.0) { $0 + $1.totalCost }, 7.0)
        // Confirm none of those entries leaked into daily.
        let dailyTotal = buckets.filter { $0.granularity == .day }.reduce(0.0) { $0 + $1.totalCost }
        try expectClose(dailyTotal, 0.0)
    }

    r.test("aggregatedTimeline_31To365AgoAreMonthlyBuckets") {
        let entries = [
            entry(id: "m45",  daysAgo: 45,  cost: 5.0),    // ~1.5 months ago
            entry(id: "m180", daysAgo: 180, cost: 7.0),    // ~6 months ago
        ]
        let buckets = UsageAggregator.aggregatedTimeline(from: entries, now: now, calendar: cal)
        let monthly = buckets.filter { $0.granularity == .month }
        try expect(monthly.count >= 1, "expected at least one monthly bucket")
        try expectClose(monthly.reduce(0.0) { $0 + $1.totalCost }, 12.0)
    }

    r.test("aggregatedTimeline_olderThanOneYearAreYearlyBuckets") {
        let entries = [
            entry(id: "y2", daysAgo: 800, cost: 9.0),    // >2 years ago
            entry(id: "y1", daysAgo: 400, cost: 11.0),   // ~1.1 years ago
            entry(id: "now", daysAgo: 0,  cost: 1.0),
        ]
        let buckets = UsageAggregator.aggregatedTimeline(from: entries, now: now, calendar: cal)
        let yearly = buckets.filter { $0.granularity == .year }
        try expect(yearly.count >= 1, "expected at least one yearly bucket")
        let yearlyTotal = yearly.reduce(0.0) { $0 + $1.totalCost }
        // y2 always falls in yearly. y1 may fall in yearly or monthly depending on calendar
        // alignment — assert >= 9.0 (just y2) and that y2's cost is captured somewhere older
        // than the daily bucket.
        try expect(yearlyTotal >= 9.0 - 0.001, "yearly total should include y2's cost")
    }

    r.test("aggregatedTimeline_bucketsAreContiguousAndNonOverlapping") {
        let entries = [entry(id: "anchor", daysAgo: 600, cost: 1.0)]   // forces yearly buckets
        let buckets = UsageAggregator.aggregatedTimeline(from: entries, now: now, calendar: cal)
        for i in 1..<buckets.count {
            let prev = buckets[i - 1]
            let cur  = buckets[i]
            try expect(prev.end == cur.start,
                       "buckets must be contiguous: \(prev.label) ends \(prev.end), \(cur.label) starts \(cur.start)")
        }
    }

    r.test("aggregatedTimeline_orderIsOldestToNewest") {
        let entries = [entry(id: "anchor", daysAgo: 400, cost: 1.0)]
        let buckets = UsageAggregator.aggregatedTimeline(from: entries, now: now, calendar: cal)
        let starts = buckets.map(\.start)
        let sortedStarts = starts.sorted()
        try expect(starts == sortedStarts, "buckets should be sorted oldest first")
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
