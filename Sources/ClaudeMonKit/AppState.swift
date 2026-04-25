import Foundation
import Observation
import SwiftUI
import UserNotifications

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

    /// Per-project rollups over the rolling 7d window. Sorted by week cost desc.
    /// Drives the Projects tab and the header filter dropdown.
    var projectTotals: [ProjectAggregate] = []

    /// Currently-selected project filter (the raw `projectDir` key), or `nil` for "all".
    /// Affects period totals (today/week/prev/month) and history. Block-level rate-limit
    /// stuff (activeBlock, blockRateLimitPercent, burn rate, projection) intentionally
    /// stays GLOBAL — Claude enforces rate limits across all projects, so filtering
    /// would mislead the user.
    var selectedProjectFilter: String? = UserDefaults.standard.string(forKey: "selectedProjectFilter") {
        didSet {
            if selectedProjectFilter == nil {
                UserDefaults.standard.removeObject(forKey: "selectedProjectFilter")
            } else {
                UserDefaults.standard.set(selectedProjectFilter, forKey: "selectedProjectFilter")
            }
        }
    }

    /// Server-sourced rate-limit snapshot from Claude Code's statusline. `nil` when the
    /// user hasn't installed the tee snippet, or hasn't made an API call this session.
    var liveRateLimit: LiveRateLimit?

    /// UNUserNotificationCenter authorization state. `nil` until we've checked.
    /// The Alerts section in Settings surfaces this + a grant-permission button.
    var notificationAuth: UNAuthorizationStatus?

    /// False when the binary isn't a `.app` bundle — UN is unavailable and every
    /// notification call is a no-op. Exposed so the UI can render a clear "bundle
    /// me first" hint instead of showing a grant button that silently fails.
    var notificationsAvailable: Bool { alertCenter.notificationsAvailable }

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

    /// Master on/off for threshold + spike + digest alerts. Defaults to true; user
    /// can toggle in Settings.
    var alertsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alertsEnabled") }
    }

    /// When true (default), suppress alerts that would be derived from the local
    /// message-count estimate. Estimate drifts ~2× from the live server number — it's
    /// decorative, not actionable. User can opt-in to "alert from estimate too" if
    /// they're on a machine without the statusline tee installed.
    var onlyAlertOnLiveData: Bool {
        get { UserDefaults.standard.object(forKey: "onlyAlertOnLiveData") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "onlyAlertOnLiveData") }
    }

    /// End-of-day digest enabled. Defaults to true; digest fires once per day at
    /// `digestHour:digestMinute` local time as long as alerts are enabled.
    var digestEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "digestEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "digestEnabled") }
    }
    var digestHour: Int {
        get { (UserDefaults.standard.object(forKey: "digestHour") as? Int) ?? 18 }
        set { UserDefaults.standard.set(newValue, forKey: "digestHour") }
    }
    var digestMinute: Int {
        get { (UserDefaults.standard.object(forKey: "digestMinute") as? Int) ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "digestMinute") }
    }

    var plan: PlanLimits { planType.limits }

    /// Effective block cost limit honoring the user override, else the plan default.
    var effectiveCostPerBlock: Double {
        customCostPerBlock > 0 ? customCostPerBlock : plan.costPerBlock
    }

    // MARK: - Private

    private let reader = JournalReader()
    private let liveStore = LiveRateLimitStore()
    private let alertCenter = AlertCenter.shared
    private var refreshTask: Task<Void, Never>?

    /// Alert IDs we've already delivered for the current (and recent) block(s). Keyed
    /// by stable `threshold:<blockStart>:<percent>` so re-entering a block after
    /// relaunch doesn't re-fire. Persisted to UserDefaults; filtered to current-block
    /// prefix whenever a new block starts to keep the set bounded.
    private var firedAlertIds: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "firedAlertIds") ?? [])

    public init() {
        start()
        Task { await self.refreshNotificationAuth() }
    }

    // MARK: - Alerts (WS-2 foundation)

    /// Check the current permission state without prompting. Writes to `notificationAuth`.
    func refreshNotificationAuth() async {
        notificationAuth = await alertCenter.authorizationStatus()
    }

    /// Prompt the user for notification permission. Safe to call more than once — the
    /// system shows the dialog only the first time.
    func requestNotificationAuth() async {
        _ = await alertCenter.requestAuthorization()
        await refreshNotificationAuth()
    }

    /// Manual end-to-end verification: fires one alert so the user can confirm the
    /// OS permission + delivery chain is working. Wired to the "Test alert" button
    /// in Settings.
    func fireTestAlert() async {
        let now = Date()
        let df = DateFormatter()
        df.timeStyle = .medium
        await alertCenter.deliver(Alert(
            id: "test:\(Int(now.timeIntervalSince1970))",
            category: .test,
            title: "claude-mon test alert",
            body: "Delivered at \(df.string(from: now)). Threshold alerts will use the same channel.",
            createdAt: now
        ))
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
            projectTotals   = bundle.projects
            lastError       = nil

            await evaluateAndFireAlerts()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Alert evaluation (WS-2.2)

    /// Runs after each successful refresh. Builds an `AlertCenter.Input` from the
    /// current state, asks the pure evaluator which alerts to fire, delivers each one,
    /// and persists the fired IDs so we don't re-fire on the next poll.
    private func evaluateAndFireAlerts() async {
        let before = firedAlertIds
        firedAlertIds = await AlertCoordinator.evaluateAndFire(
            snapshot: alertSnapshot(),
            firedKeys: firedAlertIds,
            deliver: { [alertCenter] alert in await alertCenter.deliver(alert) }
        )
        pruneFiredAlertIdsForCurrentBlock()
        if firedAlertIds != before {
            saveFiredAlertIds()
        }
    }

    /// Builds the per-refresh value snapshot consumed by AlertCoordinator. Stays in
    /// AppState because it pulls together state owned here (activeBlock, allEntries,
    /// settings, today/dailyHistory).
    private func alertSnapshot() -> AlertCoordinator.Snapshot {
        let sourceForAlerts: AlertCenter.Input.RateLimitSource =
            blockRateLimitSource == .live ? .live : .estimate
        return AlertCoordinator.Snapshot(
            now: Date(),
            blockStartTime: activeBlock?.startTime,
            blockRateLimitPercent: blockRateLimitPercent,
            rateLimitSource: sourceForAlerts,
            recentBurnBuckets: recentBurnBucketsForSpike(),
            alertsEnabled: alertsEnabled,
            onlyAlertOnLiveData: onlyAlertOnLiveData,
            digest: digestContext(),
            calendar: .current
        )
    }

    /// Keep the set bounded: retain only per-block keys that match the current block.
    /// Thresholds are `threshold:<epoch>:<pct>`; spikes are `spike:<epoch>`. Any key
    /// whose `<epoch>` doesn't match the current block's startTime gets dropped. Other
    /// categories (digest, WS2.4) are preserved as-is — they handle their own lifecycle.
    private func pruneFiredAlertIdsForCurrentBlock() {
        guard let blockStart = activeBlock?.startTime else { return }
        let currentBlockEpoch = "\(Int(blockStart.timeIntervalSince1970))"
        let before = firedAlertIds.count
        firedAlertIds = firedAlertIds.filter { key in
            let parts = key.split(separator: ":")
            switch parts.first {
            case "threshold", "spike":
                return parts.count >= 2 && parts[1] == currentBlockEpoch
            default:
                return true
            }
        }
        if firedAlertIds.count != before {
            saveFiredAlertIds()
        }
    }

    private func saveFiredAlertIds() {
        UserDefaults.standard.set(Array(firedAlertIds), forKey: "firedAlertIds")
    }

    /// Snapshot of today's usage for the daily digest body. Pulls the dominant model
    /// (by cost) from `todayTotals` and computes today-vs-yesterday % from the last-7
    /// daily history. Returns a disabled `Digest` when `digestEnabled` is off.
    private func digestContext() -> AlertCenter.Input.Digest {
        guard digestEnabled else { return AlertCenter.Input.Digest() }
        let today = Calendar.current.startOfDay(for: Date())
        let yesterdayCost = dailyHistory
            .first { Calendar.current.startOfDay(for: $0.date) ==
                     Calendar.current.date(byAdding: .day, value: -1, to: today) }
            .map { $0.totalCost }
        let pct: Double? = {
            guard let y = yesterdayCost, y > 0.01 else { return nil }
            return (todayTotals.cost - y) / y * 100
        }()
        return AlertCenter.Input.Digest(
            enabled: true,
            hour: digestHour,
            minute: digestMinute,
            todayCost: todayTotals.cost,
            topModel: todayTotals.modelBreakdown.first?.model,
            percentChangeVsYesterday: pct
        )
    }

    /// Last hour of 5-min buckets within the active block, used by the spike detector.
    /// Empty when there's no active block or the block is younger than one complete bucket.
    private func recentBurnBucketsForSpike() -> [BurnRateEstimator.Bucket] {
        guard let block = activeBlock else { return [] }
        let now = Date()
        let hourAgo = now.addingTimeInterval(-3600)
        let bucketStart = max(block.startTime, hourAgo)
        let entries = allEntries.filter {
            $0.timestamp >= bucketStart && $0.timestamp < now
        }
        return BurnRateEstimator.bucketize(entries: entries, from: bucketStart, to: now)
    }

    // MARK: - Derived helpers

    // MARK: - Filtered views (WS-3)

    /// Entries narrowed by `selectedProjectFilter`. Same as `allEntries` when no
    /// filter is set; views should prefer these when rendering project-scoped data.
    var filteredEntries: [UsageEntry] {
        guard let dir = selectedProjectFilter else { return allEntries }
        return allEntries.filter { $0.projectDir == dir }
    }

    /// Display name for the active filter (best-effort). Used by the header banner.
    var selectedProjectDisplay: String? {
        guard let dir = selectedProjectFilter else { return nil }
        return projectTotals.first(where: { $0.dir == dir })?.displayName
            ?? ProjectName.decode(dirName: dir).display
    }

    var displayedTodayTotals: PeriodTotals {
        selectedProjectFilter == nil ? todayTotals : UsageAggregator.today(from: filteredEntries)
    }
    var displayedWeekTotals: PeriodTotals {
        selectedProjectFilter == nil ? weekTotals : UsageAggregator.thisWeek(from: filteredEntries)
    }
    var displayedPrevWeekTotals: PeriodTotals {
        selectedProjectFilter == nil ? prevWeekTotals : UsageAggregator.previousWeek(from: filteredEntries)
    }
    var displayedMonthTotals: PeriodTotals {
        selectedProjectFilter == nil ? monthTotals : UsageAggregator.thisMonth(from: filteredEntries)
    }
    var displayedDailyHistory: [DailyAggregate] {
        selectedProjectFilter == nil ? dailyHistory : UsageAggregator.last7Days(from: filteredEntries)
    }

    /// Session blocks scoped to the active filter when one is set. Rebuilt from the
    /// filtered entries — same 5h-windowing logic, but a block only appears if the
    /// filtered project contributed messages to it.
    var displayedSessionBlocks: [SessionBlock] {
        selectedProjectFilter == nil ? sessionBlocks : SessionAnalyzer.analyze(entries: filteredEntries)
    }

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
        return block.startTime.addingTimeInterval(SessionAnalyzer.blockWindow)
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
