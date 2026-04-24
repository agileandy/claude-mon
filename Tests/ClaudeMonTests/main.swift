import Foundation
@testable import ClaudeMonKit

// Minimal assert-based test harness.
// Exits 0 if all pass; exits 1 with a summary if any fail.
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
func run() -> Int32 {
    let r = Runner()

    print("Smoke ———————————————————————————————")

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
            inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0
        )
        try expectEqual(e.displayModel, "Sonnet")
    }

    return r.report()
}

exit(run())
