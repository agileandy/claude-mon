import Foundation

/// Reads `~/.claude/claude-mon-ratelimit.json` — the rate-limit cache written by the
/// user-installed snippet in Claude Code's statusline script. Stateless; re-reads on
/// every `load()` call. Returns nil when the file is absent or unreadable, which is
/// the normal first-run case (user hasn't configured the snippet, or hasn't made a
/// Claude Code API call yet this session).
actor LiveRateLimitStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appendingPathComponent(".claude/claude-mon-ratelimit.json")
        }
    }

    func load(now: Date = Date()) -> LiveRateLimit? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return LiveRateLimit.decode(jsonData: data, now: now)
    }
}
