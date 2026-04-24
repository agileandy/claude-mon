import Foundation
import OSLog
import UserNotifications

private let log = Logger(subsystem: "com.andyspamer.claude-mon", category: "alerts")

/// Owns the UNUserNotificationCenter interaction: permission flow + delivery.
/// Threshold/spike/digest LOGIC lives in `AlertCenter.evaluate` (pure function) —
/// this actor only handles the side-effecting bits so tests can exercise the rules
/// without needing the OS notification framework.
///
/// Notifications on macOS require the binary to be a proper `.app` bundle with an
/// Info.plist and `CFBundleIdentifier`. A naked `swift run` executable has no bundle
/// and `UNUserNotificationCenter.current()` throws on init. We gate every call on
/// `Bundle.main.bundleIdentifier` so the app still runs in dev (returning
/// `notificationsAvailable == false`); wrap as an `.app` to get real notifications.
actor AlertCenter {
    static let shared = AlertCenter()

    /// False when the executable isn't bundled (`swift run …`). All UN calls no-op.
    nonisolated let notificationsAvailable: Bool = Bundle.main.bundleIdentifier != nil

    /// Lazy accessor — touching `UNUserNotificationCenter.current()` from a naked exe
    /// traps, so we only touch it once we've confirmed there's a bundle.
    private var un: UNUserNotificationCenter? {
        guard notificationsAvailable else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Request notification permission. Returns `true` if granted. Returns `false`
    /// immediately when the binary isn't bundled — no-op in dev.
    func requestAuthorization() async -> Bool {
        guard let un else {
            log.notice("requestAuthorization skipped — no bundle identifier")
            return false
        }
        do {
            let granted = try await un.requestAuthorization(options: [.alert, .sound, .badge])
            log.notice("requestAuthorization granted=\(granted)")
            return granted
        } catch {
            log.error("requestAuthorization threw: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Permission state. Returns `.notDetermined` when notifications aren't
    /// available in this environment so the UI can render a consistent placeholder.
    func authorizationStatus() async -> UNAuthorizationStatus {
        guard let un else { return .notDetermined }
        let status = await un.notificationSettings().authorizationStatus
        log.debug("authorizationStatus=\(status.rawValue)")
        return status
    }

    /// Best-effort delivery. No-ops when notifications aren't available or the OS
    /// rejects the request; never throws.
    func deliver(_ alert: Alert) async {
        guard let un else {
            log.notice("deliver(\(alert.id, privacy: .public)) skipped — no bundle")
            return
        }
        let settings = await un.notificationSettings()
        log.notice("deliver(\(alert.id, privacy: .public)) auth=\(settings.authorizationStatus.rawValue) alertStyle=\(settings.alertStyle.rawValue) bundle=\(Bundle.main.bundleIdentifier ?? "nil", privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body  = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        do {
            try await un.add(request)
            log.notice("deliver(\(alert.id, privacy: .public)) accepted by UNUserNotificationCenter")
        } catch {
            log.error("deliver(\(alert.id, privacy: .public)) threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pure evaluation logic (stub — filled in in WS2.2+)

    /// Inputs the evaluator needs to decide which alerts (if any) to fire.
    /// Kept as a value type so it's trivially Sendable and test-friendly.
    struct Input: Sendable {
        let now: Date
        let blockStartTime: Date?
        let blockRateLimitPercent: Double
        let rateLimitSource: RateLimitSource
        /// IDs of alerts already fired for the current block/day (persisted).
        let alreadyFiredKeys: Set<String>
        let alertsEnabled: Bool
        let onlyAlertOnLiveData: Bool
        /// Rolling-hour 5-min burn buckets for spike detection. Oldest first, most recent
        /// complete bucket last. Empty when no active block or not enough history.
        let recentBurnBuckets: [BurnRateEstimator.Bucket]
        /// Daily digest context — see nested `Digest`. Passing a default-constructed
        /// `Digest()` disables digest evaluation.
        let digest: Digest
        /// Calendar used for "today" boundaries in the digest check. Injectable so
        /// tests can run in a deterministic timezone.
        let calendar: Calendar

        enum RateLimitSource: String, Sendable, Equatable {
            case live, estimate
        }

        struct Digest: Sendable, Equatable {
            var enabled: Bool = false
            var hour: Int = 18        // 6pm local default
            var minute: Int = 0
            var todayCost: Double = 0
            var topModel: String? = nil
            /// Positive = today costs more than yesterday so far. Nil when no
            /// yesterday data.
            var percentChangeVsYesterday: Double? = nil
        }
    }

    /// Returns the alerts that should be fired right now given `input`. Pure — no
    /// state, no side-effects, no SDK calls. Caller is responsible for actually
    /// delivering via `deliver(_:)` and persisting the fired keys.
    static func evaluate(input: Input) -> [Alert] {
        guard input.alertsEnabled else { return [] }

        var alerts: [Alert] = []

        // Per-block alerts (threshold + spike) only run when there's an active block.
        if let blockStart = input.blockStartTime {
            let blockKey = Int(blockStart.timeIntervalSince1970)

            // Threshold alerts — respect the source policy. Estimate drifts ~2× from
            // truth, so firing at "75% of a 2×-wrong number" is noisy; default to live-only.
            let thresholdSourceOk = !(input.onlyAlertOnLiveData && input.rateLimitSource == .estimate)
            if thresholdSourceOk {
                for threshold in thresholds where input.blockRateLimitPercent >= threshold {
                    let id = "threshold:\(blockKey):\(Int(threshold))"
                    guard !input.alreadyFiredKeys.contains(id) else { continue }
                    alerts.append(Alert(
                        id: id,
                        category: .threshold,
                        title: thresholdTitle(threshold),
                        body: thresholdBody(threshold, pct: input.blockRateLimitPercent),
                        createdAt: input.now
                    ))
                }
            }

            // Spike alert — fire at most once per block. Independent of live/estimate
            // source: this is a local burn-rate signal from our own journal, not the
            // server-side rate-limit metric.
            let spikeId = "spike:\(blockKey)"
            if !input.alreadyFiredKeys.contains(spikeId),
               let spike = detectSpike(buckets: input.recentBurnBuckets) {
                alerts.append(Alert(
                    id: spikeId,
                    category: .spike,
                    title: "Burn rate spike",
                    body: "Last 5 min: \(formatCostCompact(spike.latest)) vs ~\(formatCostCompact(spike.median))/5min median. Check your model choice.",
                    createdAt: input.now
                ))
            }
        }

        // Daily digest — day-level, independent of active block. Fires once per
        // calendar day once the wall clock passes the configured hour:minute.
        if let digestAlert = evaluateDigest(input: input) {
            alerts.append(digestAlert)
        }

        return alerts
    }

    // MARK: - Digest

    private static func evaluateDigest(input: Input) -> Alert? {
        let d = input.digest
        guard d.enabled else { return nil }

        let today = input.calendar.startOfDay(for: input.now)
        guard let digestAt = input.calendar.date(
            bySettingHour: d.hour, minute: d.minute, second: 0, of: today
        ), input.now >= digestAt else { return nil }

        let dayKey = digestDayKey(for: today, calendar: input.calendar)
        let id = "digest:\(dayKey)"
        guard !input.alreadyFiredKeys.contains(id) else { return nil }

        return Alert(
            id: id,
            category: .digest,
            title: "Today's claude-mon digest",
            body: digestBody(d: d),
            createdAt: input.now
        )
    }

    private static func digestDayKey(for day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func digestBody(d: Input.Digest) -> String {
        var parts: [String] = ["Today: \(formatCostCompact(d.todayCost))"]
        if let model = d.topModel { parts.append("top model: \(model)") }
        if let delta = d.percentChangeVsYesterday {
            let sign = delta >= 0 ? "+" : ""
            parts.append("\(sign)\(Int(delta.rounded()))% vs yesterday")
        }
        return parts.joined(separator: " · ")
    }

    /// Returns spike info when the most recent complete bucket's cost exceeds 3× the
    /// median of the preceding buckets — provided the absolute amount is meaningful
    /// (≥ $0.05, so a $0.01 prompt doesn't fire an alert just because the window was
    /// entirely zero before it). `nil` means no spike.
    private static func detectSpike(
        buckets: [BurnRateEstimator.Bucket]
    ) -> (latest: Double, median: Double)? {
        guard buckets.count >= 4, let latest = buckets.last else { return nil }
        let prior = buckets.dropLast().map { $0.cost }.sorted()
        let n = prior.count
        let median = n % 2 == 1
            ? prior[n / 2]
            : (prior[n / 2 - 1] + prior[n / 2]) / 2
        // Floor at $0.05 absolute so zero-history blocks don't emit alerts on trivial spend.
        let threshold = max(median * 3, 0.05)
        guard latest.cost > threshold else { return nil }
        return (latest: latest.cost, median: median)
    }

    private static func formatCostCompact(_ c: Double) -> String {
        String(format: "$%.2f", c)
    }

    /// Exposed for tests; stable ordering (low → high) means jumping from 0% to 100%
    /// between two polls fires 75, 90, 100 in that order.
    static let thresholds: [Double] = [75, 90, 100]

    private static func thresholdTitle(_ t: Double) -> String {
        switch t {
        case 100: return "Block limit reached"
        case 90:  return "Block 90% used"
        default:  return "Block \(Int(t))% used"
        }
    }

    private static func thresholdBody(_ t: Double, pct: Double) -> String {
        "At \(Int(pct.rounded()))% of the 5h Claude Code rate limit. Ease off to avoid hitting the cap."
    }
}
