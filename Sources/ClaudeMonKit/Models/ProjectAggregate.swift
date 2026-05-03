import Foundation

/// Per-project rollup over the rolling 7-day window. The unique identity is `dir`
/// (the raw munged journal directory name); `displayName` is the resolved
/// human-readable name derived via `ProjectName.decode`.
///
/// `daily7` is 7 buckets of cost — oldest first, today last — for inline sparklines.
/// `prevWeekCost` enables a week-over-week delta in the project list.
struct ProjectAggregate: Identifiable, Sendable {
    var id: String { dir }
    let dir: String
    let displayName: String
    /// Best-effort full path with `$HOME` collapsed to `~`. Always populated; falls
    /// back to `displayName` when the dirName isn't a munged path (rare).
    let fullDisplay: String
    let fullPath: String?
    let weekCost: Double
    let weekTokens: Int
    let messageCount: Int
    let modelBreakdown: [ModelAggregate]
    let prevWeekCost: Double
    let daily7: [Double]
}
