import Foundation

struct PeriodTotals: Sendable {
    var tokens: Int = 0
    var cost: Double = 0
    var messages: Int = 0
    var modelBreakdown: [ModelAggregate] = []
}

enum UsageAggregator {
    static func today(from entries: [UsageEntry], calendar: Calendar = .current) -> PeriodTotals {
        let start = calendar.startOfDay(for: Date())
        return totals(from: entries.filter { $0.timestamp >= start })
    }

    static func thisWeek(from entries: [UsageEntry], calendar: Calendar = .current) -> PeriodTotals {
        rollingWindow(from: entries, days: 7, endingAt: Date())
    }

    static func previousWeek(from entries: [UsageEntry], calendar: Calendar = .current) -> PeriodTotals {
        let end = Date().addingTimeInterval(-7 * 86400)
        return rollingWindow(from: entries, days: 7, endingAt: end)
    }

    static func rollingWindow(from entries: [UsageEntry], days: Int, endingAt end: Date) -> PeriodTotals {
        let start = end.addingTimeInterval(-Double(days) * 86400)
        return totals(from: entries.filter { $0.timestamp >= start && $0.timestamp <= end })
    }

    static func thisMonth(from entries: [UsageEntry], calendar: Calendar = .current) -> PeriodTotals {
        let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return totals(from: entries.filter { $0.timestamp >= start })
    }

    static func last7Days(from entries: [UsageEntry]) -> [DailyAggregate] {
        let cutoff = Calendar.current.startOfDay(for: Date().addingTimeInterval(-6 * 86400))
        let recent = entries.filter { $0.timestamp >= cutoff }
        let byDay = DailyAggregate.build(from: recent)

        // Ensure we always have 7 entries (fill gaps with zeros)
        var result: [DailyAggregate] = []
        let calendar = Calendar.current
        for offset in 0..<7 {
            let day = calendar.startOfDay(for: Date().addingTimeInterval(Double(offset - 6) * 86400))
            if let existing = byDay.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                result.append(existing)
            } else {
                result.append(DailyAggregate(id: day, date: day, totalTokens: 0, totalCost: 0, modelBreakdown: [], sessionCount: 0))
            }
        }
        return result
    }

    // MARK: - Private

    private static func totals(from entries: [UsageEntry]) -> PeriodTotals {
        var byModel: [String: (tokens: Int, cost: Double)] = [:]
        var tokens = 0
        var cost = 0.0
        for e in entries {
            tokens += e.totalTokens
            cost   += e.cost
            var agg = byModel[e.displayModel] ?? (0, 0)
            agg.tokens += e.totalTokens
            agg.cost   += e.cost
            byModel[e.displayModel] = agg
        }
        let breakdown = byModel
            .map { ModelAggregate(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.cost > $1.cost }

        return PeriodTotals(
            tokens: tokens,
            cost: cost,
            messages: entries.count,
            modelBreakdown: breakdown
        )
    }
}
