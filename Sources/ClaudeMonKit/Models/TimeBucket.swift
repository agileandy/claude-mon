import Foundation

/// A bucket on the History tab's log-scale timeline. The timeline mixes granularities:
/// the most recent 7 days are daily buckets, the prior ~3 weeks are weekly, the prior
/// ~year is monthly, and anything older is yearly. Built by
/// `UsageAggregator.aggregatedTimeline(from:)` and consumed by `HistoryChartView`.
struct TimeBucket: Identifiable, Sendable, Equatable {
    enum Granularity: String, Sendable, Equatable {
        case day, week, month, year

        /// One-letter chip shown under each bar so the user can see when the X-axis
        /// scale shifts.
        var letter: String {
            switch self {
            case .day:   return "D"
            case .week:  return "W"
            case .month: return "M"
            case .year:  return "Y"
            }
        }
    }

    var id: Date { start }
    let granularity: Granularity
    let start: Date
    let end: Date           // exclusive
    let totalCost: Double
    let totalTokens: Int
    let messageCount: Int
    let label: String
}
