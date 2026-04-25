import Foundation

/// Resolves the test-fixture directory at compile time using `#filePath`. The
/// custom `Runner` harness in `main.swift` runs as a SwiftPM executable target
/// — there's no `Bundle.module` because the test target has no `resources:`
/// declaration in `Package.swift`. Using `#filePath` sidesteps that without
/// requiring any package restructuring.
///
/// Layout: `Tests/ClaudeMonTests/Fixtures/<service>/...`
enum Fixtures {
    /// Absolute URL of `Tests/ClaudeMonTests/Fixtures/`. Resolved from this
    /// file's compile-time location, so it's stable regardless of where
    /// `swift run ClaudeMonTests` is invoked from.
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()       // Support/
        .deletingLastPathComponent()       // ClaudeMonTests/
        .appendingPathComponent("Fixtures", isDirectory: true)

    /// Convenience: build a URL into a named subdirectory of Fixtures.
    static func subdir(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: true)
    }
}
