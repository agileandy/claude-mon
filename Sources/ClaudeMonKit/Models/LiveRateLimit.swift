import Foundation

/// Rate-limit data captured from Claude Code's statusline stdin payload, written to
/// `~/.claude/claude-mon-ratelimit.json` by a user-installed snippet in
/// `~/.claude/statusline-command.sh`. This is the authoritative number from Anthropic's
/// server — the same value Claude Code's own status line and the web console show.
///
/// The statusline only fires on assistant responses, so this file goes stale whenever
/// the user isn't actively prompting. Callers should consult `freshness(now:)` before
/// trusting `fiveHour.usedPercentage` over a local estimate.
struct LiveRateLimit: Sendable, Equatable {
    let capturedAt: Date
    let fiveHour: Bucket
    let sevenDay: Bucket

    struct Bucket: Sendable, Equatable {
        let usedPercentage: Double
        let resetsAt: Date
    }

    enum Freshness: Sendable, Equatable {
        /// Captured recently and its 5h window hasn't rolled over — trust the number.
        case fresh
        /// Captured within the freshness window, but the window has already reset.
        /// (Should be rare in practice; the data is stale by definition.)
        case stale
        /// Capture timestamp is older than the freshness cutoff.
        case aged
    }

    static let freshnessCutoff: TimeInterval = 30 * 60   // 30 minutes

    func freshness(now: Date = Date()) -> Freshness {
        if fiveHour.resetsAt <= now { return .stale }
        if now.timeIntervalSince(capturedAt) > Self.freshnessCutoff { return .aged }
        return .fresh
    }

    // MARK: - Parsing

    /// Returns nil if the file is missing, malformed, or the rate_limits fields are null.
    /// Tolerant: callers should treat nil as "no live data — fall back to local estimate".
    static func decode(jsonData: Data, now: Date = Date()) -> LiveRateLimit? {
        struct Wire: Decodable {
            let capturedAt: Double?
            let fiveHour: BucketWire?
            let sevenDay: BucketWire?
        }
        struct BucketWire: Decodable {
            let used_percentage: Double?
            let resets_at: Double?
        }

        guard let wire = try? JSONDecoder().decode(Wire.self, from: jsonData),
              let captured = wire.capturedAt,
              let five = wire.fiveHour,
              let fivePct = five.used_percentage,
              let fiveReset = five.resets_at
        else { return nil }

        let sevenPct   = wire.sevenDay?.used_percentage ?? 0
        let sevenReset = wire.sevenDay?.resets_at ?? 0

        return LiveRateLimit(
            capturedAt: Date(timeIntervalSince1970: captured),
            fiveHour: Bucket(
                usedPercentage: fivePct,
                resetsAt: Date(timeIntervalSince1970: fiveReset)
            ),
            sevenDay: Bucket(
                usedPercentage: sevenPct,
                resetsAt: Date(timeIntervalSince1970: sevenReset)
            )
        )
    }
}
