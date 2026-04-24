import SwiftUI
import UserNotifications

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

                section("Alerts") {
                    alertsSection
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

    private var alertsSection: some View {
        @Bindable var s = state
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notifications")
                    .font(.caption)
                Spacer()
                Text(authLabel)
                    .font(.caption2)
                    .foregroundStyle(authColor)
            }
            if !state.notificationsAvailable {
                Text("Notifications unavailable — the binary isn't running as a macOS .app bundle. Build with `scripts/make-app.sh` and launch the .app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if state.notificationAuth == .notDetermined || state.notificationAuth == nil {
                Button("Grant permission") {
                    Task { await state.requestNotificationAuth() }
                }
                .controlSize(.small)
            } else if state.notificationAuth == .denied {
                Text("Permission denied. Enable in System Settings → Notifications → claude-mon, then relaunch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("Send test alert") {
                Task { await state.fireTestAlert() }
            }
            .controlSize(.small)
            .disabled(!state.notificationsAvailable)

            Divider().padding(.vertical, 2)

            // Per-category toggles. Each is independently actionable; the master
            // "Enable alerts" switch gates all three at evaluation time.
            Toggle("Enable alerts", isOn: $s.alertsEnabled)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Toggle("Only alert on live data", isOn: $s.onlyAlertOnLiveData)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Text("When on, threshold alerts (75/90/100%) suppress unless the rate-limit number came from Claude's server. Spike alerts always fire.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Toggle("Daily digest", isOn: $s.digestEnabled)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
            HStack {
                Text("Digest time")
                    .font(.caption)
                Spacer()
                DatePicker("",
                           selection: digestTimeBinding,
                           displayedComponents: [.hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .disabled(!state.digestEnabled)
            }

            Text("Test fires a single notification immediately so you can verify delivery. Threshold + spike + digest all use the same channel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Bridges the two Int defaults (digestHour, digestMinute) to a SwiftUI DatePicker.
    private var digestTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = state.digestHour
                comps.minute = state.digestMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                state.digestHour = c.hour ?? 18
                state.digestMinute = c.minute ?? 0
            }
        )
    }

    private var authLabel: String {
        switch state.notificationAuth {
        case .authorized:       return "Granted"
        case .provisional:      return "Provisional"
        case .ephemeral:        return "Ephemeral"
        case .denied:           return "Denied"
        case .notDetermined:    return "Not requested"
        case nil:               return "Checking…"
        @unknown default:       return "Unknown"
        }
    }

    private var authColor: Color {
        switch state.notificationAuth {
        case .authorized, .provisional: return .green
        case .denied:                   return .red
        default:                        return .secondary
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
