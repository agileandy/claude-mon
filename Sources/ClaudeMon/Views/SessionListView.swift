import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let past = state.sessionBlocks.reversed().prefix(20)

        if past.isEmpty {
            Text("No sessions yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(past)) { block in
                    sessionRow(block)
                    if block.id != past.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    private func sessionRow(_ block: SessionBlock) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionLabel(block))
                    .font(.caption)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(formatDuration(block.endTime.timeIntervalSince(block.startTime)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                    Text(primaryModel(block))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCost(block.totalCost))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(formatCompact(block.totalTokens) + " tok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if block.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func sessionLabel(_ block: SessionBlock) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = Calendar.current.isDateInToday(block.startTime) ? "h:mm a" : "MMM d · h:mm a"
        return fmt.string(from: block.startTime)
    }

    private func primaryModel(_ block: SessionBlock) -> String {
        block.modelBreakdown.first?.model ?? "–"
    }
}
