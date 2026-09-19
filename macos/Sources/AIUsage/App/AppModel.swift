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
    /// The feature view the popover is showing instead of a provider, or nil
    /// for the provider itself. Session-only on purpose: the popover always
    /// opens on the provider, the thing it was opened for.
    @Published var featureView: FeatureView?
    /// Recent local agent sessions for the optional Sessions view.
    @Published private(set) var localSessions: [LocalSession] = []
    @Published private(set) var sessionsLoading = false
    @Published private(set) var sessionsError = ""
    @Published private(set) var sessionsUpdated: Date?
    /// The last `--open-session` result, shown as a status line and cleared
    /// on the next attempt or the next refresh.
    @Published private(set) var sessionsNotice = ""
    @Published private(set) var pricingLoading = false
    @Published private(set) var pricingStatus = ""
    @Published private(set) var pricingError = ""
    @Published private(set) var pricingFetchedAt: Date?

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
    private let snapshotOperation: () throws -> Envelope
    private let pricingRefreshOperation: () throws -> PricingRefreshResult

    init(
        settings: SettingsStore = SettingsStore(),
        snapshotOperation: @escaping () throws -> Envelope = { try Backend.snapshot() },
        pricingRefreshOperation: @escaping () throws -> PricingRefreshResult = { try Backend.refreshPricing() }
    ) {
        self.settings = settings
        self.snapshotOperation = snapshotOperation
        self.pricingRefreshOperation = pricingRefreshOperation
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

    // ── Feature views ────────────────────────────────────────────────────

    /// The feature views switched on in settings, in tab order.
    var featureTabs: [FeatureView] {
        FeatureView.allCases.filter { settings.featureEnabled($0.rawValue) }
    }

    /// Provider rows plus distinct actual and calculated local-session totals.
    /// Local rows never change the provider/API headline total or any
    /// provider's own reported cost.
    var spendRows: [SpendRow] { SpendRows.build(envelope.providers, localSpend: envelope.localSpend) }

    func showFeature(_ view: FeatureView?) {
        featureView = view
        if view == .sessions { refreshSessions() }
    }

    /// Resume one listed session in the user's terminal; the result becomes
    /// `sessionsNotice`. Rows with an empty `openKey` (Muse) show no button.
    func openSession(_ key: String) {
        guard !key.isEmpty else { return }
        sessionsNotice = ""
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Backend.openSession(key)
                await MainActor.run { self.sessionsNotice = result.message }
            } catch {
                await MainActor.run { self.sessionsNotice = error.localizedDescription }
            }
        }
    }

    func refreshSessions() {
        guard !sessionsLoading else { return }
        sessionsLoading = true
        sessionsError = ""
        sessionsNotice = ""
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Backend.sessions()
                await MainActor.run {
                    self.localSessions = result.sessions
                    self.sessionsUpdated = result.updatedAt > 0
                        ? Date(timeIntervalSince1970: result.updatedAt) : Date()
                    self.sessionsLoading = false
                }
            } catch {
                await MainActor.run {
                    self.sessionsError = error.localizedDescription
                    self.sessionsLoading = false
                }
            }
        }
    }

    // ── Refreshing ───────────────────────────────────────────────────────

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let operation = snapshotOperation
        Task.detached(priority: .userInitiated) {
            do {
                let envelope = try operation()
                await MainActor.run { self.apply(envelope) }
            } catch {
                await MainActor.run {
                    self.backendError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func refreshPricing() {
        guard !pricingLoading else { return }
        pricingLoading = true
        let operation = pricingRefreshOperation
        Task.detached(priority: .userInitiated) {
            do {
                let result = try operation()
                await MainActor.run { self.applyPricingResult(result) }
            } catch {
                await MainActor.run { self.applyPricingFailure(error) }
            }
        }
    }

    func applyPricingResult(_ result: PricingRefreshResult) {
        pricingLoading = false
        pricingStatus = result.status.isEmpty ? (result.ok ? "refreshed" : "no-cache") : result.status
        pricingError = result.error
        pricingFetchedAt = result.fetchedAt > 0 ? Date(timeIntervalSince1970: result.fetchedAt) : nil
        if result.ok { refresh() }
    }

    func applyPricingFailure(_ error: Error) {
        pricingLoading = false
        pricingStatus = "no-cache"
        pricingError = error.localizedDescription
        pricingFetchedAt = nil
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
        // A feature view toggled off while shown leaves the popover behind —
        // fall back to the provider rather than an empty view.
        if let view = featureView, !settings.featureEnabled(view.rawValue) {
            featureView = nil
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
