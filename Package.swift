// swift-tools-version: 6.0
// Run tests with: swift run ClaudeMonTests
// (XCTest/Testing aren't resolvable on pure CommandLineTools; the test
//  harness is an executable target, not a .testTarget. Switch to
//  .testTarget when Xcode is installed.)
import PackageDescription

let package = Package(
    name: "ClaudeMon",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeMonKit",
            path: "Sources/ClaudeMonKit"
        ),
        .executableTarget(
            name: "ClaudeMon",
            dependencies: ["ClaudeMonKit"],
            path: "Sources/ClaudeMon"
        ),
        .executableTarget(
            name: "ClaudeMonTests",
            dependencies: ["ClaudeMonKit"],
            path: "Tests/ClaudeMonTests"
        )
    ]
)
