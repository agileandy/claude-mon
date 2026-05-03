import SwiftUI
import Charts

struct HistoryChartView: View {
    @Environment(AppState.self) private var state

    private var mode: HistoryGraphMode { state.historyGraphMode }

    private var buckets: [TimeBucket] {
        state.timelineBuckets
    }

    private func value(_ bucket: TimeBucket) -> Double {
        switch mode {
        case .cost:   return bucket.totalCost
        case .tokens: return Double(bucket.totalTokens)
        }
    }

    private var maxValue: Double {
        buckets.map(value).max() ?? 1
    }

    private var yAxisLabel: String {
        switch mode {
        case .cost:   return "Cost"
        case .tokens: return "Tokens"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity · daily → yearly · \(mode.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    HistoryWindowController.shared.show(with: state)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open detailed history window")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if buckets.isEmpty || buckets.allSatisfy({ value($0) == 0 }) {
                emptyChart
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Bucket", bucket.label),
                        y: .value(yAxisLabel, value(bucket)),
                        width: .ratio(0.7)
                    )
                    .foregroundStyle(barColor(bucket))
                    .cornerRadius(2)
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
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 8)) { _ in
                        AxisValueLabel().font(.system(size: 8))
                    }
                }
                .frame(height: 140)
                .padding(.horizontal, 12)

                granularityLegend
                    .padding(.horizontal, 12)
            }

            Divider()
        }
    }

    private var granularityLegend: some View {
        HStack(spacing: 12) {
            ForEach(activeGranularities, id: \.self) { g in
                HStack(spacing: 3) {
                    Text(g.letter)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(legendColor(g))
                    Text(legendName(g))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }

    private var activeGranularities: [TimeBucket.Granularity] {
        var seen = Set<TimeBucket.Granularity>()
        var ordered: [TimeBucket.Granularity] = []
        for g in [TimeBucket.Granularity.year, .month, .week, .day] where buckets.contains(where: { $0.granularity == g }) {
            if seen.insert(g).inserted { ordered.append(g) }
        }
        return ordered
    }

    private func legendName(_ g: TimeBucket.Granularity) -> String {
        switch g {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        }
    }

    private var emptyChart: some View {
        Text("No usage in the last year")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func barColor(_ bucket: TimeBucket) -> Color {
        let v = value(bucket)
        let fraction = maxValue > 0 ? v / maxValue : 0
        let base = legendColor(bucket.granularity)
        if fraction < 0.3 { return base.opacity(0.5) }
        if fraction < 0.7 { return base }
        return base
    }

    private func legendColor(_ g: TimeBucket.Granularity) -> Color {
        switch g {
        case .day:   return .blue
        case .week:  return .teal
        case .month: return .indigo
        case .year:  return .purple
        }
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
