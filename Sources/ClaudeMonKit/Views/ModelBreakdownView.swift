import SwiftUI

struct ModelBreakdownView: View {
    let breakdown: [ModelAggregate]
    let totalCost: Double

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text("Models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !expanded {
                        Text(collapsedSummary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 6) {
                    ForEach(breakdown) { item in
                        modelRow(item)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var collapsedSummary: String {
        let names = breakdown.prefix(3).map(\.model).joined(separator: " · ")
        let count = breakdown.count
        return count > 3 ? "\(names) +\(count - 3)" : names
    }

    private func modelRow(_ item: ModelAggregate) -> some View {
        let fraction = totalCost > 0 ? item.cost / totalCost : 0
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
            .frame(height: 6)
            Text(formatCost(item.cost))
                .font(.caption2)
                .foregroundStyle(.primary)
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
        case "Opus":   return .purple
        case "Haiku":  return .teal
        default:       return .blue    // Sonnet
        }
    }
}
