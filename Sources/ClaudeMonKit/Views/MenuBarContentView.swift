import SwiftUI

public struct MenuBarContentView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            headerRow
            if state.selectedProjectFilter != nil {
                filterBanner
            }
            Divider()
            tabPicker(selected: $s.selectedTab)
            Divider()

            Group {
                switch state.selectedTab {
                case 0: CurrentBlockView()
                case 1: historyTab
                case 2: ProjectsTabView()
                case 3: SettingsView()
                default: CurrentBlockView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("claude-mon")
                .font(.headline)
            Spacer()
            if state.isRefreshing {
                ProgressView().scaleEffect(0.6)
            } else {
                Text("next in " + formatCountdown(state.countdownSeconds))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Button {
                state.isPinned.toggle()
            } label: {
                Image(systemName: state.isPinned ? "pin.fill" : "pin")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.isPinned ? Color.accentColor : Color.secondary)
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filter banner

    /// Shown under the header when a project filter is active. Reminds the user that
    /// most of what they see is scoped — and that the rate-limit gauge stays global.
    private var filterBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
            Text("Filtered: \(state.selectedProjectDisplay ?? "?")")
                .font(.caption2)
                .lineLimit(1)
            Spacer()
            Text("rate limit is global")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button {
                state.selectedProjectFilter = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.10))
    }

    // MARK: - History tab (chart + session list)

    private var historyTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                HistoryChartView()
                SessionListView()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Tab picker

    private func tabPicker(selected: Binding<Int>) -> some View {
        let tabs: [(String, String)] = [
            ("Now",      "bolt.fill"),
            ("History",  "chart.bar.fill"),
            ("Projects", "folder.fill"),
            ("Settings", "gearshape")
        ]
        return HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                Button {
                    selected.wrappedValue = i
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tabs[i].1).font(.caption)
                        Text(tabs[i].0).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(selected.wrappedValue == i ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundStyle(selected.wrappedValue == i ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                if i < tabs.count - 1 { Divider().frame(height: 20) }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func formatCountdown(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        if m < 60 { return r == 0 ? "\(m)m" : "\(m)m \(r)s" }
        let h = m / 60
        let mr = m % 60
        return mr == 0 ? "\(h)h" : "\(h)h \(mr)m"
    }
}
