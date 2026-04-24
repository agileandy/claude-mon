import Foundation
@testable import ClaudeMonKit

@MainActor
func runWeeklyForecastSuite(_ r: Runner) {
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 7 * 86400 + 10 * 3600)  // day 7 at 10am UTC-ish
    let today = cal.startOfDay(for: now)

    r.test("weeklyForecast_noBudget_returnsUnavailable") {
        let f = WeeklyForecast.compute(
            entries: [], weekTotalsCost: 0, weeklyBudget: 0, now: now, calendar: cal
        )
        try expectEqual(f.outcome, .unavailable)
    }

    r.test("weeklyForecast_alreadyExceeded_returnsExceeded") {
        let f = WeeklyForecast.compute(
            entries: [], weekTotalsCost: 100, weeklyBudget: 50, now: now, calendar: cal
        )
        try expectEqual(f.outcome, .alreadyExceeded)
    }

    r.test("weeklyForecast_steadyDailySpend_projectsReachDate") {
        // 7 days of steady $5/day → median daily = $5. Budget $100, spent $35 so far.
        // Remaining = $65, days = 65/5 = 13.
        var entries: [UsageEntry] = []
        for dayOffset in 1...7 {
            if let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: today) {
                entries.append(sonnetEntry(id: "d\(dayOffset)", at: dayStart.addingTimeInterval(3600), cost: 5.0))
            }
        }
        let f = WeeklyForecast.compute(
            entries: entries, weekTotalsCost: 35.0, weeklyBudget: 100.0, now: now, calendar: cal
        )
        switch f.outcome {
        case .reachesCap(_, let days):
            try expectClose(days, 13.0, tolerance: 0.1)
        default:
            throw AssertionError(description: "expected .reachesCap, got \(f.outcome)")
        }
    }

    r.test("weeklyForecast_lowConfidence_returnsUnavailable") {
        // Only 2 days of data → too few buckets → confidence .low → unavailable.
        var entries: [UsageEntry] = []
        for dayOffset in 1...2 {
            if let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: today) {
                entries.append(sonnetEntry(id: "d\(dayOffset)", at: dayStart.addingTimeInterval(3600), cost: 5.0))
            }
        }
        let f = WeeklyForecast.compute(
            entries: entries, weekTotalsCost: 10.0, weeklyBudget: 100.0, now: now, calendar: cal
        )
        try expectEqual(f.outcome, .unavailable)
        try expectEqual(f.confidence, .low)
    }

    r.test("weeklyForecast_slowPace_staysUnder") {
        // 7 days of $0.10/day → median = $0.10, dailyCost = $0.10.
        // Budget $100, spent $0.70. Remaining = $99.30. days = 993 → > 30 → staysUnder.
        var entries: [UsageEntry] = []
        for dayOffset in 1...7 {
            if let dayStart = cal.date(byAdding: .day, value: -dayOffset, to: today) {
                entries.append(sonnetEntry(id: "d\(dayOffset)", at: dayStart.addingTimeInterval(3600), cost: 0.10))
            }
        }
        let f = WeeklyForecast.compute(
            entries: entries, weekTotalsCost: 0.70, weeklyBudget: 100.0, now: now, calendar: cal
        )
        try expectEqual(f.outcome, .staysUnder)
    }
}

private func sonnetEntry(id: String, at ts: Date, cost: Double) -> UsageEntry {
    let tokens = Int(cost / 3e-6)
    return UsageEntry(
        id: id,
        timestamp: ts,
        sessionId: "s",
        model: "claude-sonnet-4",
        inputTokens: tokens,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0
    )
}
