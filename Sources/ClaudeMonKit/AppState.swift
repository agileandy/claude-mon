import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class AppState {
    // MARK: - Data

    var allEntries: [UsageEntry] = []
    var sessionBlocks: [SessionBlock] = []
    var activeBlock: SessionBlock?
    var dailyHistory: [DailyAggregate] = []  // last 7 days

    var todayTotals: PeriodTotals    = PeriodTotals()
    var weekTotals: PeriodTotals     = PeriodTotals()   // rolling 7d ending now
    var prevWeekTotals: PeriodTotals = PeriodTotals()   // rolling 7d ending 7d ago
    var monthTotals: PeriodTotals    = PeriodTotals()

    /// Server-sourced rate-limit snapshot from Claude Code's statusline. `nil` when the
    /// user hasn't installed the tee snippet, or hasn't made an API call this session.
    var liveRateLimit: LiveRateLimit?

    // MARK: - UI State

    var selectedTab: Int = 0
    var isRefreshing: Bool = false
    var lastRefreshed: Date?
    var lastError: String?
    var countdownSeconds: Double = 0
    public var isPinned: Bool = false {
        didSet {
            guard oldValue != isPinned else { return }
            if isPinned {
                PinnedPanelController.shared.show(with: self)
            } else {
                PinnedPanelController.shared.hide()
            }
        }
    }

    // MARK: - Settings (persisted)

    var usageStartDate: Date {
        get {
            if let stored = UserDefaults.standard.object(forKey: "usageStartDate") as? Date { return stored }
            // Default: today at midnight local time
            return Calendar.current.startOfDay(for: Date())
        }
        set { UserDefaults.standard.set(newValue, forKey: "usageStartDate") }
    }

    var planType: PlanType {
        get {
            let raw = UserDefaults.standard.string(forKey: "planType") ?? PlanType.max20.rawValue
            return PlanType(rawValue: raw) ?? .max20
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "planType") }
    }

    var refreshInterval: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "refreshInterval")
            return v > 0 ? v : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: "refreshInterval") }
    }

    var menuBarMode: MenuBarMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "menuBarMode") ?? MenuBarMode.cost.rawValue
            return MenuBarMode(rawValue: raw) ?? .cost
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarMode") }
    }

    var historyGraphMode: HistoryGraphMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "historyGraphMode") ?? HistoryGraphMode.cost.rawValue
            return HistoryGraphMode(rawValue: raw) ?? .cost
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "historyGraphMode") }
    }

    /// User override for per-block cost limit; 0 means "use plan default".
    var customCostPerBlock: Double {
        get { UserDefaults.standard.double(forKey: "customCostPerBlock") }
        set { UserDefaults.standard.set(newValue, forKey: "customCostPerBlock") }
    }

    /// Optional weekly cost budget; 0 means no budget tracked.
    var weeklyBudget: Double {
        get { UserDefaults.standard.double(forKey: "weeklyBudget") }
        set { UserDefaults.standard.set(newValue, forKey: "weeklyBudget") }
    }

    var plan: PlanLimits { planType.limits }

    /// Effective block cost limit honoring the user override, else the plan default.
    var effectiveCostPerBlock: Double {
        customCostPerBlock > 0 ? customCostPerBlock : plan.costPerBlock
    }

    // MARK: - Private

    private let reader = JournalReader()
    private let liveStore = LiveRateLimitStore()
    private var refreshTask: Task<Void, Never>?

    public init() {
        start()
    }

    // MARK: - Lifecycle

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                let deadline = Date().addingTimeInterval(self.refreshInterval)
                while !Task.isCancelled, deadline.timeIntervalSinceNow > 0 {
                    self.countdownSeconds = deadline.timeIntervalSinceNow
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefreshed = Date() }

        do {
            // All parsing + aggregation runs on the JournalReader actor, not on MainActor.
            async let bundleTask = reader.loadBundle(since: usageStartDate)
            async let liveTask   = liveStore.load()

            let bundle = try await bundleTask
            liveRateLimit   = await liveTask

            allEntries      = bundle.entries
            sessionBlocks   = bundle.blocks
            activeBlock     = bundle.activeBlock
            dailyHistory    = bundle.dailyHistory
            todayTotals     = bundle.today
            weekTotals      = bundle.week
            prevWeekTotals  = bundle.prevWeek
            monthTotals     = bundle.month
            lastError       = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Derived helpers

    var blockCostPercent: Double {
        guard let block = activeBlock, effectiveCostPerBlock > 0 else { return 0 }
        return min(100, block.totalCost / effectiveCostPerBlock * 100)
    }

    enum RateLimitSource: Equatable {
        /// Authoritative % from Anthropic, captured by the statusline tee within the
        /// freshness window and before the 5h window reset.
        case live
        /// Local estimate: `messageCount / plan.messagesPerBlock`. Token-weighted
        /// server-side quota doesn't fit this model cleanly — drift is expected.
        case estimate
    }

    /// The rate-limit percentage the UI should show. Prefers the live value from
    /// Claude Code's statusline tee when fresh; falls back to a local estimate based
    /// on message count vs plan cap. Check `blockRateLimitSource` to know which.
    var blockRateLimitPercent: Double {
        if let live = liveRateLimit, live.freshness() == .fresh {
            return live.fiveHour.usedPercentage
        }
        guard let block = activeBlock, plan.messagesPerBlock > 0 else { return 0 }
        return min(100, Double(block.messageCount) / Double(plan.messagesPerBlock) * 100)
    }

    var blockRateLimitSource: RateLimitSource {
        if let live = liveRateLimit, live.freshness() == .fresh { return .live }
        return .estimate
    }

    /// When the live data is available, prefer its `resetsAt` for the time-remaining
    /// clock — it reflects Anthropic's actual 5h rolling window, not our synthesised
    /// "5h from first message" heuristic.
    var blockResetsAt: Date? {
        if let live = liveRateLimit, live.freshness() == .fresh {
            return live.fiveHour.resetsAt
        }
        guard let block = activeBlock else { return nil }
        return block.startTime.addingTimeInterval(5 * 3600)
    }

    // MARK: - Predictions (current block, cost-based)

    /// Dollars remaining until the block cost limit.
    var runwayRemainingCost: Double {
        guard let block = activeBlock else { return 0 }
        return max(0, effectiveCostPerBlock - block.totalCost)
    }

    /// Seconds until the limit is hit at current burn rate; nil if no burn rate.
    var runwaySecondsAtBurn: TimeInterval? {
        guard let block = activeBlock,
              block.burnRateCostPerHour > 0,
              runwayRemainingCost > 0 else { return nil }
        return runwayRemainingCost / block.burnRateCostPerHour * 3600
    }

    /// Wall-clock timestamp when limit would be hit; nil if no projection.
    var limitHitAt: Date? {
        guard let seconds = runwaySecondsAtBurn else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    /// True when the limit would be hit before the current 5h block closes.
    var limitHitBeforeBlockEnd: Bool {
        guard let seconds = runwaySecondsAtBurn, let block = activeBlock else { return false }
        return seconds < block.remainingSeconds
    }

    var blockRisk: RiskTier {
        guard let block = activeBlock else { return .onTrack }
        return RiskTier.evaluate(
            projectedCost: block.projectedCost,
            costLimit: effectiveCostPerBlock,
            confidence: block.projectionConfidence
        )
    }

    /// Week-over-week cost delta: positive = spent more than previous 7d.
    var weekVsPrevCostDelta: Double { weekTotals.cost - prevWeekTotals.cost }
    var weekVsPrevCostDeltaPct: Double {
        guard prevWeekTotals.cost > 0.001 else { return 0 }
        return weekVsPrevCostDelta / prevWeekTotals.cost * 100
    }

    /// Week budget consumption %; only meaningful when `weeklyBudget > 0`.
    var weeklyBudgetPercent: Double {
        guard weeklyBudget > 0 else { return 0 }
        return min(100, weekTotals.cost / weeklyBudget * 100)
    }

    /// Multi-day forecast: at current median daily burn, when would the rolling-7d
    /// total reach the weekly budget? See WeeklyForecast.compute.
    var weeklyForecast: WeeklyForecast {
        WeeklyForecast.compute(
            entries: allEntries,
            weekTotalsCost: weekTotals.cost,
            weeklyBudget: weeklyBudget,
            now: Date()
        )
    }

    public var menuBarLabel: String {
        switch menuBarMode {
        case .cost:
            let cost = todayTotals.cost
            return cost < 0.01 ? "$0.00" : String(format: "$%.2f", cost)
        case .tokens:
            return formatCompact(todayTotals.tokens)
        case .blockPercent:
            return String(format: "%.0f%%", blockRateLimitPercent)
        }
    }

    public var menuBarColor: Color {
        quotaColor(blockRateLimitPercent)
    }
}

// MARK: - Supporting types

enum MenuBarMode: String, CaseIterable, Identifiable {
    case cost         = "Today Cost"
    case tokens       = "Today Tokens"
    case blockPercent = "Block %"
    var id: String { rawValue }
}

enum HistoryGraphMode: String, CaseIterable, Identifiable {
    case cost   = "Cost"
    case tokens = "Tokens"
    var id: String { rawValue }
}

enum RiskTier {
    case onTrack        // projected < 80%
    case watch          // 80-95%
    case atRisk         // 95-105%
    case overrun        // > 105%
    case indeterminate  // projection confidence too low to render a tier

    var label: String {
        switch self {
        case .onTrack:       return "On track"
        case .watch:         return "Watch"
        case .atRisk:        return "At risk"
        case .overrun:       return "Overrun"
        case .indeterminate: return "—"
        }
    }

    var color: Color {
        switch self {
        case .onTrack:       return .green
        case .watch:         return .yellow
        case .atRisk:        return .orange
        case .overrun:       return .red
        case .indeterminate: return .secondary
        }
    }

    /// Pure function so the gating logic is testable without constructing AppState.
    /// Returns `.indeterminate` when projection confidence is `.low` — avoids painting a
    /// risk colour over a number the estimator itself doesn't trust.
    static func evaluate(
        projectedCost: Double,
        costLimit: Double,
        confidence: BurnRateEstimator.Confidence
    ) -> RiskTier {
        guard confidence != .low else { return .indeterminate }
        let ratio = projectedCost / max(0.01, costLimit)
        switch ratio {
        case ..<0.80:  return .onTrack
        case ..<0.95:  return .watch
        case ..<1.05:  return .atRisk
        default:       return .overrun
        }
    }
}

// MARK: - Formatters (local to this module)

func formatCompact(_ count: Int) -> String {
    switch count {
    case ..<1_000:         return "\(count)"
    case ..<1_000_000:     return String(format: "%.0fk", Double(count) / 1_000)
    default:               return String(format: "%.1fM", Double(count) / 1_000_000)
    }
}

func formatTokensFull(_ count: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
}

func formatCost(_ cost: Double) -> String {
    if cost < 0.001 { return "$0.00" }
    if cost < 1 { return String(format: "$%.4f", cost) }
    return String(format: "$%.2f", cost)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600
    let m = (s % 3600) / 60
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    return "\(m)m"
}

func quotaColor(_ percent: Double) -> Color {
    if percent < 50 { return .green }
    if percent < 80 { return .orange }
    return .red
}
