import Foundation
@testable import ClaudeMonKit

@MainActor
func runSmokeSuite(_ r: Runner) {
    r.test("modelPricing_knownRates") {
        try expectEqual(ModelPricing.rate(for: "claude-opus-4").inputPerM, 15)
        try expectEqual(ModelPricing.rate(for: "claude-sonnet-4").inputPerM, 3)
        try expectEqual(ModelPricing.rate(for: "claude-haiku-4").inputPerM, 0.25)
    }

    r.test("usageEntry_displayModel_stripsVersions") {
        let e = UsageEntry(
            id: "m1",
            timestamp: Date(),
            sessionId: "s1",
            model: "claude-3-5-sonnet-20241022",
            inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0,
            projectDir: "-test"
        )
        try expectEqual(e.displayModel, "Sonnet")
    }
}
