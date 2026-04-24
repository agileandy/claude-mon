import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // MARK: - Data

    var allEntries: [UsageEntry] = []
    var sessionBlocks: [SessionBlock] = []
    var activeBlock: SessionBlock?
    var dailyHistory: [DailyAggregate] = []  // last 7 days

    var todayTotals: PeriodTotals    = PeriodTotals()
    var weekTotals: PeriodTotals     = PeriodTotals()   // rolling 7d ending now
    var prevWeekTotals: PeriodTotals = PeriodTotals()   // rolling 7d ending 7d ago
    var monthTotals: PeriodTotals    = PeriodTotals()

    // MARK: - UI State

    var selectedTab: Int = 0
    var isRefreshing: Bool = false
    var lastRefreshed: Date?
    var lastError: String?
    var countdownSeconds: Double = 0
    var isPinned: Bool = false {
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
    private var refreshTask: Task<Void, Never>?

    init() {
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
            let bundle = try await reader.loadBundle(since: usageStartDate)

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
        let ratio = block.projectedCost / max(0.01, effectiveCostPerBlock)
        switch ratio {
        case ..<0.80:  return .onTrack
        case ..<0.95:  return .watch
        case ..<1.05:  return .atRisk
        default:       return .overrun
        }
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

    var menuBarLabel: String {
        switch menuBarMode {
        case .cost:
            let cost = todayTotals.cost
            return cost < 0.01 ? "$0.00" : String(format: "$%.2f", cost)
        case .tokens:
            return formatCompact(todayTotals.tokens)
        case .blockPercent:
            return String(format: "%.0f%%", blockCostPercent)
        }
    }

    var menuBarColor: Color {
        quotaColor(blockCostPercent)
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
    case onTrack   // projected < 80%
    case watch     // 80-95%
    case atRisk    // 95-105%
    case overrun   // > 105%

    var label: String {
        switch self {
        case .onTrack: return "On track"
        case .watch:   return "Watch"
        case .atRisk:  return "At risk"
        case .overrun: return "Overrun"
        }
    }

    var color: Color {
        switch self {
        case .onTrack: return .green
        case .watch:   return .yellow
        case .atRisk:  return .orange
        case .overrun: return .red
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
