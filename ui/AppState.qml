import QtQuick
import "js/ProviderRegistry.js" as ProviderRegistry
import "js/Format.js" as Format
import "js/FeatureTabs.js" as FeatureTabs
import "js/RefreshCoalescer.js" as RefreshCoalescer
import "js/SessionSources.js" as SessionSources
import "js/SessionRefreshPolicy.js" as SessionRefreshPolicy
import "js/UsageHistory.js" as UsageHistory
import "js/I18n.js" as I18n

// The one application state every host shares: providers, settings, tabs,
// sessions, pricing, history and translations. PopupContent.qml and every page
// under it read this object as `shell`.
//
// A host (hosts/<platform>/) supplies only what differs per platform:
//
//   backend        the object that runs the provider backend, reads and writes
//                  the settings file and the history. hosts/windows and
//                  hosts/macos pass the Python `Backend` from app.py; the QML-only
//                  hosts (Quickshell, KDE) pass ui/CommandBackend.qml with their
//                  own process runner. Its interface is documented there.
//   popupVisible   whether the popup is on screen (drives the Sessions tab's
//                  live refresh).
//   the host*      properties below, which the settings page reads to decide
//                  which rows apply on this platform.
Item {
    id: root

    visible: false

    required property var backend
    property bool popupVisible: false

    // ── Host capabilities ────────────────────────────────────────────────────
    // A floating pill to place and a monitor to pin it to (Quickshell).
    property bool pillControls: false
    // A Python interpreter to choose (hosts that start the backend themselves).
    property bool interpreterControls: false
    // Tray styles and the floating pill (Windows / macOS tray apps).
    property bool trayOptions: false
    property var screenNames: []
    readonly property string monitorMode: root.settings.monitor || "focused"
    // The terminal frontend, shown in Settings → About for copy-paste.
    property string cliPath: ""
    readonly property bool autostartAvailable: !!backend.autostartAvailable
    readonly property bool autostart: !!backend.autostart
    function setAutostart(enabled) {
        backend.setAutostart(enabled);
    }

    // Kept for pages written against the older roots.
    readonly property string baseDir: ""

    // ── Environment ──────────────────────────────────────────────────────────
    readonly property string iconSource: backend.appIcon || ""
    readonly property string iconDir: backend.iconDir || ""
    readonly property string configPath: backend.configPath || ""
    readonly property var allProviders: ProviderRegistry.providers

    function providerIcon(provider) {
        var file = provider && provider.icon ? provider.icon : "";
        return file === "" ? "" : root.iconDir + file;
    }

    // ── Translations ─────────────────────────────────────────────────────────
    // translate/<lang>.po for the language chosen in settings ("" follows the
    // system), which the backend finds and reads, parsed by I18n.js. Strings
    // in every page go through shell.i18n(…), which xgettext extracts.
    property var catalog: I18n.empty()
    property var availableLanguages: []
    readonly property string language: root.settings.language || ""
    onLanguageChanged: if (root.settingsLoaded) backend.requestCatalog(root.language)
    onCatalogChanged: root.publishTrayLabels()

    function i18n(text) {
        return I18n.i18n.apply(null, [root.catalog].concat(Array.prototype.slice.call(arguments)));
    }
    function i18nc(context, text) {
        return I18n.i18nc.apply(null, [root.catalog].concat(Array.prototype.slice.call(arguments)));
    }
    function i18np(singular, plural, n) {
        return I18n.i18np.apply(null, [root.catalog].concat(Array.prototype.slice.call(arguments)));
    }
    function i18ncp(context, singular, plural, n) {
        return I18n.i18ncp.apply(null, [root.catalog].concat(Array.prototype.slice.call(arguments)));
    }

    // ── Settings ─────────────────────────────────────────────────────────────
    // The JSON file the backend reads its toggles and keys from, shared by
    // every host on a machine. Fields a host has no use for are carried
    // through untouched: saveSettings() writes the whole object back.
    property var settings: ({
            providers: {},
            keys: {},
            pollSec: 300,
            showChart: true,
            museQuota: false,
            overviewEnabled: false,
            spendEnabled: false,
            sessionsEnabled: true,
            antigravityChartFilter: "both",
            pillMode: "always",
            position: "top-right",
            monitor: "focused",
            pythonPath: "",
            trayStyle: "",
            floatingPill: false,
            language: ""
        })
    property bool settingsLoaded: false
    property bool showSettings: false
    onSettingsChanged: root.publishTray()
    readonly property string antigravityChartFilter: root.settings.antigravityChartFilter || "both"

    function normalizeSettings(d) {
        var s = Object.assign({}, d);
        s.providers = d.providers || {};
        s.keys = d.keys || {};
        s.pollSec = d.pollSec || 300;
        s.showChart = d.showChart !== false;
        s.museQuota = d.museQuota === true;
        s.overviewEnabled = d.overviewEnabled === true;
        s.spendEnabled = d.spendEnabled === true;
        s.sessionsEnabled = d.sessionsEnabled !== false;
        s.antigravityChartFilter = d.antigravityChartFilter || "both";
        s.pillMode = d.pillMode || (d.floatingPill === false ? "tray" : "always");
        s.position = d.position || "top-right";
        s.monitor = d.monitor || "focused";
        s.pythonPath = d.pythonPath || "";
        // trayNumbers was the on/off switch before there were three styles;
        // with neither, the platform's default.
        s.trayStyle = d.trayStyle || (d.trayNumbers === false ? "ring" : d.trayNumbers === true ? "icons" : (backend.defaultTrayStyle || "icons"));
        delete s.trayNumbers;
        s.floatingPill = d.floatingPill === true;
        s.language = d.language || "";
        return s;
    }

    function applyLoadedSettings(text) {
        var d = {};
        try {
            d = JSON.parse((text || "").trim() || "{}") || {};
        } catch (e) {}
        root.settings = root.normalizeSettings(d);
        root.settingsLoaded = true;
        backend.requestCatalog(root.language);
        // The first start (no settings file yet): write one now, so whatever
        // a host does only on a first start happens once.
        if (backend.firstRun)
            root.saveSettings();
        root.initializeProviderDefaults();
    }

    function saveSettings() {
        backend.saveSettings(JSON.stringify(root.settings));
    }

    // Mutate one nested settings field ("providers" or "keys") and persist.
    // Assigning a fresh object makes every binding re-evaluate.
    function setSetting(section, key, value) {
        var s = JSON.parse(JSON.stringify(root.settings));
        if (!s[section])
            s[section] = {};
        s[section][key] = value;
        root.settings = s;
        root.saveSettings();
    }

    // Mutate a top-level settings field and persist.
    function setSetting2(key, value) {
        var s = JSON.parse(JSON.stringify(root.settings));
        s[key] = value;
        root.settings = s;
        root.saveSettings();
    }

    function providerEnabled(id) {
        return ProviderRegistry.enabled(root.settings, id);
    }

    // ── Provider defaults ────────────────────────────────────────────────────
    // The first start detects what is installed and turns those providers on;
    // the backend latches that (providerDefaultsApplied) so it runs once. No
    // usage refresh goes out before it has answered.
    property bool providerDefaultsReady: false
    property bool providerDefaultsInitializing: false

    function initializeProviderDefaults() {
        if (root.providerDefaultsReady || root.providerDefaultsInitializing)
            return;
        if (root.settings.providerDefaultsApplied === true) {
            root.providerDefaultsReady = true;
            root.refresh();
            return;
        }
        root.providerDefaultsInitializing = true;
        backend.initializeProviderDefaults();
    }

    function finishProviderDefaults(text) {
        try {
            var result = JSON.parse((text || "").trim());
            if (result.ok === true && result.data) {
                var merged = Object.assign({}, root.settings || {}, result.data);
                merged.providers = Object.assign({}, (root.settings || {}).providers || {}, result.data.providers || {});
                root.settings = root.normalizeSettings(merged);
            }
        } catch (e) {}
        root.providerDefaultsInitializing = false;
        root.providerDefaultsReady = true;
        root.refresh();
    }

    // ── Provider state ───────────────────────────────────────────────────────
    property var providers: []
    property var localSpend: ({})
    property string activeId: ""
    // The last real provider selected (never a feature tab id) — what the
    // panel pill shows while a feature tab (Overview/Spend/Sessions) is
    // active, since those have no percentage of their own to display.
    property string lastProviderId: ""
    property string errorText: ""
    readonly property bool loading: !!backend.busy
    property int updatedAt: 0
    property double nowTick: new Date().getTime()
    readonly property color dangerColor: "#ff4d4d"

    // Feature tabs (Overview / Spend / Sessions) sit ahead of providers.
    readonly property var popupTabs: {
        var tabs = [];
        var features = FeatureTabs.enabledFeatureTabs(root.settings);
        for (var i = 0; i < features.length; i++) {
            var id = features[i];
            tabs.push({
                id: id,
                label: FeatureTabs.label(id, root.i18n),
                accent: FeatureTabs.accent(id) || "#38bdf8",
                icon: "",
                feature: true
            });
        }
        for (var j = 0; j < root.providers.length; j++)
            tabs.push(root.providers[j]);
        return tabs;
    }
    readonly property bool activeIsFeature: FeatureTabs.isFeatureTab(root.activeId)

    // Chart state: the remembered granularity carries across tabs.
    property string chartWindow: "weekly"
    property string chartGranularity: "7d"
    // Inner sub-tab for providers with activity stats: "usage" vs "stats".
    property string activeSubTab: "usage"
    readonly property bool activeHasStats: {
        if (root.activeIsFeature)
            return false;
        var p = activeProvider();
        return p && (p.id === "claude" || p.id === "openai" || p.id === "copilot" || p.id === "muse" || p.id === "cursor" || p.id === "cline" || p.id === "opencode" || p.id === "mimo" || p.id === "junie");
    }

    function providerById(id) {
        for (var i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === id)
                return root.providers[i];
        }
        return null;
    }

    function activeProvider() {
        if (root.activeIsFeature || root.providers.length === 0)
            return null;
        for (var i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === root.activeId)
                return root.providers[i];
        }
        return root.providers[0];
    }

    // What the panel pill shows: the active provider normally, or the last
    // real provider seen while a feature tab is active — never "no data".
    function pillProvider() {
        if (!root.activeIsFeature)
            return root.activeProvider();
        return root.providerById(root.lastProviderId) || root.providers[0] || null;
    }

    readonly property color activeAccent: {
        if (root.activeIsFeature)
            return FeatureTabs.accent(root.activeId) || "#38bdf8";
        var p = activeProvider();
        return p ? p.accent : "#cc785c";
    }

    // The pill's slots, with the loading and no-data placeholders every host
    // shows. The backend sends text: null for "show the percentage", which a
    // string property cannot take.
    readonly property var pillSlots: {
        var p = root.pillProvider();
        if (root.loading && root.providers.length === 0)
            return [
                {
                    pct: 0,
                    color: "#cc785c",
                    text: "…",
                    tooltip: root.i18n("Loading")
                }
            ];
        var raw = p && p.slots ? p.slots : [];
        if (raw.length === 0)
            return [
                {
                    pct: 0,
                    color: "#cc785c",
                    text: "—",
                    tooltip: root.i18n("No data")
                }
            ];
        var out = [];
        for (var i = 0; i < raw.length; i++)
            out.push({
                pct: raw[i].pct || 0,
                color: raw[i].color || "#cc785c",
                text: raw[i].text || "",
                tooltip: raw[i].tooltip || ""
            });
        return out;
    }
    readonly property bool pillStale: {
        var p = root.pillProvider();
        return root.errorText !== "" || (p ? !!p.stale : false);
    }
    readonly property bool pillHasError: {
        var p = root.pillProvider();
        return root.errorText !== "" || (p ? (p.error || "") !== "" : false);
    }
    readonly property string pillIcon: {
        var logo = root.providerIcon(root.pillProvider());
        return logo !== "" ? logo : root.iconSource;
    }

    // ── Chart ranges ─────────────────────────────────────────────────────────
    // Which history series a provider has, and how wide each range is, comes
    // from the backend (chartWindows in the contract) — no table here.
    function windowsForProvider(id) {
        for (var i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === id)
                return root.providers[i].chartWindows || [];
        }
        return [];
    }

    // Window ID for a provider at the remembered granularity, so the selected
    // range carries across tabs.
    function windowForProvider(id, gran) {
        var wins = windowsForProvider(id);
        if (wins.length === 0)
            return root.chartWindow;
        for (var i = 0; i < wins.length; i++) {
            if (wins[i].granularity === gran)
                return wins[i].id;
        }
        return wins[wins.length - 1].id;
    }

    function windowGranularity(win) {
        var wins = windowsForProvider(root.activeId);
        for (var i = 0; i < wins.length; i++) {
            if (wins[i].id === win)
                return wins[i].granularity;
        }
        return "";
    }

    onActiveIdChanged: {
        activeSubTab = "usage";
        var win = windowForProvider(root.activeId, root.chartGranularity);
        if (root.chartWindow !== win)
            root.chartWindow = win;
        if (root.activeId !== "" && !FeatureTabs.isFeatureTab(root.activeId))
            root.lastProviderId = root.activeId;
        // Reopen on this tab next time.
        if (root.providerDefaultsReady && root.activeId !== "" && (root.settings || {}).lastTab !== root.activeId)
            root.setSetting2("lastTab", root.activeId);
        root.publishTray();
    }

    function selectChartWindow(id) {
        root.chartWindow = id;
        var gran = windowGranularity(id);
        if (gran !== "")
            root.chartGranularity = gran;
    }

    function countdownFor(resetAt) {
        return Format.countdownFromEpoch(resetAt, root.nowTick);
    }

    // ── Tray ─────────────────────────────────────────────────────────────────
    // Hosts with a tray icon (Windows, macOS) draw it from this: the pill's
    // slots in the chosen trayStyle, plus a tooltip listing every provider.
    // Hosts without one ignore the call.
    function publishTray() {
        var p = root.pillProvider();
        var lines = ["AI Usage"];
        for (var i = 0; i < root.providers.length; i++) {
            var q = root.providers[i];
            if (q.label && q.summary && q.summary.text)
                lines.push(q.label + ": " + q.summary.text);
        }
        var slots = [];
        var raw = p && p.slots ? p.slots : [];
        for (var j = 0; j < raw.length; j++) {
            var s = raw[j] || {};
            var text = s.text === null || s.text === undefined ? "" : String(s.text);
            slots.push({
                pct: s.pct || 0,
                color: String(s.color || ""),
                text: text,
                // Windows cuts a tray tooltip at 127 characters, so each icon
                // names only its own value.
                tooltip: s.tooltip ? String(s.tooltip) : p.label + ": " + (text || Math.round(s.pct || 0) + "%")
            });
        }
        backend.publishTrayState(JSON.stringify({
            style: root.settings.trayStyle || backend.defaultTrayStyle || "icons",
            floatingPill: root.settings.floatingPill === true,
            // The active provider's logo leads the numbers, or sits inside the ring.
            icon: p ? root.providerIcon(p) : "",
            tooltip: lines.join("\n"),
            slots: slots
        }));
    }

    // A tray menu built by the host takes its words from here — again whenever
    // the language changes.
    function publishTrayLabels() {
        backend.setTrayLabels(JSON.stringify({
            open: root.i18n("Open AI Usage"),
            refresh: root.i18n("Refresh"),
            settings: root.i18n("Settings"),
            trayStyle: root.i18n("Tray style"),
            icons: root.i18n("Logo and percent"),
            numbers: root.i18n("Numbers"),
            ring: root.i18n("Ring"),
            floatingPill: root.i18n("Floating pill"),
            startWithWindows: root.i18n("Start with Windows"),
            startAtLogin: root.i18n("Start at login"),
            quit: root.i18n("Quit")
        }));
    }

    // ── Backend fetch ────────────────────────────────────────────────────────
    function applySnapshot(text) {
        try {
            var data = JSON.parse((text || "").trim());
            root.providers = data.providers || [];
            root.localSpend = data.localSpend || ({});
            root.updatedAt = data.updatedAt || 0;
            // Seed (or heal, if the remembered one got disabled) the pill's
            // fallback provider — needed even before the user ever leaves a
            // feature tab, since Sessions is the default-enabled one.
            if (!root.providerById(root.lastProviderId))
                root.lastProviderId = data.active || (root.providers[0] || {}).id || "";
            // Keep the active tab if it's still present; otherwise reopen the
            // tab used last time, else the backend's suggestion or the first
            // provider — never a feature tab by default, so the pill mirrors a
            // real provider from the first start.
            var features = FeatureTabs.enabledFeatureTabs(root.settings);
            var isOpenable = function (id) {
                return features.indexOf(id) !== -1 || !!root.providerById(id);
            };
            if (!isOpenable(root.activeId)) {
                var last = (root.settings || {}).lastTab || "";
                root.activeId = isOpenable(last) ? last : (data.active || (root.providers[0] || {}).id || "");
            }
            root.errorText = "";
            root.nowTick = new Date().getTime();
            root.lastFetched = root.nowTick;
            root.recordHistory();
            root.publishTray();
        } catch (e) {
            root.errorText = root.i18n("usage backend returned no data");
        }
    }

    function refresh() {
        if (!root.providerDefaultsReady || root.providerDefaultsInitializing)
            return;
        backend.refresh();
    }

    // A tab click only fetches when the data is over a minute old: every
    // refresh asks every provider, and clicking back and forth between tabs
    // would otherwise keep one running all the time.
    property double lastFetched: 0
    function refreshTab() {
        if (new Date().getTime() - root.lastFetched > 60000)
            root.refresh();
    }

    // One successful pricing refresh triggers at most one usage refresh,
    // deferred while a usage request is already in flight.
    property bool usageRefreshPending: false

    function requestUsageRefreshAfterPricing() {
        var action = RefreshCoalescer.nextAction(true, root.loading, root.usageRefreshPending);
        if (action === "refresh-now")
            root.refresh();
        else if (action === "mark-pending")
            root.usageRefreshPending = true;
    }

    onLoadingChanged: {
        if (!root.loading && root.usageRefreshPending) {
            root.usageRefreshPending = false;
            root.refresh();
        }
    }

    // ── Pricing ──────────────────────────────────────────────────────────────
    readonly property bool pricingLoading: !!backend.pricingBusy
    property string pricingStatus: ""
    property string pricingError: ""

    function refreshPricing() {
        if (root.pricingLoading)
            return;
        backend.refreshPricing();
    }

    property int ratesRequestId: 0
    property var ratesCallback: null

    function queryRates(filter, limit, offset, callback) {
        // The catalog parse runs off the GUI thread; the result comes back
        // with a generation so a superseded query is dropped.
        root.ratesRequestId += 1;
        root.ratesCallback = typeof callback === "function" ? callback : null;
        backend.requestRates((filter || "").trim(), limit || 40, offset || 0, root.ratesRequestId);
    }

    function deliverRates(text) {
        var callback = root.ratesCallback;
        root.ratesCallback = null;
        if (typeof callback === "function")
            callback(text === "" ? null : FeatureTabs.parseRateTable(text));
    }

    // ── Provider detection ───────────────────────────────────────────────────
    // Settings → Providers → "Detect installed providers": re-runs the
    // stat-only detection and syncs the toggles with what is installed.
    property bool providerDetectBusy: false
    property string providerDetectStatus: ""

    function redetectProviders() {
        if (root.providerDetectBusy)
            return;
        root.providerDetectBusy = true;
        root.providerDetectStatus = "";
        backend.detectProviders();
    }

    function applyProviderDetection(text) {
        root.providerDetectBusy = false;
        var result = null;
        try {
            result = JSON.parse((text || "").trim());
        } catch (e) {}
        if (!result || result.ok !== true || !Array.isArray(result.data)) {
            root.providerDetectStatus = root.i18n("Detection failed.");
            return;
        }
        var applied = ProviderRegistry.applyDetected(root.settings, result.data);
        if (applied.added.length === 0 && applied.removed.length === 0) {
            root.providerDetectStatus = root.i18n("No changes: enabled providers match what is installed.");
            return;
        }
        root.settings = applied.settings;
        root.saveSettings();
        var parts = [];
        if (applied.added.length)
            parts.push(root.i18n("Enabled: %1", ProviderRegistry.labels(applied.added)));
        if (applied.removed.length)
            parts.push(root.i18n("Disabled (not installed): %1", ProviderRegistry.labels(applied.removed)));
        root.providerDetectStatus = parts.join(" · ");
        root.refresh();
    }

    // ── Sessions ─────────────────────────────────────────────────────────────
    property var sessions: []
    property bool sessionsLoading: false
    property string sessionsCacheStatus: "unknown"
    property var sessionsCacheAgeSeconds: null
    property string sessionsRefreshStatus: "not-run"
    property int sessionsRemovedSourceCount: 0
    property string sessionsError: ""
    // Last `--open-session` result, shown as a status line under the list.
    property string sessionsNotice: ""
    property string sessionsQuery: ""
    property var sessionsSources: []
    property var sessionsSourceIds: []
    property string sessionsSourceSignature: ""
    property string sessionsSourceResetSignature: ""
    property var sessionsActiveSourceIds: []
    property string sessionsActiveSourceSignature: ""
    property bool sessionsActiveRefresh: false
    property double sessionsLastReconcile: 0
    property int sessionsRequestId: 0
    readonly property int sessionsLimit: 60
    property int sessionsTotal: 0
    property bool sessionsTotalExact: false
    property bool sessionsHasMore: false
    property int sessionsOffset: 0
    property int sessionsActiveOffset: 0
    property bool sessionsActiveAppend: false
    property double previousSessionClockMs: Date.now()
    readonly property bool sessionsViewVisible: root.popupVisible && !root.showSettings && root.activeId === "sessions"

    // Load as soon as the view is shown, rather than at the next poll tick.
    onSessionsViewVisibleChanged: {
        if (sessionsViewVisible && !sessionsLoading)
            querySessions(sessionsQuery, 0, false, sessionsSourceIds);
    }

    function normalizeSessionSources(raw) {
        return SessionSources.normalizeDescriptors(raw);
    }

    function sessionSourceSignature(ids) {
        return SessionSources.signature(ids);
    }

    function setSessionsSourceIds(ids) {
        var normalized = SessionSources.normalizeIds(ids, root.sessionsSources);
        var signature = root.sessionSourceSignature(normalized);
        if (signature === root.sessionsSourceSignature)
            return;
        root.sessionsSourceIds = normalized;
        root.sessionsSourceSignature = signature;
    }

    function sessionSourceSelectionHasStaleIds(available) {
        return SessionSources.hasStaleIds(root.sessionsSourceIds, available);
    }

    function setSessionsQuery(query) {
        query = (query || "").trim();
        if (query === root.sessionsQuery)
            return;
        root.requestSessions(query, false);
    }

    function sendSessionsRequest(reconcile) {
        var ids = root.sessionsActiveSourceIds;
        if (reconcile) {
            if (ids.length > 0)
                backend.refreshSessionsAndQuery(root.sessionsQuery, root.sessionsRequestId, root.sessionsActiveOffset, ids);
            else
                backend.refreshSessionsAndQuery(root.sessionsQuery, root.sessionsRequestId, root.sessionsActiveOffset);
        } else if (ids.length > 0) {
            backend.refreshSessions(root.sessionsQuery, root.sessionsRequestId, root.sessionsActiveOffset, ids);
        } else {
            backend.refreshSessions(root.sessionsQuery, root.sessionsRequestId, root.sessionsActiveOffset);
        }
    }

    function requestSessions(query, reconcile, sourceIds, offset, append) {
        if (sourceIds !== undefined)
            root.setSessionsSourceIds(sourceIds);
        root.sessionsQuery = (query || "").trim();
        root.sessionsActiveOffset = offset === undefined ? 0 : offset;
        root.sessionsActiveAppend = append === true;
        root.sessionsActiveRefresh = reconcile === true;
        root.sessionsActiveSourceIds = root.sessionsSourceIds.slice(0);
        root.sessionsActiveSourceSignature = root.sessionsSourceSignature;
        root.sessionsRequestId += 1;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root.sessionsNotice = "";
        root.sendSessionsRequest(reconcile === true);
    }

    function refreshSessions(query, offset, append, sourceIds) {
        root.requestSessions(query, false, sourceIds);
    }

    function querySessions(query, offset, append, sourceIds) {
        root.requestSessions(query, false, sourceIds, append === true ? offset : 0, append === true);
    }

    function reconcileSessions(query, sourceIds) {
        root.requestSessions(query, true, sourceIds);
    }

    function loadMoreSessions() {
        if (root.sessionsLoading || !root.sessionsHasMore)
            return;
        root.requestSessions(root.sessionsQuery, false, undefined, root.sessionsOffset + root.sessionsLimit, true);
    }

    function handleSessions(text, query, requestId) {
        if (requestId !== root.sessionsRequestId || query !== root.sessionsQuery || root.sessionsActiveSourceSignature !== root.sessionsSourceSignature)
            return;
        root.sessionsLoading = false;
        try {
            var data = JSON.parse((text || "").trim());
            if (data.error) {
                root.sessionsError = data.error;
                root.sessionsRefreshStatus = "failed";
                sessionsReconcileTimer.restart();
            } else if (data.cacheStatus === "failed") {
                root.sessionsError = root.i18n("Could not load cached sessions.");
                root.sessionsCacheStatus = "failed";
                root.sessionsRefreshStatus = "failed";
                sessionsReconcileTimer.restart();
            } else {
                var page = data.sessions || [];
                var responseSources = root.normalizeSessionSources(data.sources);
                var staleSelection = root.sessionSourceSelectionHasStaleIds(responseSources);
                root.sessionsSources = responseSources;
                if (staleSelection) {
                    var staleSignature = root.sessionsSourceSignature;
                    if (root.sessionsSourceResetSignature === staleSignature)
                        return;
                    root.sessionsSourceIds = [];
                    root.sessionsSourceSignature = "";
                    root.sessionsSourceResetSignature = staleSignature;
                    root.sessions = [];
                    root.sessionsOffset = 0;
                    root.sessionsTotal = 0;
                    root.sessionsHasMore = false;
                    root.requestSessions(root.sessionsQuery, false, [], 0);
                    return;
                }
                root.sessionsSourceResetSignature = "";
                root.sessionsTotal = Number(data.total) || 0;
                root.sessionsTotalExact = data.totalExact === true;
                root.sessionsOffset = Number(data.offset) || root.sessionsActiveOffset;
                root.sessionsHasMore = data.hasMore === true;
                root.sessions = root.sessionsActiveAppend ? root.sessions.concat(page) : page;
                root.sessionsError = "";
                root.sessionsCacheStatus = data.cacheStatus || "unknown";
                root.sessionsCacheAgeSeconds = data.cacheAgeSeconds === undefined ? null : data.cacheAgeSeconds;
                // A cache-only query never ran a refresh ("not-run"); keep the
                // status of the last scan instead of erasing it.
                if (data.refreshStatus && data.refreshStatus !== "not-run")
                    root.sessionsRefreshStatus = data.refreshStatus;
                if (root.sessionsActiveRefresh)
                    root.sessionsRemovedSourceCount = Number(data.removedSourceCount) || 0;
                sessionsReconcileTimer.restart();
                // An expired cache starts one scan, but a scan that just failed
                // waits for the reconcile timer instead of retrying in a loop.
                var lastScanFailed = root.sessionsRefreshStatus === "failed" || root.sessionsRefreshStatus === "incomplete";
                if (root.sessionsActiveRefresh)
                    root.sessionsLastReconcile = Date.now();
                else if (root.sessionsViewVisible && !lastScanFailed && SessionRefreshPolicy.cacheExpired(root.sessionsCacheAgeSeconds))
                    root.reconcileSessions(root.sessionsQuery, root.sessionsSourceIds);
            }
        } catch (e) {
            root.sessionsError = root.i18n("Could not load sessions.");
            root.sessionsRefreshStatus = "failed";
            sessionsReconcileTimer.restart();
        }
    }

    // Rows with an empty openKey (Muse) render no button at all.
    function openSession(key) {
        if (!key)
            return;
        root.sessionsNotice = "";
        backend.openSession(key);
    }

    // ── History ──────────────────────────────────────────────────────────────
    // The state machine in UsageHistory.js over the shared history file, which
    // the backend's historyio owns: it takes a lock, unions the payload into
    // whatever is on disk and hands the merged series back. Persistence is
    // coalesced into one run per window while the chart stays current from the
    // in-memory store; a controlled exit flushes instead of waiting.
    property var usageHistory: []
    readonly property int historyLimit: 10000
    property var historyStore: UsageHistory.newStore(root.historyLimit)
    property bool historySaving: false
    property string historyMsg: ""
    readonly property int historyDebounceMs: 300000

    // The store replaces `history` rather than patching it in place, so an
    // unchanged reference means there is nothing to repaint.
    function syncUsageHistory() {
        if (root.usageHistory !== root.historyStore.history)
            root.usageHistory = root.historyStore.history;
    }

    // Recorded on every poll even when no provider reported, which is what
    // releases a save that failed.
    function recordHistory() {
        UsageHistory.record(root.historyStore, UsageHistory.collect(root.providers), new Date().getTime());
        root.syncUsageHistory();
        root.saveHistory();
    }

    function saveHistory() {
        if (UsageHistory.arm(root.historyStore, new Date().getTime(), root.historyDebounceMs))
            historyDebounceTimer.restart();
    }

    function sendHistory() {
        if (root.historySaving)
            return;
        var batch = UsageHistory.take(root.historyStore);
        if (!batch)
            return;
        root.historySaving = true;
        historySaveTimeout.restart();
        backend.history(batch.op, JSON.stringify(batch.points));
    }

    function flushHistory() {
        historyDebounceTimer.stop();
        var batch = UsageHistory.takeForExit(root.historyStore);
        if (!batch)
            return;
        // Synchronous where the host can manage it: the process is going
        // away, so the write has to land before it exits.
        backend.flushHistory(batch.op, JSON.stringify(batch.points));
    }

    function finishHistorySave(result) {
        historySaveTimeout.stop();
        root.historySaving = false;
        var res = null;
        try {
            res = JSON.parse(result);
        } catch (e) {}
        if (!res || res.error) {
            UsageHistory.failed(root.historyStore);
            return;
        }
        // A degraded write answers {"ok":true} with no series, which leaves
        // nothing to adopt.
        UsageHistory.done(root.historyStore, res.data);
        root.syncUsageHistory();
        root.saveHistory();
    }

    function exportHistory() {
        backend.history("export", "");
    }

    Timer {
        id: historyDebounceTimer
        interval: root.historyDebounceMs
        onTriggered: root.sendHistory()
    }

    // A save that never answers would hold its batch in flight for the rest of
    // the session. failed() is idempotent, so a late answer after this is fine.
    Timer {
        id: historySaveTimeout
        interval: 30000
        onTriggered: {
            root.historySaving = false;
            UsageHistory.failed(root.historyStore);
        }
    }

    Timer {
        id: historyMsgTimer
        interval: 6000
        onTriggered: root.historyMsg = ""
    }

    // ── Timers ───────────────────────────────────────────────────────────────
    Timer {
        interval: Math.max(30, root.settings.pollSec || 300) * 1000
        running: root.providerDefaultsReady
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: sessionsReconcileTimer
        interval: SessionRefreshPolicy.refreshDelayMs(root.sessionsCacheAgeSeconds, root.sessionsRefreshStatus)
        running: root.sessionsViewVisible
        onTriggered: {
            if (!root.sessionsLoading)
                root.reconcileSessions(root.sessionsQuery, root.sessionsSourceIds);
        }
    }

    // Drives the countdown chips, and catches a resume from suspend.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            var now = Date.now();
            if (root.sessionsViewVisible && SessionRefreshPolicy.resumed(root.previousSessionClockMs, now) && !root.sessionsLoading)
                root.reconcileSessions(root.sessionsQuery, root.sessionsSourceIds);
            root.previousSessionClockMs = now;
            root.nowTick = now;
        }
    }

    // ── Backend answers ──────────────────────────────────────────────────────
    Connections {
        target: root.backend

        function onSettingsLoaded(text) {
            root.applyLoadedSettings(text);
        }

        function onCatalogLoaded(text) {
            root.catalog = I18n.parsePo(text || "");
        }

        function onLanguagesLoaded(text) {
            try {
                root.availableLanguages = JSON.parse(text || "[]");
            } catch (e) {
                root.availableLanguages = [];
            }
        }

        function onProviderDefaultsLoaded(text) {
            root.finishProviderDefaults(text);
        }

        function onProvidersDetected(text) {
            root.applyProviderDetection(text);
        }

        function onSnapshotReady(text) {
            root.applySnapshot(text);
        }

        function onRefreshFailed(message) {
            root.errorText = message;
        }

        function onRatesReady(text) {
            root.deliverRates(text);
        }

        function onSessionsReady(text, query, requestId) {
            root.handleSessions(text, query, requestId);
        }

        function onOpenSessionFinished(text) {
            try {
                var data = JSON.parse((text || "").trim());
                root.sessionsNotice = data.message || "";
            } catch (e) {
                root.sessionsNotice = root.i18n("Could not resume session.");
            }
        }

        function onPricingRefreshFinished(text) {
            try {
                var data = JSON.parse((text || "").trim());
                root.pricingStatus = data.status || (data.ok === true ? "refreshed" : "no-cache");
                root.pricingError = data.error || "";
                if (data.ok === true)
                    root.requestUsageRefreshAfterPricing();
            } catch (e) {
                root.pricingStatus = "no-cache";
                root.pricingError = root.i18n("Could not refresh pricing.");
            }
        }

        function onPricingRefreshFailed(message) {
            root.pricingStatus = "no-cache";
            root.pricingError = message || root.i18n("Could not refresh pricing.");
        }

        // A setting changed from a host's own menu (tray style, floating pill),
        // JSON-encoded.
        function onSettingRequested(key, value) {
            root.setSetting2(key, JSON.parse(value));
        }

        function onHistoryFinished(op, result) {
            if (op === "autoload") {
                try {
                    var r = JSON.parse(result);
                    if (r && Array.isArray(r.data)) {
                        // Samples taken while this read was in flight are this
                        // host's own and stay on top of the file's.
                        UsageHistory.adopt(root.historyStore, r.data);
                        root.syncUsageHistory();
                    }
                } catch (e) {}
                UsageHistory.opened(root.historyStore);
                root.saveHistory();
            } else if (op === "export") {
                try {
                    var x = JSON.parse(result);
                    root.historyMsg = x.path ? root.i18n("Saved to %1", x.path) : (x.error || root.i18n("Export failed"));
                } catch (e) {
                    root.historyMsg = root.i18n("Export failed");
                }
                historyMsgTimer.restart();
            } else {
                root.finishHistorySave(result);
            }
        }
    }

    Component.onCompleted: {
        root.publishTrayLabels();
        backend.requestLanguages();
        backend.requestSettings();
        backend.history("autoload", "");
    }

    Component.onDestruction: root.flushHistory()
}
