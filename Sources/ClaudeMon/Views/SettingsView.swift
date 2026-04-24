import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Plan") {
                    Picker("Subscription", selection: $s.planType) {
                        ForEach(PlanType.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    planLimitsRow
                }

                section("Tracking") {
                    DatePicker(
                        "Ignore usage before",
                        selection: $s.usageStartDate,
                        displayedComponents: [.date]
                    )
                    .font(.caption)
                    Text("Usage before this date is excluded (prior proxy plan).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                section("Limits") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Cost per 5h block")
                                .font(.caption)
                                .frame(width: 140, alignment: .leading)
                            TextField(formatCost(state.plan.costPerBlock),
                                      value: $s.customCostPerBlock,
                                      format: .number.precision(.fractionLength(0...2)))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .monospacedDigit()
                            Text("USD").font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Weekly budget")
                                .font(.caption)
                                .frame(width: 140, alignment: .leading)
                            TextField("optional",
                                      value: $s.weeklyBudget,
                                      format: .number.precision(.fractionLength(0...2)))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .monospacedDigit()
                            Text("USD").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Block default comes from plan (\(formatCost(state.plan.costPerBlock))); set 0 to revert. Weekly budget is optional — leave 0 to hide the bar.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                section("Refresh") {
                    Picker("Interval", selection: $s.refreshInterval) {
                        Text("15s").tag(15.0)
                        Text("30s").tag(30.0)
                        Text("60s").tag(60.0)
                        Text("5m").tag(300.0)
                        Text("10m").tag(600.0)
                        Text("30m").tag(1800.0)
                        Text("1h").tag(3600.0)
                    }
                    .pickerStyle(.segmented)
                }

                section("Menu Bar Shows") {
                    Picker("Display", selection: $s.menuBarMode) {
                        ForEach(MenuBarMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                section("History Graph") {
                    Picker("Graph", selection: $s.historyGraphMode) {
                        ForEach(HistoryGraphMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let err = state.lastError {
                    section("Last Error") {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(12)
        }
    }

    private var planLimitsRow: some View {
        let lim = state.plan
        return HStack(spacing: 16) {
            limitBadge(label: "Cost/block",   value: formatCost(lim.costPerBlock))
            limitBadge(label: "Messages",     value: "\(lim.messagesPerBlock)")
        }
        .frame(maxWidth: .infinity)
    }

    private func limitBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
