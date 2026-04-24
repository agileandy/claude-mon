import Foundation

/// Multi-day forecast: given the weekly budget and recent per-day spend, how many days
/// until the rolling-7d total would reach the cap? Uses median daily cost via
/// BurnRateEstimator so a single heavy day doesn't shift the forecast dramatically.
struct WeeklyForecast: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        /// At the current pace, the cap is reached on this date (and N days from now).
        case reachesCap(on: Date, daysFromNow: Double)
        /// Pace is slow enough that the cap is comfortably out of reach.
        case staysUnder
        /// Already at/past the cap.
        case alreadyExceeded
        /// Budget isn't set, confidence is low, or there's effectively no activity.
        case unavailable
    }

    let outcome: Outcome
    let dailyCostMedian: Double
    let confidence: BurnRateEstimator.Confidence

    /// Compute from inputs. Pure — no UserDefaults, no Date() side-effects.
    /// `entries` should be sorted by timestamp ascending (as JournalReader emits them).
    /// `now` is injected so the computation is deterministic in tests.
    static func compute(
        entries: [UsageEntry],
        weekTotalsCost: Double,
        weeklyBudget: Double,
        now: Date,
        calendar: Calendar = .current
    ) -> WeeklyForecast {
        guard weeklyBudget > 0 else {
            return WeeklyForecast(outcome: .unavailable, dailyCostMedian: 0, confidence: .low)
        }

        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -7, to: today) else {
            return WeeklyForecast(outcome: .unavailable, dailyCostMedian: 0, confidence: .low)
        }

        let buckets = BurnRateEstimator.bucketize(
            entries: entries,
            from: start,
            to: today,          // exclude partial "today" so it doesn't drag the median down
            bucketSizeSeconds: 86400
        )
        let estimate = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 86400)
        let dailyCost = estimate.costPerHour * 24  // convert "per hour" back to "per day"

        if weekTotalsCost >= weeklyBudget {
            return WeeklyForecast(outcome: .alreadyExceeded, dailyCostMedian: dailyCost, confidence: estimate.confidence)
        }

        guard estimate.confidence != .low, dailyCost >= 0.01 else {
            return WeeklyForecast(outcome: .unavailable, dailyCostMedian: dailyCost, confidence: estimate.confidence)
        }

        let remaining = weeklyBudget - weekTotalsCost
        let days = remaining / dailyCost
        // Anything > 30 days out is noise — prefer a clearer "stays under" message.
        if days > 30 {
            return WeeklyForecast(outcome: .staysUnder, dailyCostMedian: dailyCost, confidence: estimate.confidence)
        }

        let hitDate = now.addingTimeInterval(days * 86400)
        return WeeklyForecast(
            outcome: .reachesCap(on: hitDate, daysFromNow: days),
            dailyCostMedian: dailyCost,
            confidence: estimate.confidence
        )
    }
}
