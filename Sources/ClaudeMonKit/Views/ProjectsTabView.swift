import SwiftUI

struct ProjectsTabView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.projectTotals.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    header
                    ForEach(state.projectTotals) { p in
                        ProjectRowView(project: p, isFiltered: state.selectedProjectFilter == p.dir) {
                            tapRow(p)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(12)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Projects · last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if state.selectedProjectFilter != nil {
                Button("Clear filter") {
                    state.selectedProjectFilter = nil
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No project activity yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Open a Claude Code session in any directory; it'll appear here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Tap behaviour: if the project is already the active filter, clear it; otherwise
    /// set the filter to that project AND switch back to the Now tab so the user
    /// immediately sees their work scoped to that repo.
    private func tapRow(_ project: ProjectAggregate) {
        if state.selectedProjectFilter == project.dir {
            state.selectedProjectFilter = nil
        } else {
            state.selectedProjectFilter = project.dir
            state.selectedTab = 0
        }
    }
}

// MARK: - Row

struct ProjectRowView: View {
    let project: ProjectAggregate
    let isFiltered: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if isFiltered {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(project.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let model = project.modelBreakdown.first?.model {
                            Text(model)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(project.messageCount) msg")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 4)
                Sparkline(values: project.daily7)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCost(project.weekCost))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    deltaBadge
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isFiltered ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deltaBadge: some View {
        if project.prevWeekCost > 0.001 {
            let delta = (project.weekCost - project.prevWeekCost) / project.prevWeekCost * 100
            if abs(delta) >= 1 {
                let arrow = delta >= 0 ? "▲" : "▼"
                let color: Color = delta >= 0 ? .orange : .green
                Text("\(arrow) \(String(format: "%.0f%%", abs(delta)))")
                    .font(.caption2)
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 0, 0.001)
            let n = max(values.count, 1)
            let totalGap: CGFloat = CGFloat(n - 1) * 1.5
            let barWidth = max(2, (geo.size.width - totalGap) / CGFloat(n))
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(v > 0 ? 0.55 : 0.15))
                        .frame(width: barWidth, height: max(2, CGFloat(v / maxV) * geo.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 56, height: 18)
    }
}
