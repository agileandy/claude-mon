import Foundation
@testable import ClaudeMonKit

@MainActor
func runSessionBlockSuite(_ r: Runner) {
    r.test("sessionBlock_spikeThenQuiet_projectsMildly") {
        // Block starts at 0, "now" is 40 min in. A big spike in the first 5 min, then quiet.
        // Flat-average projection would extrapolate the early burn across the full 5h window
        // and produce a wildly inflated number. Median-based should stay close to actual.
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(40 * 60)  // 40 min into the 5h block

        var entries: [UsageEntry] = []
        // Big spike in bucket 0 (0-5 min): $10 worth.
        entries.append(sonnetEntry(id: "spike", at: start.addingTimeInterval(60), cost: 10.0))
        // Tiny activity in buckets 2, 4, 6: $0.10 each (7 buckets are complete at t=40min).
        entries.append(sonnetEntry(id: "q1", at: start.addingTimeInterval(12 * 60), cost: 0.10))
        entries.append(sonnetEntry(id: "q2", at: start.addingTimeInterval(22 * 60), cost: 0.10))
        entries.append(sonnetEntry(id: "q3", at: start.addingTimeInterval(32 * 60), cost: 0.10))

        let block = SessionBlock.build(from: entries, now: now)

        // Old flat-average produced a projection of ~$79 (spike dominates the whole window).
        // Median-based produces ~$15.5 (median bucket is $0.10 → $1.20/h × 4.3h remaining + $10.30 spent).
        // The test documents the regression boundary: must stay safely under the buggy flat-average value.
        try expect(block.projectedCost < 25.0,
                   "median-based projection should stay well under the flat-average bug (~$79), got $\(block.projectedCost)")
        try expect(block.burnRateCostPerHour < 5.0,
                   "burn rate should reflect recent quiet, not the opening spike (got $\(block.burnRateCostPerHour)/h)")
    }

    r.test("sessionBlock_steadyBurn_projectionIsReasonable") {
        // Steady $0.50 bucket every 5 min for 30 min → 6 buckets, median = 0.50 → $6/h.
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(30 * 60)
        var entries: [UsageEntry] = []
        for i in 0..<6 {
            entries.append(sonnetEntry(id: "e\(i)", at: start.addingTimeInterval(Double(i) * 5 * 60 + 30), cost: 0.5))
        }

        let block = SessionBlock.build(from: entries, now: now)
        try expectClose(block.burnRateCostPerHour, 6.0, tolerance: 0.1)
        // projection = totalCost ($3) + 6/h × 4.5h remaining = $30.
        try expectClose(block.projectedCost, 30.0, tolerance: 0.5)
    }

    r.test("sessionBlock_inactiveBlock_projectionEqualsTotalCost") {
        // Block ended >5h ago. Projection must equal totalCost (no extrapolation).
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(6 * 3600)  // 6h later
        let entries = [sonnetEntry(id: "a", at: start.addingTimeInterval(60), cost: 2.5)]
        let block = SessionBlock.build(from: entries, now: now)
        try expect(!block.isActive, "block should be inactive")
        try expectClose(block.projectedCost, block.totalCost)
        try expectClose(block.burnRateCostPerHour, 0)
    }
}

// MARK: - fixtures

private func sonnetEntry(id: String, at ts: Date, cost: Double) -> UsageEntry {
    // Sonnet input pricing is $3/M. inputTokens = cost / 3e-6.
    let tokens = Int(cost / 3e-6)
    return UsageEntry(
        id: id,
        timestamp: ts,
        sessionId: "s",
        model: "claude-sonnet-4",
        inputTokens: tokens,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        projectDir: "-test"
    )
}
