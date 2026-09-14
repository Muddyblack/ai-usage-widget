import AppKit
import SwiftUI

/// Holds the settings window, so that reopening it brings the existing one
/// forward instead of stacking another.
@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?

    func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = i18n("AI Usage Settings")
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        // An accessory app has no Dock icon and no menu bar of its own, so its
        // windows do not come forward on their own — this asks for the one
        // activation the user just clicked for.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    /// The window's title follows the language setting like everything else.
    func retitle() {
        window?.title = i18n("AI Usage Settings")
    }
}
