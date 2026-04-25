import Foundation
@testable import ClaudeMonKit

@MainActor
func runAlertCoordinatorSuite(_ r: Runner) async {
    // Records every alert delivered through the coordinator. Sendable + actor so
    // the @Sendable deliver closure can mutate it across actor boundaries.
    actor Recorder {
        private(set) var delivered: [Alert] = []
        func record(_ a: Alert) { delivered.append(a) }
    }

    let now = Date(timeIntervalSince1970: 1_777_120_800)   // 2026-04-25 12:00 UTC
    let blockStart = now.addingTimeInterval(-30 * 60)
    let blockKey = Int(blockStart.timeIntervalSince1970)

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!

    func snapshot(
        pct: Double = 0,
        source: AlertCenter.Input.RateLimitSource = .live,
        buckets: [BurnRateEstimator.Bucket] = [],
        digest: AlertCenter.Input.Digest = AlertCenter.Input.Digest(),
        enabled: Bool = true,
        onlyLive: Bool = true
    ) -> AlertCoordinator.Snapshot {
        AlertCoordinator.Snapshot(
            now: now,
            blockStartTime: blockStart,
            blockRateLimitPercent: pct,
            rateLimitSource: source,
            recentBurnBuckets: buckets,
            alertsEnabled: enabled,
            onlyAlertOnLiveData: onlyLive,
            digest: digest,
            calendar: cal
        )
    }

    await r.test("alertCoordinator_threshold_firesAndReturnsKeys") {
        let rec = Recorder()
        let after = await AlertCoordinator.evaluateAndFire(
            snapshot: snapshot(pct: 76),
            firedKeys: [],
            deliver: { await rec.record($0) }
        )
        let delivered = await rec.delivered
        try expectEqual(delivered.count, 1)
        try expectEqual(delivered[0].category, .threshold)
        try expect(after.contains("threshold:\(blockKey):75"))
    }

    await r.test("alertCoordinator_dedupKeysSuppressDelivery") {
        // 75% threshold already fired → coordinator must NOT call deliver again.
        let rec = Recorder()
        let after = await AlertCoordinator.evaluateAndFire(
            snapshot: snapshot(pct: 76),
            firedKeys: ["threshold:\(blockKey):75"],
            deliver: { await rec.record($0) }
        )
        let delivered = await rec.delivered
        try expectEqual(delivered.count, 0)
        // Returned set unchanged (still just the original key).
        try expectEqual(after.count, 1)
    }

    await r.test("alertCoordinator_estimateSource_blockedWhenOnlyLive") {
        let rec = Recorder()
        _ = await AlertCoordinator.evaluateAndFire(
            snapshot: snapshot(pct: 99, source: .estimate, onlyLive: true),
            firedKeys: [],
            deliver: { await rec.record($0) }
        )
        let delivered = await rec.delivered
        try expectEqual(delivered.count, 0)
    }

    await r.test("alertCoordinator_spike_firesEvenOnEstimateSource") {
        // Spike is local burn-rate; source-independent.
        var buckets = Array(repeating: BurnRateEstimator.Bucket(cost: 0.10, tokens: 1000), count: 11)
        buckets.append(BurnRateEstimator.Bucket(cost: 5.0, tokens: 50000))
        let rec = Recorder()
        _ = await AlertCoordinator.evaluateAndFire(
            snapshot: snapshot(pct: 0, source: .estimate, buckets: buckets, onlyLive: true),
            firedKeys: [],
            deliver: { await rec.record($0) }
        )
        let delivered = await rec.delivered
        try expectEqual(delivered.count, 1)
        try expectEqual(delivered[0].category, .spike)
    }

    await r.test("alertCoordinator_digest_firesAtConfiguredHour") {
        // Digest enabled + now (12:00) is past digest hour (10:00) → fires.
        let d = AlertCenter.Input.Digest(
            enabled: true,
            hour: 10,
            minute: 0,
            todayCost: 4.50,
            topModel: "Sonnet",
            percentChangeVsYesterday: -10
        )
        let rec = Recorder()
        let after = await AlertCoordinator.evaluateAndFire(
            snapshot: snapshot(digest: d),
            firedKeys: [],
            deliver: { await rec.record($0) }
        )
        let delivered = await rec.delivered
        try expectEqual(delivered.count, 1)
        try expectEqual(delivered[0].category, .digest)
        try expectEqual(delivered[0].id, "digest:2026-04-25")
        try expect(after.contains("digest:2026-04-25"))
    }

    await r.test("alertCoordinator_alertsDisabled_deliversNothing") {
        let rec = Recorder()
        let after = await AlertCoordinator.evaluateAndFire(
            snapshot: snapshot(pct: 99, enabled: false),
            firedKeys: [],
            deliver: { await rec.record($0) }
        )
        let delivered = await rec.delivered
        try expectEqual(delivered.count, 0)
        try expectEqual(after.count, 0)
    }
}
