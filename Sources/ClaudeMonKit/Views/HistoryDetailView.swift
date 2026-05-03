import SwiftUI
import Charts

/// Full-window companion to `HistoryChartView`. Shows the same `timelineBuckets`
/// without the popover's height clamp, plus a numeric breakdown table and a
/// cost/tokens toggle.
struct HistoryDetailView: View {
    @Environment(AppState.self) private var state

    private var buckets: [TimeBucket] { state.timelineBuckets }
    private var mode: HistoryGraphMode { state.historyGraphMode }

    private func value(_ bucket: TimeBucket) -> Double {
        switch mode {
        case .cost:   return bucket.totalCost
        case .tokens: return Double(bucket.totalTokens)
        }
    }

    var body: some View {
        @Bindable var bindable = state
        VStack(alignment: .leading, spacing: 12) {
            header(bindable: $bindable)

            if buckets.isEmpty || buckets.allSatisfy({ value($0) == 0 }) {
                emptyChart
            } else {
                chart
                granularityLegend
                Divider()
                breakdownTable
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 420)
    }

    private func header(bindable: Bindable<AppState>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage history")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Daily for the last week, weekly for ~3 weeks before that, monthly back ~1 year, yearly older.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: bindable.historyGraphMode) {
                ForEach(HistoryGraphMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .labelsHidden()
        }
    }

    private var chart: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Bucket", bucket.label),
                y: .value(yAxisLabel, value(bucket)),
                width: .ratio(0.7)
            )
            .foregroundStyle(barColor(bucket.granularity))
            .cornerRadius(3)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                if value(bucket) > 0 {
                    Text(formatShort(value(bucket)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let n = v.as(Double.self) {
                        Text(formatShort(n)).font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 16)) { v in
                AxisValueLabel().font(.caption2)
            }
        }
        .frame(minHeight: 220)
    }

    private var granularityLegend: some View {
        HStack(spacing: 16) {
            ForEach(activeGranularities, id: \.self) { g in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(g))
                        .frame(width: 10, height: 10)
                    Text(legendName(g))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(buckets.count) buckets")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var breakdownTable: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Period").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Granularity").frame(width: 100, alignment: .leading)
                    Text(yAxisLabel).frame(width: 100, alignment: .trailing)
                    Text("Messages").frame(width: 100, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
                Divider()
                ForEach(buckets.reversed()) { bucket in
                    HStack {
                        Text(bucket.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(legendName(bucket.granularity))
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text(formatShort(value(bucket)))
                            .monospacedDigit()
                            .frame(width: 100, alignment: .trailing)
                        Text("\(bucket.messageCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No usage in the last year")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var yAxisLabel: String {
        switch mode {
        case .cost:   return "Cost"
        case .tokens: return "Tokens"
        }
    }

    private var activeGranularities: [TimeBucket.Granularity] {
        var seen = Set<TimeBucket.Granularity>()
        var ordered: [TimeBucket.Granularity] = []
        for g in [TimeBucket.Granularity.year, .month, .week, .day]
        where buckets.contains(where: { $0.granularity == g }) {
            if seen.insert(g).inserted { ordered.append(g) }
        }
        return ordered
    }

    private func legendName(_ g: TimeBucket.Granularity) -> String {
        switch g {
        case .day:   return "Daily"
        case .week:  return "Weekly"
        case .month: return "Monthly"
        case .year:  return "Yearly"
        }
    }

    private func barColor(_ g: TimeBucket.Granularity) -> Color {
        switch g {
        case .day:   return .blue
        case .week:  return .teal
        case .month: return .indigo
        case .year:  return .purple
        }
    }

    private func formatShort(_ v: Double) -> String {
        if v == 0 { return "—" }
        switch mode {
        case .cost:
            if v < 1 { return String(format: "¢%.0f", v * 100) }
            return String(format: "$%.2f", v)
        case .tokens:
            return formatCompact(Int(v))
        }
    }
}
