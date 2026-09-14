import AppKit
import Combine
import SwiftUI

/// Everything the views read and the menu bar shows.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var envelope = Envelope()
    @Published private(set) var isLoading = false
    /// A failure of the backend itself — not a provider's own error, which
    /// travels inside the envelope and is shown on that provider's card.
    @Published private(set) var backendError = ""
    @Published private(set) var lastUpdated: Date?
    @Published var showingSettings = false
    @Published var showingChart = false
    @Published var showingStats = false

    /// The provider the popover and the menu bar are showing. Deliberately
    /// sticky: a menu bar reading that silently changed which service it meant
    /// would be worse than useless, so nothing but the user — or that provider
    /// disappearing entirely — moves it.
    @Published var selectedID = "" {
        didSet {
            guard selectedID != oldValue, !selectedID.isEmpty else { return }
            settings.menuBarProvider = selectedID
        }
    }

    let settings: SettingsStore
    let history = HistoryStore()

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        selectedID = settings.menuBarProvider
        history.load()
        rearmTimer()
        watchForWake()
    }

    var providers: [Provider] { envelope.providers }

    var selected: Provider? {
        envelope.provider(id: selectedID) ?? envelope.providers.first
    }

    var hasBackend: Bool { Backend.executable != nil }

    // ── Refreshing ───────────────────────────────────────────────────────

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            do {
                let envelope = try Backend.snapshot()
                await MainActor.run { self.apply(envelope) }
            } catch {
                await MainActor.run {
                    self.backendError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func apply(_ envelope: Envelope) {
        self.envelope = envelope
        backendError = ""
        isLoading = false
        lastUpdated = envelope.updatedAt > 0 ? Date(timeIntervalSince1970: envelope.updatedAt) : Date()
        // The remembered provider is gone — switched off, or renamed by a
        // backend update. Fall back rather than showing an empty popover.
        if envelope.provider(id: selectedID) == nil {
            selectedID = envelope.fallbackID
        }
        history.record(envelope.providers)
    }

    // ── Polling ──────────────────────────────────────────────────────────

    func rearmTimer() {
        timer?.invalidate()
        let interval = TimeInterval(settings.pollSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Bound before the hop to the main actor: a Task body runs
            // concurrently, and the weak `self` it would otherwise read is a
            // mutable capture of the enclosing closure.
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
        // A generous tolerance lets macOS coalesce this poll with whatever else
        // it is already waking the CPU for. On a laptop that is the difference
        // between a background app that costs battery and one that does not.
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func watchForWake() {
        // A machine that slept through several poll intervals has stale
        // numbers, and the quota windows it is showing may have reset while it
        // was away.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    /// Feed one envelope in without going near the network — the diagnostic
    /// modes, which render a fixture.
    func applyForDiagnostics(_ envelope: Envelope) {
        apply(envelope)
    }

    // ── Settings ─────────────────────────────────────────────────────────

    /// Writes the settings file and makes the change take effect now: a new
    /// poll interval re-arms the timer, and everything else is picked up by the
    /// next refresh, because the backend reads that same file.
    func changeSettings(_ change: (SettingsStore) -> Void) {
        let languageBefore = settings.language
        change(settings)
        if settings.language != languageBefore {
            Catalog.load(language: settings.language)
        }
        rearmTimer()
        objectWillChange.send()
    }
}
