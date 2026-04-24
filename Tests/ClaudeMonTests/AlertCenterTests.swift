import Foundation
@testable import ClaudeMonKit

@MainActor
func runAlertCenterSuite(_ r: Runner) {
    let now = Date(timeIntervalSince1970: 1_777_100_000)
    let blockStart = now.addingTimeInterval(-30 * 60)   // 30 min ago
    let blockKey = Int(blockStart.timeIntervalSince1970)

    func makeInput(
        pct: Double,
        source: AlertCenter.Input.RateLimitSource = .live,
        fired: Set<String> = [],
        enabled: Bool = true,
        onlyLive: Bool = true
    ) -> AlertCenter.Input {
        AlertCenter.Input(
            now: now,
            blockStartTime: blockStart,
            blockRateLimitPercent: pct,
            rateLimitSource: source,
            alreadyFiredKeys: fired,
            alertsEnabled: enabled,
            onlyAlertOnLiveData: onlyLive,
            recentBurnBuckets: [],
            digest: AlertCenter.Input.Digest(),
            calendar: .current
        )
    }

    r.test("threshold_crosses75_firesOnce") {
        let alerts = AlertCenter.evaluate(input: makeInput(pct: 76))
        try expectEqual(alerts.count, 1)
        try expectEqual(alerts.first?.id, "threshold:\(blockKey):75")
        try expectEqual(alerts.first?.category, .threshold)
    }

    r.test("threshold_crosses90_firesOnly90if75AlreadyFired") {
        let alerts = AlertCenter.evaluate(input: makeInput(
            pct: 92,
            fired: ["threshold:\(blockKey):75"]
        ))
        try expectEqual(alerts.count, 1)
        try expectEqual(alerts.first?.id, "threshold:\(blockKey):90")
    }

    r.test("threshold_jumpsFrom0To100_firesAllThree") {
        // Long poll gap or a big single burst: all three thresholds crossed since last fire.
        let alerts = AlertCenter.evaluate(input: makeInput(pct: 100))
        try expectEqual(alerts.count, 3)
        let ids = Set(alerts.map { $0.id })
        try expect(ids.contains("threshold:\(blockKey):75"))
        try expect(ids.contains("threshold:\(blockKey):90"))
        try expect(ids.contains("threshold:\(blockKey):100"))
    }

    r.test("threshold_below75_firesNothing") {
        try expectEqual(AlertCenter.evaluate(input: makeInput(pct: 74.9)).count, 0)
    }

    r.test("threshold_allAlreadyFired_firesNothing") {
        let fired: Set<String> = [
            "threshold:\(blockKey):75",
            "threshold:\(blockKey):90",
            "threshold:\(blockKey):100"
        ]
        try expectEqual(AlertCenter.evaluate(input: makeInput(pct: 101, fired: fired)).count, 0)
    }

    r.test("threshold_newBlock_firesFresh") {
        // Same fired keys but from an OLD block — don't suppress on new block's thresholds.
        let oldBlockKey = blockKey - 6 * 3600
        let staleFired: Set<String> = [
            "threshold:\(oldBlockKey):75",
            "threshold:\(oldBlockKey):90"
        ]
        let alerts = AlertCenter.evaluate(input: makeInput(pct: 91, fired: staleFired))
        try expectEqual(alerts.count, 2)   // current block's 75 + 90
    }

    r.test("threshold_estimateSource_blockedWhenOnlyLiveRequired") {
        let alerts = AlertCenter.evaluate(input: makeInput(
            pct: 99,
            source: .estimate,
            onlyLive: true
        ))
        try expectEqual(alerts.count, 0)
    }

    r.test("threshold_estimateAt99WithLiveAllowed_firesTwo") {
        let alerts = AlertCenter.evaluate(input: makeInput(
            pct: 99,
            source: .estimate,
            onlyLive: false
        ))
        let ids = alerts.map { $0.id }.sorted()
        try expectEqual(ids, [
            "threshold:\(blockKey):75",
            "threshold:\(blockKey):90"
        ])
    }

    r.test("threshold_alertsDisabled_firesNothing") {
        try expectEqual(AlertCenter.evaluate(input: makeInput(pct: 99, enabled: false)).count, 0)
    }

    r.test("threshold_noActiveBlock_firesNothing") {
        let input = AlertCenter.Input(
            now: now,
            blockStartTime: nil,
            blockRateLimitPercent: 99,
            rateLimitSource: .live,
            alreadyFiredKeys: [],
            alertsEnabled: true,
            onlyAlertOnLiveData: true,
            recentBurnBuckets: [],
            digest: AlertCenter.Input.Digest(),
            calendar: .current
        )
        try expectEqual(AlertCenter.evaluate(input: input).count, 0)
    }
}
