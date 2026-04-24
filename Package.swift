// swift-tools-version: 6.0
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
