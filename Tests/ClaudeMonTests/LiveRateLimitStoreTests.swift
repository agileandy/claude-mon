import Foundation
@testable import ClaudeMonKit

@MainActor
func runLiveRateLimitStoreSuite(_ r: Runner) async {
    let dir = Fixtures.subdir("ratelimit")

    func store(_ name: String) -> LiveRateLimitStore {
        LiveRateLimitStore(fileURL: dir.appendingPathComponent(name))
    }

    await r.test("liveRateLimitStore_missingFile_returnsNil") {
        // Path that explicitly doesn't exist. Reader should treat absence as "no
        // tee installed yet", not a failure.
        let s = store("does-not-exist.json")
        let result = await s.load()
        try expect(result == nil, "expected nil for missing file")
    }

    await r.test("liveRateLimitStore_malformedJson_returnsNil") {
        // File present but body is unparseable. Same contract: nil, no throw.
        let s = store("malformed.json")
        let result = await s.load()
        try expect(result == nil, "expected nil for malformed JSON")
    }

    await r.test("liveRateLimitStore_validFile_returnsPopulatedRateLimit") {
        let s = store("valid.json")
        guard let rl = await s.load() else {
            throw AssertionError(description: "expected non-nil result for valid fixture")
        }
        try expectClose(rl.fiveHour.usedPercentage, 60.8)
        try expectClose(rl.sevenDay.usedPercentage, 12.3)
        try expectEqual(rl.capturedAt, Date(timeIntervalSince1970: 1_777_097_420))
    }

    await r.test("liveRateLimitStore_missingSevenDay_tolerated") {
        // The statusline tee includes sevenDay only on subscriber accounts.
        // Reader must still surface the fiveHour data when sevenDay is absent.
        let s = store("missing-sevenday.json")
        guard let rl = await s.load() else {
            throw AssertionError(description: "expected non-nil result")
        }
        try expectClose(rl.fiveHour.usedPercentage, 40)
        try expectClose(rl.sevenDay.usedPercentage, 0)   // defaults to 0
    }
}
