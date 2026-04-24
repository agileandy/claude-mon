import Foundation
@testable import ClaudeMonKit

@MainActor
func runLiveRateLimitSuite(_ r: Runner) {
    let now = Date(timeIntervalSince1970: 1_777_100_000)

    r.test("liveRateLimit_parsesStatuslineFormat") {
        let json = """
        {"capturedAt":1777099800,"fiveHour":{"used_percentage":60.8,"resets_at":1777108800},"sevenDay":{"used_percentage":12.3,"resets_at":1777600000}}
        """.data(using: .utf8)!
        guard let parsed = LiveRateLimit.decode(jsonData: json) else {
            throw AssertionError(description: "decode returned nil")
        }
        try expectClose(parsed.fiveHour.usedPercentage, 60.8)
        try expectClose(parsed.sevenDay.usedPercentage, 12.3)
        try expectEqual(parsed.capturedAt, Date(timeIntervalSince1970: 1_777_099_800))
    }

    r.test("liveRateLimit_fresh_whenRecent_andWindowValid") {
        let limit = LiveRateLimit(
            capturedAt: now.addingTimeInterval(-60),    // 1 min ago
            fiveHour: .init(usedPercentage: 50, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: .init(usedPercentage: 10, resetsAt: now.addingTimeInterval(86400))
        )
        try expectEqual(limit.freshness(now: now), .fresh)
    }

    r.test("liveRateLimit_aged_whenOlderThanCutoff") {
        let limit = LiveRateLimit(
            capturedAt: now.addingTimeInterval(-45 * 60),   // 45 min ago, beyond 30m cutoff
            fiveHour: .init(usedPercentage: 50, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: .init(usedPercentage: 10, resetsAt: now.addingTimeInterval(86400))
        )
        try expectEqual(limit.freshness(now: now), .aged)
    }

    r.test("liveRateLimit_stale_whenWindowHasReset") {
        // Captured inside the freshness window, but the 5h window's resetsAt has passed:
        // the cached % no longer corresponds to the current block at all.
        let limit = LiveRateLimit(
            capturedAt: now.addingTimeInterval(-5 * 60),
            fiveHour: .init(usedPercentage: 95, resetsAt: now.addingTimeInterval(-60)),
            sevenDay: .init(usedPercentage: 10, resetsAt: now.addingTimeInterval(86400))
        )
        try expectEqual(limit.freshness(now: now), .stale)
    }

    r.test("liveRateLimit_decode_returnsNil_onMissingFields") {
        let bad = """
        {"capturedAt":1777099800,"fiveHour":{"resets_at":1777108800}}
        """.data(using: .utf8)!
        try expect(LiveRateLimit.decode(jsonData: bad) == nil,
                   "decode must return nil when used_percentage is absent")
    }

    r.test("liveRateLimit_decode_tolerantToMissingSevenDay") {
        // Some plans may not return sevenDay; the struct should still decode and default it.
        let partial = """
        {"capturedAt":1777099800,"fiveHour":{"used_percentage":40,"resets_at":1777108800}}
        """.data(using: .utf8)!
        guard let parsed = LiveRateLimit.decode(jsonData: partial) else {
            throw AssertionError(description: "decode returned nil")
        }
        try expectClose(parsed.fiveHour.usedPercentage, 40)
        try expectClose(parsed.sevenDay.usedPercentage, 0)
    }
}
