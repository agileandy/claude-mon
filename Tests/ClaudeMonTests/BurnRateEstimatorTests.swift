import Foundation
@testable import ClaudeMonKit

@MainActor
func runBurnRateEstimatorSuite(_ r: Runner) {
    r.test("estimate_emptyBuckets_returnsZeroLow") {
        let est = BurnRateEstimator.estimate(buckets: [], bucketSizeSeconds: 300)
        try expectClose(est.costPerHour, 0)
        try expectClose(est.tokensPerHour, 0)
        try expectEqual(est.confidence, .low)
    }

    r.test("estimate_twoBuckets_confidenceIsLow") {
        // <3 buckets is not enough to trust the signal, regardless of steadiness.
        let buckets = [
            BurnRateEstimator.Bucket(cost: 1.0, tokens: 1000),
            BurnRateEstimator.Bucket(cost: 1.0, tokens: 1000)
        ]
        let est = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 300)
        try expectEqual(est.confidence, .low)
    }

    r.test("estimate_steadyBuckets_confidenceIsHigh_correctRate") {
        // 5 buckets of $1 each, 5 min apart → $12/h (12 buckets per hour * $1).
        let buckets = Array(repeating: BurnRateEstimator.Bucket(cost: 1.0, tokens: 10_000), count: 5)
        let est = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 300)
        try expectClose(est.costPerHour, 12.0, tolerance: 0.01)
        try expectClose(est.tokensPerHour, 120_000, tolerance: 1)
        try expectEqual(est.confidence, .high)
    }

    r.test("estimate_spikeThenQuiet_usesMedianNotMean") {
        // One $10 spike, five $0.10 quiet buckets. Mean would say ~$22/h; median should say ~$1.20/h.
        var buckets = [BurnRateEstimator.Bucket(cost: 10.0, tokens: 100_000)]
        buckets.append(contentsOf: Array(repeating: BurnRateEstimator.Bucket(cost: 0.10, tokens: 1_000), count: 5))
        let est = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 300)
        // Median bucket cost is 0.10 → $1.20/h. Mean would be ~$22/h — reject that.
        try expect(est.costPerHour < 5.0, "median-based estimate should reject the spike, got \(est.costPerHour)")
        // MAD/median ignores the outlier — five steady $0.10 buckets vs one $10 spike means
        // the consensus is steady, so confidence is high. The whole point of robust dispersion.
        try expectEqual(est.confidence, .high)
    }

    r.test("estimate_burstyCodingPattern_confidenceIsNotLow") {
        // Real-world coding: 24 buckets across 2h, alternating active/idle. Half are idle ($0),
        // half are active at $0.20. Under CV this lands at low (CV ≈ 1.0); under MAD/median it
        // should be medium or high because active intensity is consistent.
        var buckets: [BurnRateEstimator.Bucket] = []
        for i in 0..<24 {
            let cost = i.isMultiple(of: 2) ? 0.20 : 0.0
            buckets.append(BurnRateEstimator.Bucket(cost: cost, tokens: Int(cost * 10_000)))
        }
        let est = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 300)
        try expect(est.confidence != .low,
                   "bursty-but-steady coding pattern should not be flagged low, got \(est.confidence)")
    }

    r.test("estimate_mostlyIdle_confidenceIsLow") {
        // >50% zero buckets → median is zero → no central tendency to project from.
        var buckets: [BurnRateEstimator.Bucket] = Array(
            repeating: BurnRateEstimator.Bucket(cost: 0.0, tokens: 0), count: 8
        )
        buckets.append(BurnRateEstimator.Bucket(cost: 0.50, tokens: 5_000))
        buckets.append(BurnRateEstimator.Bucket(cost: 0.50, tokens: 5_000))
        let est = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 300)
        try expectEqual(est.confidence, .low)
    }

    r.test("estimate_mildVariance_confidenceIsMedium") {
        // Costs: 1.0, 1.2, 0.8, 1.1, 0.9 — small spread around $1.
        let buckets: [BurnRateEstimator.Bucket] = [1.0, 1.2, 0.8, 1.1, 0.9].map {
            BurnRateEstimator.Bucket(cost: $0, tokens: Int($0 * 10_000))
        }
        let est = BurnRateEstimator.estimate(buckets: buckets, bucketSizeSeconds: 300)
        try expect(est.confidence == .medium || est.confidence == .high,
                   "mild variance should yield medium or high confidence, got \(est.confidence)")
    }

    r.test("bucketize_distributesEntriesByTimestamp") {
        // Start 10:00, bucket size 5 min, now 10:20. 4 complete buckets.
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(20 * 60)

        func ts(_ min: Double) -> Date { start.addingTimeInterval(min * 60) }
        // One entry in bucket 0 (0-5 min), two in bucket 2 (10-15 min).
        let entries = [
            entry(id: "a", at: ts(1), cost: 0.5),
            entry(id: "b", at: ts(12), cost: 0.3),
            entry(id: "c", at: ts(13), cost: 0.4)
        ]

        let buckets = BurnRateEstimator.bucketize(entries: entries, from: start, to: now, bucketSizeSeconds: 300)
        try expectEqual(buckets.count, 4)                 // 4 complete 5-min windows
        try expectClose(buckets[0].cost, 0.5)             // bucket 0-5 min
        try expectClose(buckets[1].cost, 0.0)             // empty
        try expectClose(buckets[2].cost, 0.7)             // 0.3 + 0.4
        try expectClose(buckets[3].cost, 0.0)             // empty
    }

    r.test("bucketize_excludesPartialTailBucket") {
        // Start 10:00, now 10:07. One complete bucket (0-5 min) + partial (5-7 min).
        // Partial bucket must be excluded so the estimator isn't tricked by "how far into the current bucket are we".
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(7 * 60)
        let entries = [entry(id: "a", at: start.addingTimeInterval(2 * 60), cost: 0.25)]

        let buckets = BurnRateEstimator.bucketize(entries: entries, from: start, to: now, bucketSizeSeconds: 300)
        try expectEqual(buckets.count, 1)
        try expectClose(buckets[0].cost, 0.25)
    }
}

// MARK: - test fixtures

private func entry(id: String, at timestamp: Date, cost: Double) -> UsageEntry {
    // UsageEntry.cost is derived from tokens × ModelPricing. To get a specific cost,
    // fabricate Sonnet input tokens: $3/M input means cost = inputTokens × 3e-6.
    // inputTokens = cost / 3e-6.
    let inputTokens = Int(cost / 3e-6)
    return UsageEntry(
        id: id,
        timestamp: timestamp,
        sessionId: "s",
        model: "claude-sonnet-4",
        inputTokens: inputTokens,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        projectDir: "-test"
    )
}
