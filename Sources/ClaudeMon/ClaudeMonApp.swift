import SwiftUI
import AppKit
import ClaudeMonKit

@main
struct ClaudeMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
                .onChange(of: appState.isPinned) { _, pinned in
                    if pinned {
                        PinnedPanelController.shared.show(with: appState)
                    } else {
                        PinnedPanelController.shared.hide()
                    }
                }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                Text(appState.menuBarLabel)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(appState.menuBarColor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.andyspamer.claude-mon"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            running.first { $0 != .current }?.activate()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
