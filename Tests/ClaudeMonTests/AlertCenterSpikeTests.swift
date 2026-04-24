import Foundation
@testable import ClaudeMonKit

@MainActor
func runAlertCenterSpikeSuite(_ r: Runner) {
    let now = Date(timeIntervalSince1970: 1_777_100_000)
    let blockStart = now.addingTimeInterval(-60 * 60)   // 1h ago
    let blockKey = Int(blockStart.timeIntervalSince1970)

    func makeInput(
        buckets: [BurnRateEstimator.Bucket],
        fired: Set<String> = [],
        enabled: Bool = true
    ) -> AlertCenter.Input {
        AlertCenter.Input(
            now: now,
            blockStartTime: blockStart,
            blockRateLimitPercent: 0,           // irrelevant for spike-only paths
            rateLimitSource: .live,
            alreadyFiredKeys: fired,
            alertsEnabled: enabled,
            onlyAlertOnLiveData: true,
            recentBurnBuckets: buckets,
            digest: AlertCenter.Input.Digest(),
            calendar: .current
        )
    }

    func bucket(_ cost: Double) -> BurnRateEstimator.Bucket {
        BurnRateEstimator.Bucket(cost: cost, tokens: Int(cost * 10_000))
    }

    r.test("spike_noBuckets_noAlert") {
        try expectEqual(AlertCenter.evaluate(input: makeInput(buckets: [])).count, 0)
    }

    r.test("spike_tooFewBuckets_noAlert") {
        try expectEqual(AlertCenter.evaluate(input: makeInput(buckets: [bucket(0.1), bucket(0.1), bucket(0.1)])).count, 0)
    }

    r.test("spike_steadyLow_noAlert") {
        let buckets = Array(repeating: bucket(0.10), count: 12)
        try expectEqual(AlertCenter.evaluate(input: makeInput(buckets: buckets)).count, 0)
    }

    r.test("spike_recentHighVsLowMedian_fires") {
        // 11 quiet buckets ($0.10) then a $5 spike. Median prior = 0.10; 5 > 0.30 → spike.
        var buckets = Array(repeating: bucket(0.10), count: 11)
        buckets.append(bucket(5.0))
        let alerts = AlertCenter.evaluate(input: makeInput(buckets: buckets))
        try expectEqual(alerts.count, 1)
        try expectEqual(alerts.first?.id, "spike:\(blockKey)")
        try expectEqual(alerts.first?.category, .spike)
    }

    r.test("spike_alreadyFired_noAlert") {
        var buckets = Array(repeating: bucket(0.10), count: 11)
        buckets.append(bucket(5.0))
        let alerts = AlertCenter.evaluate(input: makeInput(
            buckets: buckets,
            fired: ["spike:\(blockKey)"]
        ))
        try expectEqual(alerts.count, 0)
    }

    r.test("spike_tinyAbsoluteAmount_belowFloor_noAlert") {
        // 11 zero buckets then $0.02. Ratio is huge but absolute amount is below
        // the $0.05 floor — not worth bothering the user.
        var buckets = Array(repeating: bucket(0), count: 11)
        buckets.append(bucket(0.02))
        try expectEqual(AlertCenter.evaluate(input: makeInput(buckets: buckets)).count, 0)
    }

    r.test("spike_alertsDisabled_noAlert") {
        var buckets = Array(repeating: bucket(0.10), count: 11)
        buckets.append(bucket(5.0))
        try expectEqual(AlertCenter.evaluate(input: makeInput(buckets: buckets, enabled: false)).count, 0)
    }

    r.test("spike_firesEvenOnEstimateSource") {
        // Spike detection is a local burn-rate signal, independent of rate-limit source.
        // If the user is on pure estimate mode, the threshold alerts are suppressed but
        // spikes should still fire.
        var buckets = Array(repeating: bucket(0.10), count: 11)
        buckets.append(bucket(5.0))
        let input = AlertCenter.Input(
            now: now,
            blockStartTime: blockStart,
            blockRateLimitPercent: 50,
            rateLimitSource: .estimate,
            alreadyFiredKeys: [],
            alertsEnabled: true,
            onlyAlertOnLiveData: true,
            recentBurnBuckets: buckets,
            digest: AlertCenter.Input.Digest(),
            calendar: .current
        )
        let alerts = AlertCenter.evaluate(input: input)
        try expectEqual(alerts.count, 1)
        try expectEqual(alerts.first?.category, .spike)
    }
}
