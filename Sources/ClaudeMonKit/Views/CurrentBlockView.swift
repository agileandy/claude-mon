import SwiftUI

struct CurrentBlockView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let block = state.activeBlock {
                    activeSection(block)
                } else {
                    noActiveBlock
                }
                periodTotalsSection
            }
            .padding(12)
        }
    }

    // MARK: - Active block

    private func activeSection(_ block: SessionBlock) -> some View {
        VStack(spacing: 10) {
            // Block header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Block")
                        .font(.headline)
                    Text(blockTimeRange(block))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let resetsAt = state.blockResetsAt {
                    let remaining = resetsAt.timeIntervalSinceNow
                    if remaining > 0 {
                        Label(formatDuration(remaining) + " left", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Block quota row: shows the rate-limit % (live from Claude when available,
            // estimate from local message-count as fallback), plus raw message fraction
            // and $-value burned this block (informational only).
            blockQuotaRow(block: block)

            // Token breakdown (no limit — Claude console doesn't track tokens)
            HStack(spacing: 12) {
                statBox(title: "Input",        value: formatCompact(block.totalInputTokens))
                statBox(title: "Output",       value: formatCompact(block.totalOutputTokens))
                statBox(title: "Cache write",  value: formatCompact(block.totalCacheCreationTokens))
                statBox(title: "Cache read",   value: formatCompact(block.totalCacheReadTokens))
            }

            Divider()

            // Burn rate row
            HStack(spacing: 16) {
                statBox(title: "Burn rate", value: formatCost(block.burnRateCostPerHour) + "/hr")
                statBox(title: "Tokens/hr", value: formatCompact(Int(block.burnRateTokensPerHour)))
                statBox(title: "Projected", value: formatCost(block.projectedCost))
            }

            Divider()
            predictionSection(block: block)

            // Model breakdown
            if !block.modelBreakdown.isEmpty {
                Divider()
                ModelBreakdownView(breakdown: block.modelBreakdown, totalCost: block.totalCost)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var noActiveBlock: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No active session")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code conversation\nto see live metrics.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Prediction

    @ViewBuilder
    private func predictionSection(block: SessionBlock) -> some View {
        let risk = state.blockRisk
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Prediction")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(risk.color).frame(width: 7, height: 7)
                    Text(risk.label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(risk.color)
                }
            }

            predictionRow("Budget left",
                          value: formatCost(state.runwayRemainingCost))

            if let hit = state.limitHitAt, state.limitHitBeforeBlockEnd {
                predictionRow("Hits limit at",
                              value: formatClock(hit) + "  (" + formatDuration(state.runwaySecondsAtBurn ?? 0) + ")")
            } else if block.burnRateCostPerHour > 0 {
                predictionRow("Hits limit at",
                              value: "— stays under")
            }

            predictionRow("End-of-block",
                          value: formatCost(block.projectedCost))

            if let caveat = confidenceCaveat(block.projectionConfidence) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text(caveat)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
    }

    private func confidenceCaveat(_ c: BurnRateEstimator.Confidence) -> String? {
        switch c {
        case .high:   return nil
        case .medium: return "Estimate — pace may vary."
        case .low:    return "Low confidence — pace too variable to project."
        }
    }

    private func predictionRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func formatClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    // MARK: - Period totals

    private var periodTotalsSection: some View {
        VStack(spacing: 8) {
            PeriodAccordionRow(label: "Today", totals: state.todayTotals)
            Divider()
            PeriodAccordionRow(
                label: "Rolling 7d",
                totals: state.weekTotals,
                trailing: AnyView(weekTrailing),
                subhead: AnyView(weekDeltaBadge)
            ) {
                if state.weeklyBudget > 0 {
                    QuotaBar(percent: state.weeklyBudgetPercent)
                        .padding(.vertical, 2)
                }
                HStack {
                    Text("Prior 7d")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCost(state.prevWeekTotals.cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                forecastLine
            }
            Divider()
            PeriodAccordionRow(label: "This month", totals: state.monthTotals)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var forecastLine: some View {
        let f = state.weeklyForecast
        switch f.outcome {
        case .reachesCap(let hitDate, let days):
            HStack {
                Text("At pace")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("hits budget \(shortDate(hitDate))  (\(daysPhrase(days)))")
                    .font(.caption2)
                    .foregroundStyle(days < 3 ? .orange : .secondary)
                    .monospacedDigit()
            }
        case .alreadyExceeded:
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                Text("Over budget — ease off")
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
        case .staysUnder, .unavailable:
            EmptyView()
        }
    }

    private func shortDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        return df.string(from: d)
    }

    private func daysPhrase(_ days: Double) -> String {
        if days < 1 { return "today" }
        if days < 2 { return "tomorrow" }
        return "\(Int(days.rounded()))d"
    }

    @ViewBuilder
    private var weekDeltaBadge: some View {
        let delta = state.weekVsPrevCostDelta
        let pct   = state.weekVsPrevCostDeltaPct
        if abs(pct) > 0.1 {
            let arrow = delta >= 0 ? "▲" : "▼"
            let color: Color = delta >= 0 ? .orange : .green
            Text("\(arrow) \(String(format: "%.0f%%", abs(pct)))")
                .font(.caption2)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var weekTrailing: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if state.weeklyBudget > 0 {
                Text("\(formatCost(state.weekTotals.cost)) / \(formatCost(state.weeklyBudget))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } else {
                Text(formatCost(state.weekTotals.cost))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Text(formatCompact(state.weekTotals.tokens) + " tok")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Helpers

    private func blockQuotaRow(block: SessionBlock) -> some View {
        let pct = state.blockRateLimitPercent
        let isLive = state.blockRateLimitSource == .live

        return VStack(alignment: .leading, spacing: 6) {
            // Headline: the rate-limit %. When live, this matches Claude's console
            // exactly. When estimated (statusline tee missing or stale), it's a
            // message-count approximation and we label it with "(est.)" so the user
            // knows not to treat it as authoritative.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Block")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isLive {
                    Text("(est.)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(quotaColor(pct))
                    .monospacedDigit()
            }

            QuotaBar(percent: pct)
                .frame(height: 6)

            // Sub-line: local context — message count seen by this machine + $-value.
            // Both are informational when we're using the live %; they're the basis of
            // the estimate when we're not.
            HStack(alignment: .firstTextBaseline) {
                Text("\(formatTokensFull(block.messageCount)) / \(formatTokensFull(state.plan.messagesPerBlock)) msg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("\(formatCost(block.totalCost)) value")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private func quotaRow(label: String, used: String, limit: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(used) / \(limit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(quotaColor(percent))
                    .monospacedDigit()
                Text(String(format: "%.0f%%", percent))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
                    .monospacedDigit()
            }
            QuotaBar(percent: percent)
        }
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func blockTimeRange(_ block: SessionBlock) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return "\(fmt.string(from: block.startTime)) – \(fmt.string(from: block.startTime.addingTimeInterval(5 * 3600)))"
    }
}

// MARK: - Shared quota bar

struct QuotaBar: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(quotaColor(percent))
                    .frame(width: max(4, geo.size.width * CGFloat(min(percent, 100)) / 100))
            }
        }
        .frame(height: 6)
    }
}
