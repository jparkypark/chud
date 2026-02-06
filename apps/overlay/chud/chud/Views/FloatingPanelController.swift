import SwiftUI
import AppKit

/// Notification for tab cycling
extension Notification.Name {
    static let cycleTab = Notification.Name("cycleTab")
}

/// Custom panel that intercepts Tab/Shift+Tab for tab cycling
final class KeyInterceptingPanel: NSPanel {
    override func keyDown(with event: NSEvent) {
        // Tab key
        if event.keyCode == 48 {
            let forward = !event.modifierFlags.contains(.shift)
            NotificationCenter.default.post(name: .cycleTab, object: forward)
            return
        }
        super.keyDown(with: event)
    }
}

/// A floating panel that stays on top of all windows
final class FloatingPanelController: NSObject {
    private var panel: NSPanel?
    private(set) var isVisible = false

    func showPanel(with view: some View) {
        if panel == nil {
            createPanel(with: view)
        } else {
            // Update content if panel already exists
            let hostingView = NSHostingView(rootView: view)
            panel?.contentView = hostingView
        }

        panel?.makeKeyAndOrderFront(nil)
        panel?.center()
        isVisible = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func togglePanel(with view: some View) {
        if isVisible {
            hidePanel()
        } else {
            showPanel(with: view)
        }
    }

    private func createPanel(with view: some View) {
        let panel = KeyInterceptingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Claude Code Sessions"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = false
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor

        // Hide when app deactivates
        panel.hidesOnDeactivate = false

        // Set up close behavior
        panel.delegate = self

        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView

        self.panel = panel
    }
}

extension FloatingPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
}
