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

    /// Sum of every entry the app has loaded. Bound by `usageStartDate` — the journal
    /// reader filters entries before that — so this is "lifetime since the user
    /// configured a start date", not all-time history.
    static func lifetime(from entries: [UsageEntry]) -> PeriodTotals {
        totals(from: entries)
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
                fullDisplay: decoded.fullDisplay,
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

    /// Log-scale aggregating timeline for the History tab. Returns oldest→newest:
    /// yearly buckets (older than ~1 year) → monthly (~31–365 days ago) → weekly
    /// (~8–28 days ago) → daily (last 7 days). Older empty buckets are dropped so a
    /// new install doesn't show a wall of zeros.
    static func aggregatedTimeline(
        from entries: [UsageEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimeBucket] {
        let todayStart    = calendar.startOfDay(for: now)
        // 7 daily buckets ending with today's bucket.
        let dayWindowStart  = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        // 3 weekly buckets immediately preceding the daily window (21 days).
        let weekWindowStart = calendar.date(byAdding: .day, value: -21, to: dayWindowStart) ?? dayWindowStart
        // Monthly buckets cover from start-of-month-12-months-ago up to weekWindowStart.
        // The day-30 → day-7 weekly rule means months end at weekWindowStart, even if
        // that's mid-month — fine for visual buckets.
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: todayStart) ?? todayStart
        let monthWindowStart = calendar.dateInterval(of: .month, for: yearAgo)?.start ?? yearAgo

        // Earliest entry decides how far back yearly buckets reach. If no entries,
        // we still emit the 7 daily zero-buckets (matching `last7Days` semantics).
        let earliestEntry = entries.map(\.timestamp).min()

        var buckets: [TimeBucket] = []

        // Year buckets: only emitted when there's data older than ~1 year.
        if let earliest = earliestEntry, earliest < monthWindowStart {
            let earliestYearStart = calendar.dateInterval(of: .year, for: earliest)?.start ?? earliest
            var cursor = earliestYearStart
            while cursor < monthWindowStart {
                let nextYear = calendar.date(byAdding: .year, value: 1, to: cursor) ?? monthWindowStart
                let bucketEnd = min(nextYear, monthWindowStart)
                let agg = totals(from: entries.filter { $0.timestamp >= cursor && $0.timestamp < bucketEnd })
                let yearLabel = String(calendar.component(.year, from: cursor))
                buckets.append(TimeBucket(
                    granularity: .year, start: cursor, end: bucketEnd,
                    totalCost: agg.cost, totalTokens: agg.tokens,
                    messageCount: agg.messages, label: yearLabel
                ))
                cursor = nextYear
            }
        }

        // Month buckets: only emitted when there's data older than the weekly window.
        // Monthly buckets start at the calendar-month containing the earliest entry,
        // clamped to no earlier than 1 year ago (older data falls into yearly buckets).
        if let earliest = earliestEntry, earliest < weekWindowStart {
            let earliestMonthStart = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
            let monthStart = max(earliestMonthStart, monthWindowStart)
            var cursor = monthStart
            while cursor < weekWindowStart {
                let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) ?? weekWindowStart
                let bucketEnd = min(nextMonth, weekWindowStart)
                let agg = totals(from: entries.filter { $0.timestamp >= cursor && $0.timestamp < bucketEnd })
                let label = monthLabel(cursor, calendar: calendar)
                buckets.append(TimeBucket(
                    granularity: .month, start: cursor, end: bucketEnd,
                    totalCost: agg.cost, totalTokens: agg.tokens,
                    messageCount: agg.messages, label: label
                ))
                cursor = nextMonth
            }
        }

        // Week buckets: always 3, even on an empty install (consistent with daily).
        do {
            var cursor = weekWindowStart
            while cursor < dayWindowStart {
                let nextWeek = calendar.date(byAdding: .day, value: 7, to: cursor) ?? dayWindowStart
                let bucketEnd = min(nextWeek, dayWindowStart)
                let agg = totals(from: entries.filter { $0.timestamp >= cursor && $0.timestamp < bucketEnd })
                let label = weekLabel(cursor, calendar: calendar)
                buckets.append(TimeBucket(
                    granularity: .week, start: cursor, end: bucketEnd,
                    totalCost: agg.cost, totalTokens: agg.tokens,
                    messageCount: agg.messages, label: label
                ))
                cursor = nextWeek
            }
        }

        // Day buckets: always 7, ending with today.
        do {
            var cursor = dayWindowStart
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
            while cursor < endOfToday {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endOfToday
                let agg = totals(from: entries.filter { $0.timestamp >= cursor && $0.timestamp < nextDay })
                let label = dayLabel(cursor, calendar: calendar)
                buckets.append(TimeBucket(
                    granularity: .day, start: cursor, end: nextDay,
                    totalCost: agg.cost, totalTokens: agg.tokens,
                    messageCount: agg.messages, label: label
                ))
                cursor = nextDay
            }
        }

        return buckets
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

    private static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }

    private static func weekLabel(_ date: Date, calendar: Calendar) -> String {
        let week = calendar.component(.weekOfYear, from: date)
        return "W\(week)"
    }

    private static func monthLabel(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        // Include the year suffix when the month isn't in the current year so the
        // ~1-year history doesn't fold into ambiguous month names ("Apr" twice).
        let nowYear = calendar.component(.year, from: Date())
        let bucketYear = calendar.component(.year, from: date)
        f.dateFormat = (bucketYear == nowYear) ? "MMM" : "MMM yy"
        return f.string(from: date)
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
