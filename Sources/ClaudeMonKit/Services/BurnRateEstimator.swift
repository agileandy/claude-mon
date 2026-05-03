import Foundation

/// Windowed burn-rate estimation for an active session block.
///
/// The existing `SessionBlock.build` averages cost over the entire elapsed block window,
/// which makes the projection swing by 20–40% within a single block whenever activity is
/// bursty (a heavy first 15 min tails into 4h of quiet reading). This estimator uses the
/// median across fixed-size time buckets instead, which is robust to spikes, and emits a
/// confidence tier so the UI can disclaim a jittery reading.
enum BurnRateEstimator {
enum Confidence: Sendable, Equatable {
        case high
        case medium
        case low
    }

struct Bucket: Sendable, Equatable {
    let cost: Double
    let tokens: Int
    init(cost: Double, tokens: Int) {
            self.cost = cost
            self.tokens = tokens
        }
    }

struct Estimate: Sendable, Equatable {
    let costPerHour: Double
    let tokensPerHour: Double
    let confidence: Confidence
    }

    /// Estimate burn rate from time-ordered buckets (oldest first).
    /// Uses median cost/tokens per bucket × (buckets per hour). Confidence is derived from
    /// coefficient of variation — see `confidenceTier`.
static func estimate(buckets: [Bucket], bucketSizeSeconds: Double = 300) -> Estimate {
        guard !buckets.isEmpty, bucketSizeSeconds > 0 else {
            return Estimate(costPerHour: 0, tokensPerHour: 0, confidence: .low)
        }

        let bucketsPerHour = 3600.0 / bucketSizeSeconds
        let costs = buckets.map { $0.cost }
        let tokenCounts = buckets.map { Double($0.tokens) }

        return Estimate(
            costPerHour: median(of: costs) * bucketsPerHour,
            tokensPerHour: median(of: tokenCounts) * bucketsPerHour,
            confidence: confidenceTier(for: costs)
        )
    }

    /// Group entries into fixed-size time buckets over `[start, end)`.
    /// Only complete buckets are returned — a partial tail bucket (e.g. 2 min into a 5-min
    /// window) is excluded so the estimator isn't swayed by "how far through the current
    /// bucket are we". Zero-cost buckets within the span are kept; they legitimately
    /// represent quiet periods that should pull the median down.
static func bucketize(
        entries: [UsageEntry],
        from start: Date,
        to end: Date,
        bucketSizeSeconds: Double = 300
    ) -> [Bucket] {
        guard end > start, bucketSizeSeconds > 0 else { return [] }
        let completeCount = Int(end.timeIntervalSince(start) / bucketSizeSeconds)
        guard completeCount > 0 else { return [] }

        var costs = Array(repeating: 0.0, count: completeCount)
        var tokens = Array(repeating: 0, count: completeCount)

        for entry in entries {
            let offset = entry.timestamp.timeIntervalSince(start)
            guard offset >= 0 else { continue }
            let idx = Int(offset / bucketSizeSeconds)
            guard idx < completeCount else { continue }
            costs[idx] += entry.cost
            tokens[idx] += entry.totalTokens
        }

        return (0..<completeCount).map { Bucket(cost: costs[$0], tokens: tokens[$0]) }
    }

    // MARK: - Statistics

    /// Internal: AlertCenter.detectSpike (in R4) reuses this to dedup the inline
    /// median calculation that was previously duplicated there. Kept on the
    /// estimator because that's the only file that owns "statistics over Bucket
    /// costs" — alert policy (3× ratio + $0.05 floor) stays at the call site.
    static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// Robust dispersion-based confidence: median absolute deviation over median (MAD/median).
    /// CV (std/mean) is fooled by zero-inflated cost data — coding sessions are inherently bursty
    /// (active bursts of API calls separated by quiet thinking/reading), and zero buckets blow up
    /// CV even when the *active* pace is steady. MAD/median pairs naturally with the median-based
    /// rate calculation and is robust against single-bucket spikes.
    /// - `<3` buckets → `.low` (not enough signal regardless of steadiness).
    /// - median == 0 (>50% idle) → `.low` (rate calc is also zero — no central tendency to project).
    /// - MAD/median < 0.5 → `.high`; < 1.5 → `.medium`; else `.low`.
    private static func confidenceTier(for values: [Double]) -> Confidence {
        guard values.count >= 3 else { return .low }
        let med = median(of: values)
        guard med > 1e-6 else { return .low }
        let deviations = values.map { abs($0 - med) }
        let mad = median(of: deviations)
        let dispersion = mad / med
        switch dispersion {
        case ..<0.5: return .high
        case ..<1.5: return .medium
        default:     return .low
        }
    }
}
