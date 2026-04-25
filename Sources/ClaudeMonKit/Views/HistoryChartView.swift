import SwiftUI
import Charts

struct HistoryChartView: View {
    @Environment(AppState.self) private var state

    private var mode: HistoryGraphMode { state.historyGraphMode }

    private var blocks: [SessionBlock] {
        Array(state.displayedSessionBlocks.suffix(20))
    }

    private func value(_ block: SessionBlock) -> Double {
        switch mode {
        case .cost:   return block.totalCost
        case .tokens: return Double(block.totalTokens)
        }
    }

    private var maxValue: Double {
        blocks.map(value).max() ?? 1
    }

    private var yAxisLabel: String {
        switch mode {
        case .cost:   return "Cost"
        case .tokens: return "Tokens"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent 5h blocks · \(mode.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if blocks.isEmpty {
                emptyChart
            } else {
                Chart(blocks) { block in
                    BarMark(
                        x: .value("Block", block.startTime, unit: .hour),
                        y: .value(yAxisLabel, value(block)),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(barColor(value(block)))
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let n = v.as(Double.self) {
                                Text(formatShort(n)).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { v in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour(.defaultDigits(amPM: .omitted)))
                    }
                }
                .frame(height: 140)
                .padding(.horizontal, 12)
            }

            Divider()
        }
    }

    private var emptyChart: some View {
        Text("No session blocks yet")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func barColor(_ v: Double) -> Color {
        let fraction = maxValue > 0 ? v / maxValue : 0
        if fraction < 0.3 { return .blue.opacity(0.5) }
        if fraction < 0.7 { return .blue }
        return .purple
    }

    private func formatShort(_ v: Double) -> String {
        if v == 0 { return "" }
        switch mode {
        case .cost:
            if v < 1 { return String(format: "¢%.0f", v * 100) }
            return String(format: "$%.1f", v)
        case .tokens:
            return formatCompact(Int(v))
        }
    }
}
