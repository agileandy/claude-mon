import AppKit
import SwiftUI

/// Hosts the expanded `HistoryDetailView` in a standalone resizable window. Mirrors
/// `PinnedPanelController` so we don't hand-roll a different lifecycle for the second
/// detached window the app vends. Single-instance: re-clicking the expand button
/// brings the existing window forward instead of spawning a new one.
@MainActor
public final class HistoryWindowController: NSObject, NSWindowDelegate {
    public static let shared = HistoryWindowController()

    private var window: NSWindow?

    public func show(with state: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Usage history"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: HistoryDetailView().environment(state)
        )
        window.minSize = NSSize(width: 720, height: 420)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    nonisolated public func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
        }
    }
}
