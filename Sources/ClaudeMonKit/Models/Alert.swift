import Foundation

/// A single notification the app wants to deliver. Pure value — no side-effects,
/// no SDK dependencies — so alert-generation logic stays testable.
struct Alert: Sendable, Equatable {
    enum Category: String, Sendable, Equatable {
        case threshold   // 75 / 90 / 100% of rate-limit block
        case spike       // 5-min bucket burn ≥ 3× rolling-hour median
        case digest      // end-of-day summary
        case test        // user-triggered verification from Settings
    }

    /// Stable, deterministic. Used both for OS-level dedup (UNNotificationRequest
    /// identifier) and for the `alreadyFiredKeys` set in evaluator input.
    /// Format: `<category>:<block-or-day-key>:<variant>`
    let id: String
    let category: Category
    let title: String
    let body: String
    let createdAt: Date
}
