import AppKit
import SwiftUI

@MainActor
final class PinnedPanelController: NSObject, NSWindowDelegate {
    static let shared = PinnedPanelController()

    private var panel: NSPanel?
    private weak var state: AppState?

    func show(with state: AppState) {
        self.state = state

        if let panel {
            panel.orderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "claude-mon"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: MenuBarContentView().environment(state)
        )
        panel.center()
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.state?.isPinned = false
        }
    }
}
