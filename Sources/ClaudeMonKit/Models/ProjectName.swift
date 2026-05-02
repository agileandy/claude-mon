import Foundation

/// Decodes the path-munged directory name Claude Code uses for journal storage
/// (`~/.claude/projects/<munged-name>/*.jsonl`) back into a display name and, when
/// possible, the original filesystem path.
///
/// Munging rules observed in the wild:
///   `/Users/x/agent`             → `-Users-x-agent`
///   `/Users/x/.claude`           → `-Users-x--claude`     (leading dot collapses to dash)
///   `/Applications/Foo Bar.app`  → `-Applications-Foo-Bar-app`  (space and dot dropped)
///
/// The space/dot collapse is lossy. We try the most common reconstruction (single dash
/// → slash, double dash → slash-dot) and verify with `pathExists`. If the reconstructed
/// path exists we keep it; otherwise we fall back to the LAST `-`-delimited segment as
/// the display name — which is what the user mentally calls the project 90% of the time.
enum ProjectName {
    /// `path` is non-nil only when the heuristic reconstruction was filesystem-verified.
    /// `display` is the basename ("the thing the user calls the project").
    /// `fullDisplay` is the best-effort full path with `$HOME` collapsed to `~` — used
    /// when the user wants to disambiguate between projects with the same basename.
    static func decode(
        dirName: String,
        homeDir: String = NSHomeDirectory(),
        pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> (display: String, path: String?, fullDisplay: String) {
        let trimmed = dirName.hasPrefix("-") ? String(dirName.dropFirst()) : dirName

        // Reconstruction: dashes → slashes, then collapse `//` (which came from `--`) to
        // `/.` so `--claude` becomes `/.claude`.
        let candidate = "/"
            + trimmed.replacingOccurrences(of: "-", with: "/")
        let resolved = candidate.replacingOccurrences(of: "//", with: "/.")

        if !resolved.isEmpty, pathExists(resolved) {
            let last = (resolved as NSString).lastPathComponent
            let display = last.isEmpty ? resolved : last
            return (display: display, path: resolved, fullDisplay: collapseHome(resolved, homeDir: homeDir))
        }

        // Fallback: last `-`-delimited segment of the original dirName.
        let segments = trimmed.split(separator: "-", omittingEmptySubsequences: true)
        let display = segments.last.map(String.init) ?? dirName
        // If the dirName looks munged (starts with `-`), the unverified `resolved`
        // candidate is still a reasonable hint — show it. Otherwise (bare name like
        // "myproject" or empty), use `display` as fullDisplay.
        let fullDisplay: String
        if dirName.hasPrefix("-"), !resolved.isEmpty {
            fullDisplay = collapseHome(resolved, homeDir: homeDir)
        } else {
            fullDisplay = display
        }
        return (display: display, path: nil, fullDisplay: fullDisplay)
    }

    private static func collapseHome(_ path: String, homeDir: String) -> String {
        guard !homeDir.isEmpty, path.hasPrefix(homeDir) else { return path }
        let suffix = path.dropFirst(homeDir.count)
        return suffix.isEmpty ? "~" : "~" + suffix
    }
}
