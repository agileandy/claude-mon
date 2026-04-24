import Foundation

struct SessionBlock: Identifiable, Sendable {
    let id: UUID
    let startTime: Date
    let endTime: Date      // timestamp of last entry in this block
    let isActive: Bool     // endTime is within 5 hours of now

    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheCreationTokens: Int
    let totalCacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let messageCount: Int
    let modelBreakdown: [ModelAggregate]  // sorted by cost desc

    // Computed for active block only (safe to read on any block; only meaningful when isActive)
    let elapsedHours: Double
    let remainingSeconds: TimeInterval    // seconds until 5h window closes (may be negative if overrun)
    let burnRateCostPerHour: Double
    let burnRateTokensPerHour: Double
    let projectedCost: Double
    let projectedTokens: Int
}

extension SessionBlock {
    static func build(from entries: [UsageEntry], now: Date = Date()) -> SessionBlock {
        precondition(!entries.isEmpty)

        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let start = sorted.first!.timestamp
        let end   = sorted.last!.timestamp

        let blockWindowEnd = start.addingTimeInterval(5 * 3600)
        let active = now < blockWindowEnd

        var totalInput = 0, totalOutput = 0, totalCacheCreate = 0, totalCacheRead = 0
        var costByModel: [String: (tokens: Int, cost: Double)] = [:]

        for e in sorted {
            totalInput       += e.inputTokens
            totalOutput      += e.outputTokens
            totalCacheCreate += e.cacheCreationTokens
            totalCacheRead   += e.cacheReadTokens

            let key = e.displayModel
            var agg = costByModel[key] ?? (tokens: 0, cost: 0)
            agg.tokens += e.totalTokens
            agg.cost   += e.cost
            costByModel[key] = agg
        }

        let totalTok = totalInput + totalOutput + totalCacheCreate + totalCacheRead
        let totalCostActual = sorted.reduce(0.0) { $0 + $1.cost }

        let breakdown = costByModel.map { ModelAggregate(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.cost > $1.cost }

        let elapsedH = max(0.001, now.timeIntervalSince(start) / 3600)
        let remaining = blockWindowEnd.timeIntervalSince(now)
        let burnCost  = active ? totalCostActual / elapsedH : 0
        let burnTok   = active ? Double(totalTok) / elapsedH : 0
        let projCost  = active && remaining > 0 ? totalCostActual + burnCost * (remaining / 3600) : totalCostActual
        let projTok   = active && remaining > 0 ? totalTok + Int(burnTok * (remaining / 3600)) : totalTok

        return SessionBlock(
            id: UUID(),
            startTime: start,
            endTime: end,
            isActive: active,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheCreationTokens: totalCacheCreate,
            totalCacheReadTokens: totalCacheRead,
            totalTokens: totalTok,
            totalCost: totalCostActual,
            messageCount: sorted.count,
            modelBreakdown: breakdown,
            elapsedHours: elapsedH,
            remainingSeconds: remaining,
            burnRateCostPerHour: burnCost,
            burnRateTokensPerHour: burnTok,
            projectedCost: projCost,
            projectedTokens: projTok
        )
    }
}
