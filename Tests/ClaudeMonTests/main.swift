import Foundation
@testable import ClaudeMonKit

// Minimal assert-based test harness.
// Exits 0 if all pass; exits 1 with a summary if any fail.
// Run with: `swift run ClaudeMonTests`
// Replace with swift-testing / XCTest when Xcode is available on the machine.

@MainActor
final class Runner {
    var failures: [String] = []

    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            FileHandle.standardOutput.write(Data("  ok  \(name)\n".utf8))
        } catch {
            let msg = "  FAIL  \(name) — \(error)"
            FileHandle.standardError.write(Data("\(msg)\n".utf8))
            failures.append(msg)
        }
    }

    /// Async variant for actor-bound services (e.g. JournalReader). Same shape as
    /// `test(_:_:)` but awaits the body. Use from inside `async` suite functions.
    func test(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            FileHandle.standardOutput.write(Data("  ok  \(name)\n".utf8))
        } catch {
            let msg = "  FAIL  \(name) — \(error)"
            FileHandle.standardError.write(Data("\(msg)\n".utf8))
            failures.append(msg)
        }
    }

    func report() -> Int32 {
        if failures.isEmpty {
            print("\nAll tests passed.")
            return 0
        } else {
            print("\n\(failures.count) failure(s):")
            for f in failures { print(f) }
            return 1
        }
    }
}

struct AssertionError: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    if !condition() {
        throw AssertionError(description: "\(message) (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) throws {
    if a != b {
        throw AssertionError(description: "expected \(b), got \(a) (\(file):\(line))")
    }
}

func expectClose(_ a: Double, _ b: Double, tolerance: Double = 0.001, file: StaticString = #file, line: UInt = #line) throws {
    if abs(a - b) > tolerance {
        throw AssertionError(description: "expected ~\(b) (±\(tolerance)), got \(a) (\(file):\(line))")
    }
}

// MARK: - Suites

@MainActor
func run() async -> Int32 {
    let r = Runner()

    print("Smoke ———————————————————————————————")
    runSmokeSuite(r)

    print("\nBurnRateEstimator ———————————————————")
    runBurnRateEstimatorSuite(r)

    print("\nSessionBlock ————————————————————————")
    runSessionBlockSuite(r)

    print("\nRiskTier ————————————————————————————")
    runRiskTierSuite(r)

    print("\nWeeklyForecast ——————————————————————")
    runWeeklyForecastSuite(r)

    print("\nQuotaPercent ————————————————————————")
    runQuotaPercentSuite(r)

    print("\nLiveRateLimit ———————————————————————")
    runLiveRateLimitSuite(r)

    print("\nAlertCenter —————————————————————————")
    runAlertCenterSuite(r)

    print("\nAlertCenter (spike) —————————————————")
    runAlertCenterSpikeSuite(r)

    print("\nAlertCenter (digest) ————————————————")
    runAlertCenterDigestSuite(r)

    print("\nProjectName —————————————————————————")
    runProjectNameSuite(r)

    print("\nProjectAggregate ————————————————————")
    runProjectAggregateSuite(r)

    print("\nProjectFilter ———————————————————————")
    runProjectFilterSuite(r)

    print("\nJournalReader ———————————————————————")
    await runJournalReaderSuite(r)

    print("\nLiveRateLimitStore ——————————————————")
    await runLiveRateLimitStoreSuite(r)

    print("\nUsageAggregator —————————————————————")
    runUsageAggregatorSuite(r)

    print("\nSessionAnalyzer —————————————————————")
    runSessionAnalyzerSuite(r)

    print("\nAlertCoordinator ————————————————————")
    await runAlertCoordinatorSuite(r)

    return r.report()
}

exit(await run())
