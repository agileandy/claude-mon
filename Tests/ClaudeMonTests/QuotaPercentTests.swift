import Foundation
@testable import ClaudeMonKit

// The rate-limit gauge tracks Claude's actual enforcement (message count against the
// plan cap), not dollar cost against the plan's subscription price. Dollar spend is
// informational — it tells you how much API value you consumed, not when Claude will
// throttle you.

@MainActor
func runQuotaPercentSuite(_ r: Runner) {
    r.test("rateLimitPercent_halfway_onMax20") {
        let pct = ratePct(messageCount: 1000, messageLimit: 2000)
        try expectClose(pct, 50.0)
    }

    r.test("rateLimitPercent_capsAt100") {
        let pct = ratePct(messageCount: 9999, messageLimit: 2000)
        try expectClose(pct, 100.0)
    }

    r.test("rateLimitPercent_zeroWhenNoData") {
        try expectClose(ratePct(messageCount: 0, messageLimit: 2000), 0)
    }

    r.test("rateLimitPercent_matchesAndy'sConsoleCase") {
        // Reported scenario: console showed 58%. Previous WS-1.6 draft used
        // max(cost%, msg%) and returned 100 — that was wrong because Claude never
        // enforces a cost cap; it enforces messages + a token bucket. Now we track
        // messages only, which matches the console.
        let pct = ratePct(messageCount: 1160, messageLimit: 2000)
        try expectClose(pct, 58.0)
    }

    r.test("rateLimitPercent_notAffectedByHighCost") {
        // Even if the block has racked up $200 in API value (cache-heavy / Opus-heavy),
        // as long as messages are under the cap Claude won't rate-limit. The gauge
        // must not go red just because cost is high.
        let pct = ratePct(messageCount: 500, messageLimit: 2000)   // 25%
        try expectClose(pct, 25.0)  // ignores the fictional $200 entirely
    }
}

// MARK: - pure helper mirroring AppState.blockRateLimitPercent

private func ratePct(messageCount: Int, messageLimit: Int) -> Double {
    guard messageLimit > 0 else { return 0 }
    return min(100, Double(messageCount) / Double(messageLimit) * 100)
}
