import Foundation

struct DailyAggregate: Identifiable, Sendable {
    let id: Date           // start of day (local calendar)
    let date: Date
    var totalTokens: Int
    var totalCost: Double
    var modelBreakdown: [ModelAggregate]
    var sessionCount: Int
}

extension DailyAggregate {
    static func build(from entries: [UsageEntry], calendar: Calendar = .current) -> [DailyAggregate] {
        var byDay: [Date: [UsageEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            byDay[day, default: []].append(entry)
        }

        return byDay.map { (day, dayEntries) in
            var costByModel: [String: (tokens: Int, cost: Double)] = [:]
            var totalTok = 0
            var totalCost = 0.0
            var sessions = Set<String>()

            for e in dayEntries {
                totalTok  += e.totalTokens
                totalCost += e.cost
                sessions.insert(e.sessionId)
                let key = e.displayModel
                var agg = costByModel[key] ?? (tokens: 0, cost: 0)
                agg.tokens += e.totalTokens
                agg.cost   += e.cost
                costByModel[key] = agg
            }

            let breakdown = costByModel
                .map { ModelAggregate(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
                .sorted { $0.cost > $1.cost }

            return DailyAggregate(
                id: day,
                date: day,
                totalTokens: totalTok,
                totalCost: totalCost,
                modelBreakdown: breakdown,
                sessionCount: sessions.count
            )
        }
        .sorted { $0.date < $1.date }
    }
}
