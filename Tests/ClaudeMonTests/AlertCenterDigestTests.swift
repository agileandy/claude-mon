import Foundation
@testable import ClaudeMonKit

@MainActor
func runAlertCenterDigestSuite(_ r: Runner) {
    // Fixed calendar in UTC for deterministic boundaries.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    // 2026-04-25 15:30:00 UTC
    let now1530 = Date(timeIntervalSince1970: 1_777_131_000)

    func input(
        now: Date,
        fired: Set<String> = [],
        enabled: Bool = true,
        hour: Int = 18,
        todayCost: Double = 4.30,
        topModel: String? = "Sonnet",
        pctDelta: Double? = -15
    ) -> AlertCenter.Input {
        AlertCenter.Input(
            now: now,
            blockStartTime: nil,   // digest doesn't need it
            blockRateLimitPercent: 0,
            rateLimitSource: .live,
            alreadyFiredKeys: fired,
            alertsEnabled: true,
            onlyAlertOnLiveData: true,
            recentBurnBuckets: [],
            digest: AlertCenter.Input.Digest(
                enabled: enabled,
                hour: hour,
                minute: 0,
                todayCost: todayCost,
                topModel: topModel,
                percentChangeVsYesterday: pctDelta
            ),
            calendar: cal
        )
    }

    r.test("digest_beforeConfiguredTime_doesNotFire") {
        // 15:30 UTC, digest at 18:00 → before → no fire
        let alerts = AlertCenter.evaluate(input: input(now: now1530))
        try expectEqual(alerts.count, 0)
    }

    r.test("digest_afterConfiguredTime_firstTime_fires") {
        // 19:00 UTC, digest at 18:00 → past → fires
        let now1900 = now1530.addingTimeInterval(3.5 * 3600)
        let alerts = AlertCenter.evaluate(input: input(now: now1900))
        try expectEqual(alerts.count, 1)
        try expectEqual(alerts.first?.category, .digest)
        try expectEqual(alerts.first?.id, "digest:2026-04-25")
    }

    r.test("digest_alreadyFiredToday_doesNotFire") {
        let now1900 = now1530.addingTimeInterval(3.5 * 3600)
        let alerts = AlertCenter.evaluate(input: input(
            now: now1900,
            fired: ["digest:2026-04-25"]
        ))
        try expectEqual(alerts.count, 0)
    }

    r.test("digest_newDay_firesAgainEvenWithYesterdayKeyFired") {
        // Next day at 19:00 UTC (2026-04-26 19:00)
        let nowTomorrow = now1530.addingTimeInterval(86400 + 3.5 * 3600)
        let alerts = AlertCenter.evaluate(input: input(
            now: nowTomorrow,
            fired: ["digest:2026-04-25"]
        ))
        try expectEqual(alerts.count, 1)
        try expectEqual(alerts.first?.id, "digest:2026-04-26")
    }

    r.test("digest_disabled_doesNotFire") {
        let now1900 = now1530.addingTimeInterval(3.5 * 3600)
        let alerts = AlertCenter.evaluate(input: input(now: now1900, enabled: false))
        try expectEqual(alerts.count, 0)
    }

    r.test("digest_body_includesCostModelAndDelta") {
        let now1900 = now1530.addingTimeInterval(3.5 * 3600)
        let alerts = AlertCenter.evaluate(input: input(
            now: now1900,
            todayCost: 4.30,
            topModel: "Sonnet",
            pctDelta: -15
        ))
        let body = alerts.first?.body ?? ""
        try expect(body.contains("$4.30"), "body should include today's cost, got: \(body)")
        try expect(body.contains("Sonnet"), "body should include top model, got: \(body)")
        try expect(body.contains("-15%"), "body should include delta %, got: \(body)")
    }

    r.test("digest_body_tolerantToMissingOptionalData") {
        // No top model / no yesterday delta — body still fires with just cost.
        let now1900 = now1530.addingTimeInterval(3.5 * 3600)
        let alerts = AlertCenter.evaluate(input: input(
            now: now1900,
            topModel: nil,
            pctDelta: nil
        ))
        try expectEqual(alerts.count, 1)
        try expect(alerts.first!.body.contains("$4.30"))
    }
}
