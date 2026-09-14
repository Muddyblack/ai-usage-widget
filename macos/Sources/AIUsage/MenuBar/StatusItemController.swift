import AppKit
import SwiftUI

/// The menu bar item and the popover under it.
///
/// Deliberately AppKit rather than SwiftUI's `MenuBarExtra`: the item has to
/// carry an attributed title, stay highlighted while the popover is open, and
/// be the popover's anchor view. `NSPopover` then does the part that is hard to
/// imitate and easy to get wrong — the material background, the arrow pointing
/// at the item, placement on whichever display the menu bar is on, staying
/// clear of the notch, dismissal on a click outside, and the open/close
/// animation. All of it is the system's, so it behaves like every other menu
/// bar app on the machine.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var escapeMonitor: Any?

    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    init(content: some View) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: AnyView(content))
        popover.delegate = self

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityTitle("AI Usage")
        }
        // The item is in the menu bar before the first snapshot arrives, so it
        // shows something rather than an empty gap.
        statusItem.button?.image = Artwork.fallbackSymbol
    }

    var isOpen: Bool { popover.isShown }

    /// The window the popover's content lives in, once it is on screen — what
    /// the screenshot session photographs.
    var popoverWindow: NSWindow? {
        popover.contentViewController?.view.window
    }

    /// Where the item sits in the menu bar, in screen coordinates. The status
    /// bar gives each item its own window, so its frame is the item's.
    var itemFrame: NSRect? {
        statusItem.button?.window?.frame
    }

    func update(
        provider: Provider?, style: MenuBarStyle, slots: Int, coloured: Bool,
        icon: MenuBarIcon = .monochrome
    ) {
        guard let button = statusItem.button else { return }
        // With a logo beside every value the button's own image would be a
        // second, redundant one at the far left — unless there are no values to
        // put one beside, which is what icon-only means.
        let wantsButtonImage = style != .percentOnly && (!icon.isPerValue || style == .iconOnly)
        button.image = wantsButtonImage ? Artwork.menuBarImage(provider?.icon ?? "") : nil
        if style == .iconOnly, icon == .brand, let filename = provider?.icon, !filename.isEmpty {
            button.image = Artwork.brandMenuBarImage(filename)
        }
        button.attributedTitle = MenuBarTitle.attributedTitle(
            for: provider, style: style, slots: slots, coloured: coloured, icon: icon)
        let label = MenuBarTitle.accessibilityLabel(for: provider)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    @objc private func buttonClicked() {
        let isSecondary = NSApp.currentEvent.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false
        if isSecondary {
            showMenu()
        } else {
            toggle()
        }
    }

    func toggle() {
        if popover.isShown { close() } else { open() }
    }

    func open() {
        guard let button = statusItem.button else { return }
        // Anchored to the button itself, so the system places the popover under
        // the item on the display the menu bar is currently on — including a
        // second monitor, and below the notch on the machines that have one.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // A popover from a status item does not get key focus on its own, and
        // without it the text fields on the settings page cannot be typed into.
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
        watchForEscape()
    }

    func close() {
        popover.performClose(nil)
    }

    private func watchForEscape() {
        guard escapeMonitor == nil else { return }
        // Escape is the system's dismiss key for a popover, but a transient one
        // anchored to a status item only gets key events once its window is
        // key — and it is not always. A local monitor makes it reliable.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // Escape
            self?.close()
            return nil
        }
    }

    // ── NSPopoverDelegate ────────────────────────────────────────────────

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // ── Secondary click ──────────────────────────────────────────────────

    private func showMenu() {
        close()
        let menu = NSMenu()
        for item in [
            NSMenuItem(title: i18n("Refresh"), action: #selector(refresh), keyEquivalent: "r"),
            NSMenuItem(title: i18n("Settings") + "…", action: #selector(openSettings), keyEquivalent: ","),
        ] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // No target: Quit goes up the responder chain to NSApp, which is where
        // every other Mac app's Quit goes.
        menu.addItem(
            NSMenuItem(
                title: i18n("Quit AI Usage"), action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))

        // Handed to the status item for the length of one click, rather than
        // left assigned: a permanent menu would replace the click that opens
        // the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() { onRefresh() }
    @objc private func openSettings() { onOpenSettings() }
}
