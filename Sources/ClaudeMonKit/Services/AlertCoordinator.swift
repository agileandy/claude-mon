import Foundation

/// Owns the alert-firing pipeline that AppState used to inline:
///   build snapshot → AlertCenter.evaluate → deliver each alert → return updated firedKeys.
///
/// Pulled out so the orchestration is testable end-to-end without standing up a
/// full `AppState` (which is `@MainActor @Observable` and runs UserDefaults-backed
/// settings, a refresh loop, etc.). AppState builds a `Snapshot` from its current
/// state and a `deliver` closure that calls into the real `AlertCenter`; tests
/// build a tiny snapshot and pass a recorder closure.
///
/// State (firedAlertIds persistence) deliberately stays in AppState — only the
/// evaluation+delivery pipeline moves here.
enum AlertCoordinator {
    /// Sendable value snapshot of everything `AlertCenter.evaluate` needs.
    /// Mirrors `AlertCenter.Input` but unbundled from the pipeline so AppState
    /// can build it from its own state without re-importing UN frameworks.
    struct Snapshot: Sendable {
        let now: Date
        let blockStartTime: Date?
        let blockRateLimitPercent: Double
        let rateLimitSource: AlertCenter.Input.RateLimitSource
        let recentBurnBuckets: [BurnRateEstimator.Bucket]
        let alertsEnabled: Bool
        let onlyAlertOnLiveData: Bool
        let digest: AlertCenter.Input.Digest
        let calendar: Calendar
    }

    /// Evaluates alerts for `snapshot`, delivers each via `deliver`, and returns
    /// the updated `firedKeys` set (caller persists). Pure orchestration: zero
    /// global state, zero side effects beyond the closure.
    ///
    /// `deliver` is a closure (not a protocol) so tests can pass an arbitrary
    /// recorder without faking UNUserNotificationCenter.
    static func evaluateAndFire(
        snapshot: Snapshot,
        firedKeys: Set<String>,
        deliver: @Sendable (Alert) async -> Void
    ) async -> Set<String> {
        let input = AlertCenter.Input(
            now: snapshot.now,
            blockStartTime: snapshot.blockStartTime,
            blockRateLimitPercent: snapshot.blockRateLimitPercent,
            rateLimitSource: snapshot.rateLimitSource,
            alreadyFiredKeys: firedKeys,
            alertsEnabled: snapshot.alertsEnabled,
            onlyAlertOnLiveData: snapshot.onlyAlertOnLiveData,
            recentBurnBuckets: snapshot.recentBurnBuckets,
            digest: snapshot.digest,
            calendar: snapshot.calendar
        )
        let alerts = AlertCenter.evaluate(input: input)
        var updated = firedKeys
        for alert in alerts {
            await deliver(alert)
            updated.insert(alert.id)
        }
        return updated
    }
}
