import Foundation

struct UsageEntry: Identifiable, Hashable, Sendable {
    let id: String         // message.id — dedup key
    let timestamp: Date
    let sessionId: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// The munged journal directory name (e.g. `-Users-andy-Dev-foo`). Acts as the
    /// stable per-project key for aggregation. Decode to a display name with
    /// `ProjectName.decode(dirName:)`. Empty string when the entry pre-dates WS-3 or
    /// the parent dir couldn't be resolved.
    let projectDir: String

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var cost: Double {
        ModelPricing.cost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens
        )
    }

    var displayModel: String {
        let lower = model.lowercased()
        if lower.contains("opus")   { return "Opus" }
        if lower.contains("haiku")  { return "Haiku" }
        if lower.contains("sonnet") { return "Sonnet" }
        return model
    }
}

// MARK: - Model aggregate grouping

struct ModelAggregate: Identifiable, Sendable {
    var id: String { model }
    let model: String
    var tokens: Int
    var cost: Double
}
