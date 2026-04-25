import Foundation

struct PeriodTotals: Sendable {
    var tokens: Int = 0
    var cost: Double = 0
    var messages: Int = 0
    var modelBreakdown: [ModelAggregate] = []
}

enum UsageAggregator {
    static func today(from entries: [UsageEntry], now: Date = Date(), calendar: Calendar = .current) -> PeriodTotals {
        let start = calendar.startOfDay(for: now)
        return totals(from: entries.filter { $0.timestamp >= start })
    }

    static func thisWeek(from entries: [UsageEntry], now: Date = Date(), calendar: Calendar = .current) -> PeriodTotals {
        rollingWindow(from: entries, days: 7, endingAt: now)
    }

    static func previousWeek(from entries: [UsageEntry], now: Date = Date(), calendar: Calendar = .current) -> PeriodTotals {
        let end = now.addingTimeInterval(-7 * 86400)
        return rollingWindow(from: entries, days: 7, endingAt: end)
    }

    static func rollingWindow(from entries: [UsageEntry], days: Int, endingAt end: Date) -> PeriodTotals {
        let start = end.addingTimeInterval(-Double(days) * 86400)
        return totals(from: entries.filter { $0.timestamp >= start && $0.timestamp <= end })
    }

    static func thisMonth(from entries: [UsageEntry], now: Date = Date(), calendar: Calendar = .current) -> PeriodTotals {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return totals(from: entries.filter { $0.timestamp >= start })
    }

    /// Group entries by `projectDir` over the rolling 7-day window. Each result also
    /// carries the prior 7d cost (for week-over-week delta) and a 7-element daily
    /// sparkline (oldest first, today last). Sorted by week cost desc.
    static func byProject(
        from entries: [UsageEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectAggregate] {
        let weekStart = now.addingTimeInterval(-7 * 86400)
        let prevWeekStart = now.addingTimeInterval(-14 * 86400)

        let weekEntries = entries.filter { $0.timestamp >= weekStart && $0.timestamp <= now }
        let prevEntries = entries.filter { $0.timestamp >= prevWeekStart && $0.timestamp < weekStart }

        let weekByDir = Dictionary(grouping: weekEntries) { $0.projectDir }
        let prevByDir = Dictionary(grouping: prevEntries) { $0.projectDir }

        let aggregates = weekByDir.map { (dir, ents) -> ProjectAggregate in
            let decoded = ProjectName.decode(dirName: dir)
            let cost = ents.reduce(0.0) { $0 + $1.cost }
            let tokens = ents.reduce(0) { $0 + $1.totalTokens }
            let breakdown = modelBreakdownAggregates(from: ents)
            let prevCost = prevByDir[dir]?.reduce(0.0) { $0 + $1.cost } ?? 0
            let daily = dailyCosts7(entries: ents, now: now, calendar: calendar)
            return ProjectAggregate(
                dir: dir,
                displayName: decoded.display,
                fullPath: decoded.path,
                weekCost: cost,
                weekTokens: tokens,
                messageCount: ents.count,
                modelBreakdown: breakdown,
                prevWeekCost: prevCost,
                daily7: daily
            )
        }
        return aggregates.sorted { $0.weekCost > $1.weekCost }
    }

    static func last7Days(from entries: [UsageEntry], now: Date = Date(), calendar: Calendar = .current) -> [DailyAggregate] {
        let cutoff = calendar.startOfDay(for: now.addingTimeInterval(-6 * 86400))
        let recent = entries.filter { $0.timestamp >= cutoff }
        let byDay = DailyAggregate.build(from: recent, calendar: calendar)

        // Ensure we always have 7 entries (fill gaps with zeros)
        var result: [DailyAggregate] = []
        for offset in 0..<7 {
            let day = calendar.startOfDay(for: now.addingTimeInterval(Double(offset - 6) * 86400))
            if let existing = byDay.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                result.append(existing)
            } else {
                result.append(DailyAggregate(id: day, date: day, totalTokens: 0, totalCost: 0, modelBreakdown: [], sessionCount: 0))
            }
        }
        return result
    }

    // MARK: - Private

    /// Sparkline buckets: 7 day-sized bins, oldest first, today last.
    private static func dailyCosts7(entries: [UsageEntry], now: Date, calendar: Calendar) -> [Double] {
        var buckets = Array(repeating: 0.0, count: 7)
        let today = calendar.startOfDay(for: now)
        for e in entries {
            let day = calendar.startOfDay(for: e.timestamp)
            let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            guard daysAgo >= 0, daysAgo < 7 else { continue }
            buckets[6 - daysAgo] += e.cost
        }
        return buckets
    }

    private static func modelBreakdownAggregates(from entries: [UsageEntry]) -> [ModelAggregate] {
        var byModel: [String: (tokens: Int, cost: Double)] = [:]
        for e in entries {
            var agg = byModel[e.displayModel] ?? (0, 0)
            agg.tokens += e.totalTokens
            agg.cost   += e.cost
            byModel[e.displayModel] = agg
        }
        return byModel
            .map { ModelAggregate(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.cost > $1.cost }
    }

    private static func totals(from entries: [UsageEntry]) -> PeriodTotals {
        var tokens = 0
        var cost = 0.0
        for e in entries {
            tokens += e.totalTokens
            cost   += e.cost
        }
        return PeriodTotals(
            tokens: tokens,
            cost: cost,
            messages: entries.count,
            modelBreakdown: modelBreakdownAggregates(from: entries)
        )
    }
}
