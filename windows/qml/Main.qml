import QtQuick
import QtQuick.Controls.Basic as QC
import "../../hyprland"
import "../../hyprland/ProviderRegistry.js" as ProviderRegistry
import "../../package/contents/code/Format.js" as Format
import "../../package/contents/code/FeatureTabs.js" as FeatureTabs
import "../../package/contents/code/SessionSources.js" as SessionSources
import "../../package/contents/code/UsageHistory.js" as UsageHistory
import "../../package/contents/code/I18n.js" as I18n

// The Windows tray popup (windows/app.py places, shows and hides it).
//
// The content is the Hyprland panel's own — PopupContent.qml and the settings
// page inside it — so this file is only the window around it plus the `shell`
// interface those read: state, settings and history, backed by the `backend`
// object app.py exposes instead of Quickshell processes. Keep the two roots'
// interfaces in step; AiUsageShell.qml is the other implementation.
Window {
    id: root

    width: 460
    height: Math.min(680, popupContent.height + 40)
    visible: false
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    // Matched by the KWin script in app.py (POPUP_TITLE) on Plasma Wayland.
    title: "AI Usage"

    // ── Environment ──────────────────────────────────────────────────────────
    readonly property string iconSource: backend.appIcon
    readonly property string iconDir: backend.iconDir
    readonly property string configPath: backend.configPath
    readonly property var allProviders: ProviderRegistry.providers

    // Translations: translate/<lang>.po for the language chosen in settings (""
    // follows the system), which app.py picks and reads, parsed by the same
    // I18n.js as the Quickshell panel.
    readonly property var catalog: I18n.parsePo(backend.catalogFor(root.settings.language || ""))
    readonly property var availableLanguages: JSON.parse(backend.languagesJson)
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

    // What this frontend does not have, so the settings page leaves it out: no
    // floating pill to place, no monitor to pin it to, and no interpreter to
    // choose — the app ships its own.
    readonly property bool pillControls: false
    readonly property bool interpreterControls: false
    readonly property var screenNames: []
    readonly property string monitorMode: "focused"
    readonly property string baseDir: ""
    // What it has instead: tray styles and the floating pill (settings page, Display).
    readonly property bool trayOptions: true

    readonly property bool autostartAvailable: backend.autostartAvailable
    readonly property bool autostart: backend.autostart
    function setAutostart(enabled) {
        backend.setAutostart(enabled);
    }

    function providerIcon(provider) {
        var file = provider && provider.icon ? provider.icon : "";
        return file === "" ? "" : root.iconDir + file;
    }

    // ── Settings ─────────────────────────────────────────────────────────────
    // The same JSON file the backend reads its toggles and keys from. On Linux
    // it is also the Hyprland panel's, so fields this frontend has no use for
    // (pill mode, position, interpreter) are carried through untouched.
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
            trayStyle: backend.defaultTrayStyle,
            floatingPill: false,
            language: ""
        })
    property bool showSettings: false
    onSettingsChanged: root.publishTray()
    readonly property string antigravityChartFilter: root.settings.antigravityChartFilter || "both"

    function loadSettings() {
        var d = {};
        try {
            d = JSON.parse(backend.loadSettings() || "{}") || {};
        } catch (e) {}
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
        // trayNumbers was the on/off switch before there were three styles;
        // with neither, the platform's default (app.py, DEFAULT_TRAY_STYLE).
        s.trayStyle = d.trayStyle || (d.trayNumbers === false ? "ring" : d.trayNumbers === true ? "icons" : backend.defaultTrayStyle);
        delete s.trayNumbers;
        s.floatingPill = d.floatingPill === true;
        s.language = d.language || "";
        root.settings = s;
    }

    function saveSettings() {
        backend.saveSettings(JSON.stringify(root.settings));
    }

    function setSetting(section, key, value) {
        var s = JSON.parse(JSON.stringify(root.settings));
        s[section][key] = value;
        root.settings = s;
        root.saveSettings();
    }

    function setSetting2(key, value) {
        var s = JSON.parse(JSON.stringify(root.settings));
        s[key] = value;
        root.settings = s;
        root.saveSettings();
    }

    function providerEnabled(id) {
        return ProviderRegistry.enabled(root.settings, id);
    }

    // ── Provider state ───────────────────────────────────────────────────────
    property var providers: []
    property var sessions: []
    property bool sessionsLoading: false
    property string sessionsError: ""
    property string sessionsNotice: ""
    property string sessionsQuery: ""
    property var sessionsSources: []
    property var sessionsSourceIds: []
    property string sessionsSourceSignature: ""
    property var sessionsActiveSourceIds: []
    property string sessionsActiveSourceSignature: ""
    property int sessionsRequestId: 0
    readonly property int sessionsLimit: 60
    property int sessionsTotal: 0
    property bool sessionsHasMore: false
    property int sessionsOffset: 0
    property int sessionsActiveOffset: 0
    property bool sessionsActiveAppend: false
    property string activeId: ""
    readonly property bool sessionsViewVisible: root.visible && !root.showSettings && root.activeId === "sessions"
    // The last real provider selected (never a feature tab id) — what the
    // panel pill shows while a feature tab (Overview/Spend/Sessions) is
    // active, since those have no percentage of their own to display.
    property string lastProviderId: ""
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
    property string errorText: ""
    readonly property bool loading: backend.busy
    property int updatedAt: 0
    property double nowTick: new Date().getTime()
    readonly property color dangerColor: "#ff4d4d"

    property string chartWindow: "weekly"
    property string chartGranularity: "7d"
    property string activeSubTab: "usage"
    readonly property bool activeHasStats: {
        if (root.activeIsFeature)
            return false;
        var p = activeProvider();
        return p && (p.id === "claude" || p.id === "openai" || p.id === "copilot" || p.id === "muse" || p.id === "cursor" || p.id === "cline");
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

    function windowsForProvider(id) {
        for (var i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === id)
                return root.providers[i].chartWindows || [];
        }
        return [];
    }

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

    // The glance the Hyprland pill gives: the active tab's slots, which app.py
    // (tray_entries) turns into tray icons in the chosen trayStyle.
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
            style: root.settings.trayStyle || backend.defaultTrayStyle,
            floatingPill: root.settings.floatingPill === true,
            // The active provider's logo leads the numbers, or sits inside the ring.
            icon: p ? root.providerIcon(p) : "",
            tooltip: lines.join("\n"),
            slots: slots
        }));
    }

    // ── Backend fetch ────────────────────────────────────────────────────────
    function applySnapshot(text) {
        try {
            var data = JSON.parse((text || "").trim());
            root.providers = data.providers || [];
            root.updatedAt = data.updatedAt || 0;
            // Seed (or heal, if the remembered one got disabled) the pill's
            // fallback provider — needed even before the user ever leaves a
            // feature tab, since Sessions is the default-enabled one.
            if (!root.providerById(root.lastProviderId))
                root.lastProviderId = data.active || (root.providers[0] || {}).id || "";
            var stillThere = FeatureTabs.isFeatureTab(root.activeId);
            for (var i = 0; i < root.providers.length; i++)
                if (root.providers[i].id === root.activeId)
                    stillThere = true;
            if (!stillThere) {
                var features = FeatureTabs.enabledFeatureTabs(root.settings);
                if (features.length > 0)
                    root.activeId = features[0];
                else
                    root.activeId = data.active || (root.providers[0] || {}).id || "";
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
        backend.refresh();
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
        root.sessionsOffset = 0;
        root.sessionsTotal = 0;
        root.sessionsHasMore = false;
    }

    function sessionSourceSelectionHasStaleIds(available) {
        return SessionSources.hasStaleIds(root.sessionsSourceIds, available);
    }

    function requestSessions(query, reconcile, sourceIds) {
        if (sourceIds !== undefined)
            root.setSessionsSourceIds(sourceIds);
        var normalizedQuery = (query || "").trim();
        root.sessionsQuery = normalizedQuery;
        root.sessionsOffset = 0;
        root.sessionsTotal = 0;
        root.sessionsHasMore = false;
        root.sessionsActiveOffset = 0;
        root.sessionsActiveAppend = false;
        root.sessionsActiveSourceIds = root.sessionsSourceIds.slice(0);
        root.sessionsActiveSourceSignature = root.sessionsSourceSignature;
        root.sessionsRequestId += 1;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root.sessionsNotice = "";
        if (reconcile) {
            if (root.sessionsActiveSourceIds.length > 0)
                backend.refreshSessionsAndQuery(normalizedQuery, root.sessionsRequestId, 0, root.sessionsActiveSourceIds);
            else
                backend.refreshSessionsAndQuery(normalizedQuery, root.sessionsRequestId, 0);
        } else if (root.sessionsActiveSourceIds.length > 0) {
            backend.refreshSessions(normalizedQuery, root.sessionsRequestId, 0, root.sessionsActiveSourceIds);
        } else {
            backend.refreshSessions(normalizedQuery, root.sessionsRequestId, 0);
        }
    }

    function refreshSessions(query, offset, append, sourceIds) {
        root.requestSessions(query, false, sourceIds);
    }

    function querySessions(query, offset, append, sourceIds) {
        if (append !== true) {
            root.requestSessions(query, false, sourceIds);
            return;
        }
        if (sourceIds !== undefined)
            root.setSessionsSourceIds(sourceIds);
        root.sessionsQuery = (query || "").trim();
        root.sessionsActiveOffset = offset === undefined ? 0 : offset;
        root.sessionsActiveAppend = true;
        root.sessionsActiveSourceIds = root.sessionsSourceIds.slice(0);
        root.sessionsActiveSourceSignature = root.sessionsSourceSignature;
        root.sessionsRequestId += 1;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root.sessionsNotice = "";
        if (root.sessionsActiveSourceIds.length > 0)
            backend.refreshSessions(root.sessionsQuery, root.sessionsRequestId, root.sessionsActiveOffset, root.sessionsActiveSourceIds);
        else
            backend.refreshSessions(root.sessionsQuery, root.sessionsRequestId, root.sessionsActiveOffset);
    }

    function reconcileSessions(query, sourceIds) {
        root.requestSessions(query, true, sourceIds);
    }

    function loadMoreSessions() {
        if (root.sessionsLoading || !root.sessionsHasMore)
            return;
        var offset = root.sessionsOffset + root.sessionsLimit;
        root.sessionsActiveOffset = offset;
        root.sessionsActiveAppend = true;
        root.sessionsActiveSourceIds = root.sessionsSourceIds.slice(0);
        root.sessionsActiveSourceSignature = root.sessionsSourceSignature;
        root.sessionsRequestId += 1;
        root.sessionsLoading = true;
        root.sessionsError = "";
        root.sessionsNotice = "";
        if (root.sessionsSourceIds.length > 0)
            backend.refreshSessions(root.sessionsQuery, root.sessionsRequestId, offset, root.sessionsSourceIds);
        else
            backend.refreshSessions(root.sessionsQuery, root.sessionsRequestId, offset);
    }

    // Rows with an empty openKey (Muse) render no button at all.
    function openSession(key) {
        if (!key)
            return;
        root.sessionsNotice = "";
        backend.openSession(key);
    }

    // A tab click only fetches when the data is over a minute old: every
    // refresh asks every provider, and clicking back and forth between tabs
    // would otherwise keep one running all the time.
    property double lastFetched: 0
    function refreshTab() {
        if (new Date().getTime() - root.lastFetched > 60000)
            backend.refresh();
    }

    Timer {
        interval: Math.max(30, root.settings.pollSec || 300) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refresh();
            if (root.sessionsViewVisible && !root.sessionsLoading)
                root.reconcileSessions(root.sessionsQuery);
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowTick = new Date().getTime()
    }

    // ── History ──────────────────────────────────────────────────────────────
    // The same state machine as the other frontends (UsageHistory.js) over the
    // same shared file, which aiusage.historyio owns here as it does behind
    // tools/sh/history-io on Linux.
    property var usageHistory: []
    readonly property int historyLimit: 10000
    property var historyStore: UsageHistory.newStore(root.historyLimit)
    property bool historySaving: false
    property string historyMsg: ""

    function syncUsageHistory() {
        if (root.usageHistory !== root.historyStore.history)
            root.usageHistory = root.historyStore.history;
    }

    function recordHistory() {
        UsageHistory.record(root.historyStore, UsageHistory.collect(root.providers), new Date().getTime());
        root.syncUsageHistory();
        root.saveHistory();
    }

    function saveHistory() {
        if (root.historySaving)
            return;
        var batch = UsageHistory.take(root.historyStore);
        if (!batch)
            return;
        root.historySaving = true;
        historySaveTimeout.restart();
        backend.history(batch.op, JSON.stringify(batch.points));
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
        UsageHistory.done(root.historyStore, res.data);
        root.syncUsageHistory();
        root.saveHistory();
    }

    function exportHistory() {
        backend.history("export", "");
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

    Connections {
        target: backend

        function onSnapshotReady(text) {
            root.applySnapshot(text);
        }

        function onSessionsReady(text, query, requestId) {
            if (requestId !== root.sessionsRequestId || query !== root.sessionsQuery || root.sessionsActiveSourceSignature !== root.sessionsSourceSignature)
                return;
            root.sessionsLoading = false;
            try {
                var data = JSON.parse((text || "").trim());
                if (data.error) {
                    root.sessionsError = data.error;
                    root.sessions = data.sessions || [];
                } else {
                    var page = data.sessions || [];
                    var responseSources = root.normalizeSessionSources(data.sources);
                    var staleSelection = root.sessionSourceSelectionHasStaleIds(responseSources);
                    root.sessionsSources = responseSources;
                    if (staleSelection) {
                        root.sessionsSourceIds = [];
                        root.sessionsSourceSignature = "";
                        root.sessionsRequestId += 1;
                        root.sessions = [];
                        root.sessionsOffset = 0;
                        root.sessionsTotal = 0;
                        root.sessionsHasMore = false;
                        root.sessionsLoading = true;
                        root.requestSessions(root.sessionsQuery, false, []);
                        return;
                    }
                    root.sessionsTotal = Number(data.total) || 0;
                    root.sessionsOffset = Number(data.offset) || root.sessionsActiveOffset;
                    root.sessionsHasMore = data.hasMore === true;
                    root.sessions = root.sessionsActiveAppend ? root.sessions.concat(page) : page;
                    root.sessionsError = "";
                }
            } catch (e) {
                root.sessionsError = root.i18n("Could not load sessions.");
            }
        }

        function onOpenSessionFinished(text) {
            try {
                var data = JSON.parse((text || "").trim());
                root.sessionsNotice = data.message || "";
            } catch (e) {
                root.sessionsNotice = root.i18n("Could not resume session.");
            }
        }

        function onRefreshFailed(message) {
            root.errorText = message;
        }

        // The tray menu's switches (tray style, floating pill), JSON-encoded.
        function onSettingRequested(key, value) {
            root.setSetting2(key, JSON.parse(value));
        }

        function onHistoryFinished(op, result) {
            if (op === "autoload") {
                try {
                    var r = JSON.parse(result);
                    if (r && Array.isArray(r.data)) {
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

    // The tray menu is built in app.py, which takes its words from here — again
    // whenever the language changes.
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
            quit: root.i18n("Quit")
        }));
    }

    Component.onCompleted: {
        root.loadSettings();
        root.publishTrayLabels();
        // The first start (no settings file yet): write one now, so that what
        // app.py does for a first start — open the popup — happens only once.
        if (backend.firstRun)
            root.saveSettings();
        backend.history("autoload", "");
    }

    // ── Floating pill ────────────────────────────────────────────────────────
    // The panel pill (hyprland/PanelPill.qml) in a small always-on-top window of
    // its own, for anyone who wants the panel's look rather than tray icons.
    // Drag it anywhere; app.py puts it back where it was left (pillPosition) or,
    // the first time, just above the taskbar. A click opens the popup by it.
    // It never takes focus, so clicking it does not close an open popup first.
    Window {
        id: pillWindow

        objectName: "floatingPill"
        // Declared inside the popup, a Window would be its transient child, and
        // Qt shows a transient child only while its parent is shown — the popup
        // is hidden most of the time. Without a parent it stands on its own.
        transientParent: null
        visible: root.settings.floatingPill === true
        width: pill.implicitWidth + 8
        height: pill.implicitHeight + 8
        color: "transparent"
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        // Matched by the KWin script in app.py (PILL_TITLE) on Plasma Wayland.
        title: "AI Usage pill"

        onXChanged: pillSave.restart()
        onYChanged: pillSave.restart()

        Timer {
            id: pillSave
            interval: 800
            onTriggered: {
                if (pillWindow.visible)
                    root.setSetting2("pillPosition", {
                        x: pillWindow.x,
                        y: pillWindow.y
                    });
            }
        }

        PanelPill {
            id: pill

            readonly property string brandLogo: root.providerIcon(root.pillProvider())

            anchors.centerIn: parent
            iconSource: brandLogo !== "" ? brandLogo : root.iconSource
            // The pill's own hover sits under the drag area below, so the tint
            // is driven from there.
            active: pillMouse.containsMouse || root.visible
            slots: {
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
                // The backend sends text: null for "show the percentage", which a
                // string property cannot take.
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
            stale: {
                var p = root.pillProvider();
                return root.errorText !== "" || (p ? !!p.stale : false);
            }
            hasError: {
                var p = root.pillProvider();
                return root.errorText !== "" || (p ? (p.error || "") !== "" : false);
            }
        }

        // A press that moves drags the window; one that does not is a click.
        MouseArea {
            id: pillMouse

            property point pressedAt
            property bool dragged: false

            anchors.fill: pill
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => {
                pressedAt = Qt.point(mouse.x, mouse.y);
                dragged = false;
            }
            onPositionChanged: mouse => {
                if (pressed && !dragged && Math.abs(mouse.x - pressedAt.x) + Math.abs(mouse.y - pressedAt.y) > 4) {
                    dragged = true;
                    pillWindow.startSystemMove();
                }
            }
            onClicked: {
                if (!dragged)
                    backend.togglePopupFromPill();
            }
        }

        QC.ToolTip {
            // A window of its own: the pill's window is only as big as the pill.
            popupType: QC.Popup.Window
            visible: pillMouse.containsMouse && !pillMouse.pressed && !root.visible && pill.tooltipText !== ""
            delay: 500
            text: pill.tooltipText
        }
    }

    // ── Window ───────────────────────────────────────────────────────────────
    Shortcut {
        sequence: "Escape"
        onActivated: root.hide()
    }

    // The panel drags from anywhere a control does not claim the press — its
    // background, headings, text. Buttons, tabs, the chart's scrub and the
    // settings fields keep their presses. The floating pill comes along
    // (app.py, TrayApp._on_panel_moved; the KWin script on Plasma Wayland).
    DragHandler {
        target: null
        onActiveChanged: {
            if (active)
                root.startSystemMove();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(0.09, 0.10, 0.13, 0.97)
            }
            GradientStop {
                position: 0.5
                color: Qt.rgba(0.06, 0.07, 0.09, 0.97)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(0.04, 0.045, 0.06, 0.98)
            }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        clip: true

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 1
            color: Qt.rgba(1, 1, 1, 0.18)
        }
    }

    // Capped height, so the settings page scrolls rather than running off the
    // screen — see the same Flickable in AiUsageShell.qml.
    Flickable {
        id: contentFlick
        anchors.fill: parent
        anchors.margins: 20
        clip: true
        contentWidth: width
        contentHeight: popupContent.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        QC.ScrollBar.vertical: QC.ScrollBar {
            policy: contentFlick.interactive ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
            width: 6
        }

        Item {
            id: popupContent

            width: contentFlick.width
            height: mainColumn.implicitHeight + (windowsSessionsLoadMore.visible ? windowsSessionsLoadMore.implicitHeight + 10 : 0)

            PopupContent {
                id: mainColumn
                width: parent.width
                shell: root
            }

            SettingsButton {
                id: windowsSessionsLoadMore

                visible: !root.showSettings && root.activeId === "sessions" && root.sessionsHasMore
                x: 0
                y: mainColumn.implicitHeight + 10
                width: parent.width
                text: root.i18n("Load more")
                enabled: !root.sessionsLoading
                onClicked: root.loadMoreSessions()
            }
        }
    }
}
