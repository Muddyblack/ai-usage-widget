import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: LaunchMode
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private let settingsWindow = SettingsWindowController()
    private var screenshots: ScreenshotSession?
    private var cancellable: AnyCancellable?

    init(mode: LaunchMode) {
        self.mode = mode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A diagnostic run is its own instance by definition; handing it to a
        // copy already in the menu bar would photograph that one's state.
        if !mode.isDiagnostic, handOffToRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        let initialSettings = SettingsStore()
        let firstRun = initialSettings.isFirstRun
        if !initialSettings.bool("providerDefaultsApplied", default: false) {
            do {
                try Backend.initializeProviderDefaults()
            } catch {
                NSLog("AI Usage: could not initialize provider defaults: \(error.localizedDescription)")
            }
        }
        let settings = SettingsStore()
        Catalog.load(language: settings.language)
        model = AppModel(settings: settings)

        statusItem = StatusItemController(content: UsageView(model: model))
        statusItem.onRefresh = { [weak self] in self?.model.refreshManually() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onVisibilityChanged = { [weak self] visible in self?.model.setPopoverVisible(visible) }

        // The menu bar item and the settings window both follow the model.
        cancellable = model.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the change lands, so the item is
            // refreshed on the next turn of the run loop with the new value.
            DispatchQueue.main.async { self?.syncStatusItem() }
        }
        syncStatusItem()

        if mode.isDiagnostic {
            runDiagnostics()
            return
        }

        model.refresh()
        if firstRun {
            // Nothing points at a new menu bar item, and on a crowded menu bar
            // it can be pushed out of sight entirely. Opening once says it is
            // there, and where.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.statusItem.open() }
        }
    }

    private func runDiagnostics() {
        let session = ScreenshotSession(
            directory: mode.screenshotDirectory,
            model: model,
            statusItem: statusItem,
            settingsWindow: settingsWindow)
        screenshots = session
        session.run { code in
            // Left without waiting for the worker threads: a provider may be
            // sitting on a socket timeout and nothing here needs finishing.
            exit(code)
        }
    }

    private func syncStatusItem() {
        statusItem.update(
            provider: model.selected,
            style: model.settings.menuBarStyle,
            slots: model.settings.menuBarSlots,
            coloured: model.settings.colouredPercentages,
            icon: model.settings.menuBarIcon)
        settingsWindow.retitle()
        if model.showingSettings {
            model.showingSettings = false
            openSettings()
        }
    }

    private func openSettings() {
        statusItem.close()
        settingsWindow.show(model: model)
    }

    /// True when another copy is already in the menu bar. Starting the app a
    /// second time — from Spotlight, say — should show that one's popover
    /// rather than add a second identical item.
    private func handOffToRunningInstance() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine }
        guard let other = others.first else { return false }
        other.activate(options: [])
        return true
    }
}
