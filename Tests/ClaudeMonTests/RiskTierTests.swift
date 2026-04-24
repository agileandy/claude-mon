import Foundation
@testable import ClaudeMonKit

@MainActor
func runRiskTierSuite(_ r: Runner) {
    r.test("riskTier_lowConfidence_returnsIndeterminate_regardlessOfRatio") {
        // Even a clearly-over-limit projection is indeterminate when the estimator
        // doesn't trust the underlying burn rate. Silencing a wrong-looking badge is
        // better than pretending it's certain.
        let tier = RiskTier.evaluate(projectedCost: 999, costLimit: 50, confidence: .low)
        try expectEqual(tier, .indeterminate)
    }

    r.test("riskTier_mediumConfidence_appliesThresholds") {
        try expectEqual(RiskTier.evaluate(projectedCost: 10, costLimit: 100, confidence: .medium), .onTrack)
        try expectEqual(RiskTier.evaluate(projectedCost: 85, costLimit: 100, confidence: .medium), .watch)
        try expectEqual(RiskTier.evaluate(projectedCost: 100, costLimit: 100, confidence: .medium), .atRisk)
        try expectEqual(RiskTier.evaluate(projectedCost: 150, costLimit: 100, confidence: .medium), .overrun)
    }

    r.test("riskTier_highConfidence_appliesSameThresholds") {
        try expectEqual(RiskTier.evaluate(projectedCost: 75, costLimit: 100, confidence: .high), .onTrack)
        try expectEqual(RiskTier.evaluate(projectedCost: 90, costLimit: 100, confidence: .high), .watch)
        try expectEqual(RiskTier.evaluate(projectedCost: 200, costLimit: 100, confidence: .high), .overrun)
    }
}
