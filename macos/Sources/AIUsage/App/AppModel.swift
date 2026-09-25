import AppKit
import Combine
import SwiftUI

/// Everything the views read and the menu bar shows.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var envelope = Envelope()
    @Published private(set) var isLoading = false
    private var usageRefreshPending = false
    /// A failure of the backend itself — not a provider's own error, which
    /// travels inside the envelope and is shown on that provider's card.
    @Published private(set) var backendError = ""
    @Published private(set) var lastUpdated: Date?
    @Published var showingSettings = false
    @Published var showingChart = false
    @Published var showingStats = false
    private(set) var popoverVisible = false
    /// The feature view the popover is showing instead of a provider, or nil
    /// for the provider itself. Session-only on purpose: the popover always
    /// opens on the provider, the thing it was opened for.
    @Published var featureView: FeatureView?
    /// Recent local agent sessions for the optional Sessions view.
    @Published private(set) var localSessions: [LocalSession] = []
    @Published private(set) var sessionsLoading = false
    @Published private(set) var sessionsError = ""
    @Published private(set) var sessionsUpdated: Date?
    @Published private(set) var sessionsTotal = 0
    @Published private(set) var sessionsOffset = 0
    @Published private(set) var sessionsLimit = 60
    @Published private(set) var sessionsHasMore = false
    @Published private(set) var sessionsTotalExact = false
    @Published private(set) var sessionsCacheStatus = "unknown"
    @Published private(set) var sessionsCacheAgeSeconds: Int?
    @Published private(set) var sessionsRefreshStatus = "not-run"
    @Published private(set) var sessionsRemovedSourceCount = 0
    @Published private(set) var sessionSources: [SessionSource] = []
    @Published private(set) var selectedSessionSourceIDs: Set<String> = []
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
    private var sessionsTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let snapshotOperation: () throws -> Envelope
    private let pricingRefreshOperation: () throws -> PricingRefreshResult
    private var sessionsRequestID = 0
    private var sessionsQuery = ""
    private var sessionsRequestSignature = ""
    private var sessionsDebounceTask: Task<Void, Never>?
    private var sessionsFetchTask: Task<Void, Never>?
    private var sessionsRefreshTask: Task<Void, Never>?
    private var sessionsPollTask: Task<Void, Never>?
    private var sessionsLastReconcile = Date.distantPast
    private nonisolated static let sessionsReconcileInterval: TimeInterval = 600

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

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible, featureView == .sessions {
            refreshSessions(query: sessionsQuery, refresh: false)
        }
    }

    func refreshManually() {
        refresh()
        if popoverVisible, featureView == .sessions {
            refreshSessions(query: sessionsQuery, refresh: true)
        }
    }

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
        if view == .sessions { refreshSessions(query: sessionsQuery, refresh: false) }
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

    func scheduleSessionsRefresh(query: String) {
        sessionsDebounceTask?.cancel()
        sessionsDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refreshSessions(query: query, refresh: false)
        }
    }

    func setSessionSourceSelection(_ ids: Set<String>, query: String? = nil) {
        let normalizedIDs = Set(normalizedSessionSourceIDs(ids, available: sessionSources))
        let allSourceIDs = Set(sessionSources.map(\.id))
        let selection = normalizedIDs == allSourceIDs ? Set<String>() : normalizedIDs
        guard selection != selectedSessionSourceIDs else { return }
        selectedSessionSourceIDs = selection
        sessionsDebounceTask?.cancel()
        refreshSessions(query: query ?? sessionsQuery, refresh: false)
    }

    func refreshSessions(query: String = "", refresh: Bool = true) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if refresh, sessionsRefreshTask != nil {
            refreshSessions(query: normalizedQuery, offset: 0, appending: false, refresh: false)
            return
        }
        let requestSignature = makeSessionsRequestSignature(for: normalizedQuery)
        guard !Self.shouldDeduplicateSessionRequest(
            isLoading: sessionsLoading,
            sameSignature: sessionsRequestSignature == requestSignature,
            forced: refresh
        ) else { return }
        refreshSessions(query: normalizedQuery, offset: 0, appending: false, refresh: refresh)
    }

    nonisolated static func shouldDeduplicateSessionRequest(
        isLoading: Bool, sameSignature: Bool, forced: Bool
    ) -> Bool {
        isLoading && sameSignature && !forced
    }

    nonisolated static func isCurrentSessionRequest(_ requestID: Int, currentRequestID: Int) -> Bool {
        requestID == currentRequestID
    }

    func loadMoreSessions() {
        guard sessionsHasMore, !sessionsLoading else { return }
        let sessionsLimit = 60
        let nextOffset = sessionsOffset + sessionsLimit
        refreshSessions(query: sessionsQuery, offset: nextOffset, appending: true, refresh: false)
    }

    private func refreshSessions(query: String, offset: Int, appending: Bool, refresh: Bool, quiet: Bool = false) {
        sessionsFetchTask?.cancel()
        sessionsRequestID += 1
        let requestID = sessionsRequestID
        let requestedSourceIDs = normalizedSessionSourceIDs(selectedSessionSourceIDs, available: sessionSources)
        let requestSignature = makeSessionsRequestSignature(for: query, sourceIDs: requestedSourceIDs)
        sessionsRequestSignature = requestSignature
        sessionsQuery = query
        if !quiet {
            sessionsLoading = true
            sessionsError = ""
            sessionsNotice = ""
        }
        let requestedOffset = offset
        let requestedLimit: Int? = 60
        if refresh, sessionsRefreshTask == nil {
            sessionsRefreshTask = Task.detached(priority: .userInitiated) { [weak self] in
                var refreshError: String?
                do {
                    _ = try Backend.refreshSessions(
                        query, limit: requestedLimit, offset: requestedOffset, sourceIds: requestedSourceIDs
                    )
                } catch {
                    refreshError = error.localizedDescription
                }
                guard let self else { return }
                await MainActor.run { [self] in
                    self.sessionsRefreshTask = nil
                    self.sessionsPollTask?.cancel()
                    self.refreshSessions(query: self.sessionsQuery, offset: 0, appending: false, refresh: false)
                    if let refreshError {
                        self.sessionsError = refreshError
                        self.sessionsRefreshStatus = "failed"
                    }
                }
            }
            sessionsPollTask?.cancel()
            sessionsPollTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while self.sessionsRefreshTask != nil {
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, self.sessionsRefreshTask != nil else { return }
                    self.refreshSessions(
                        query: self.sessionsQuery, offset: self.sessionsOffset,
                        appending: false, refresh: false, quiet: true)
                }
            }
        }
        sessionsFetchTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try Backend.sessions(
                    query, limit: requestedLimit, offset: requestedOffset, sourceIds: requestedSourceIDs
                )
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await MainActor.run { [self] in
                    guard !Task.isCancelled,
                          Self.isCurrentSessionRequest(requestID, currentRequestID: self.sessionsRequestID),
                          self.sessionsRequestSignature == requestSignature else { return }
                    guard result.cacheStatus != "failed" else {
                        self.sessionsError = i18n("Could not load cached sessions.")
                        self.sessionsRefreshStatus = "failed"
                        self.sessionsLoading = false
                        self.sessionsFetchTask = nil
                        return
                    }
                    self.sessionSources = result.sources
                    let sourceSelection = Self.reconciledSessionSourceIDs(
                        requested: requestedSourceIDs, available: result.sources)
                    self.selectedSessionSourceIDs = sourceSelection.selected
                    if sourceSelection.requiresAllQuery {
                        self.localSessions = []
                        self.sessionsTotal = 0
                        self.sessionsOffset = 0
                        self.sessionsHasMore = false
                        self.sessionsTotalExact = false
                        self.refreshSessions(query: query, refresh: false)
                        return
                    }
                    if requestedOffset == 0 {
                        self.localSessions = result.sessions
                    } else {
                        self.localSessions.append(contentsOf: result.sessions)
                    }
                    self.sessionsTotal = result.total
                    self.sessionsOffset = requestedOffset
                    self.sessionsLimit = result.limit ?? 60
                    self.sessionsHasMore = result.hasMore
                    self.sessionsTotalExact = result.totalExact
                    self.sessionsUpdated = result.updatedAt > 0
                        ? Date(timeIntervalSince1970: result.updatedAt) : Date()
                    self.sessionsCacheStatus = result.cacheStatus
                    self.sessionsCacheAgeSeconds = result.cacheAgeSeconds
                    self.sessionsRefreshStatus = result.refreshStatus
                    self.sessionsRemovedSourceCount = result.removedSourceCount
                    self.sessionsLoading = false
                    self.sessionsFetchTask = nil
                    if refresh {
                        self.sessionsLastReconcile = Date()
                    } else {
                        if let age = result.cacheAgeSeconds {
                            self.sessionsLastReconcile = Date().addingTimeInterval(-TimeInterval(age))
                        }
                        if self.sessionsRefreshTask == nil,
                           Self.sessionsCacheExpired(ageSeconds: result.cacheAgeSeconds),
                           self.popoverVisible, self.featureView == .sessions {
                            self.refreshSessions(query: query, refresh: true)
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await MainActor.run { [self] in
                    guard !Task.isCancelled,
                          Self.isCurrentSessionRequest(requestID, currentRequestID: self.sessionsRequestID),
                          self.sessionsRequestSignature == requestSignature else { return }
                    self.sessionsError = error.localizedDescription
                    self.sessionsRefreshStatus = "failed"
                    self.sessionsLoading = false
                    self.sessionsFetchTask = nil
                }
            }
        }
    }

    nonisolated static func reconciledSessionSourceIDs(
        requested: [String], available: [SessionSource]
    ) -> (selected: Set<String>, requiresAllQuery: Bool) {
        let requestedIDs = Set(requested.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        let availableIDs = Set(available.map(\.id))
        guard !requestedIDs.isEmpty else { return ([], false) }
        guard requestedIDs.isSubset(of: availableIDs) else { return ([], true) }
        return (requestedIDs, false)
    }

    private func normalizedSessionSourceIDs(
        _ ids: Set<String>, available: [SessionSource]
    ) -> [String] {
        let requested = Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
        let availableIDs = Set(available.map(\.id))
        return available
            .map(\.id)
            .filter { requested.contains($0) && availableIDs.contains($0) }
    }

    private func makeSessionsRequestSignature(
        for query: String, sourceIDs: [String]? = nil
    ) -> String {
        let ids = sourceIDs ?? normalizedSessionSourceIDs(selectedSessionSourceIDs, available: sessionSources)
        return query + "\u{1F}" + ids.joined(separator: ",")
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
        // A successful pricing refresh changes derived cost values, so it owes
        // exactly one usage refresh — but if one is already running, remember
        // it and fire when that settles instead of cancelling and re-running.
        if result.ok { requestUsageRefreshAfterPricing() }
    }

    func requestUsageRefreshAfterPricing() {
        if isLoading {
            usageRefreshPending = true
        } else {
            refresh()
        }
    }

    private func settlePendingUsageRefresh() {
        guard usageRefreshPending else { return }
        usageRefreshPending = false
        refresh()
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
        settlePendingUsageRefresh()
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
            Task { @MainActor in
                self.refresh()
                // Provider usage stays on its normal app-wide timer; local
                // session stores are reconciled only while Sessions is shown.
                if self.popoverVisible, self.featureView == .sessions,
                   Self.sessionsReconciliationDue(last: self.sessionsLastReconcile, now: Date()) {
                    self.refreshSessions(query: self.sessionsQuery, refresh: true)
                }
            }
        }
        // A generous tolerance lets macOS coalesce this poll with whatever else
        // it is already waking the CPU for. On a laptop that is the difference
        // between a background app that costs battery and one that does not.
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sessionsTimer?.invalidate()
        let sessionsTimer = Timer(timeInterval: Self.sessionsReconcileInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.popoverVisible, self.featureView == .sessions,
                      Self.sessionsReconciliationDue(last: self.sessionsLastReconcile, now: Date()) else { return }
                self.refreshSessions(query: self.sessionsQuery, refresh: true)
            }
        }
        sessionsTimer.tolerance = 60
        RunLoop.main.add(sessionsTimer, forMode: .common)
        self.sessionsTimer = sessionsTimer
    }

    private func watchForWake() {
        // A machine that slept through several poll intervals has stale
        // numbers, and the quota windows it is showing may have reset while it
        // was away.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
                if self.popoverVisible, self.featureView == .sessions {
                    self.refreshSessions(query: self.sessionsQuery, refresh: true)
                }
            }
        }
    }

    nonisolated static func sessionsCacheExpired(ageSeconds: Int?) -> Bool {
        guard let ageSeconds else { return true }
        return ageSeconds >= Int(sessionsReconcileInterval)
    }

    nonisolated static func sessionsReconciliationDue(last: Date, now: Date) -> Bool {
        now.timeIntervalSince(last) >= sessionsReconcileInterval
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
