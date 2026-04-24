import SwiftUI

struct PeriodAccordionRow<Detail: View>: View {
    let label: String
    let totals: PeriodTotals
    let trailing: AnyView?
    let subhead: AnyView?
    @ViewBuilder let detail: () -> Detail

    @State private var expanded: Bool = false

    init(
        label: String,
        totals: PeriodTotals,
        trailing: AnyView? = nil,
        subhead: AnyView? = nil,
        @ViewBuilder detail: @escaping () -> Detail = { EmptyView() }
    ) {
        self.label = label
        self.totals = totals
        self.trailing = trailing
        self.subhead = subhead
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let subhead {
                        subhead
                    }
                    Spacer()
                    if let trailing {
                        trailing
                    } else {
                        defaultTrailing
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.leading, 15)
                    .padding(.top, 4)
            }
        }
    }

    private var defaultTrailing: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(formatCost(totals.cost))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(formatCompact(totals.tokens) + " tok")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(totals.messages) messages")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTokensFull(totals.tokens) + " tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !totals.modelBreakdown.isEmpty {
                ForEach(totals.modelBreakdown) { item in
                    modelRow(item)
                }
            }
            detail()
        }
    }

    private func modelRow(_ item: ModelAggregate) -> some View {
        let fraction = totals.cost > 0 ? item.cost / totals.cost : 0
        return HStack(spacing: 8) {
            Text(item.model)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(modelColor(item.model))
                        .frame(width: max(2, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 5)
            Text(formatCost(item.cost))
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            Text(String(format: "%.0f%%", fraction * 100))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func modelColor(_ model: String) -> Color {
        switch model {
        case "Opus":  return .purple
        case "Haiku": return .teal
        default:      return .blue
        }
    }
}
