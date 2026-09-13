import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic as QC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
// Shared with the Plasma widget. Quickshell sandboxes the QML engine to the
// config root, so these imports only resolve because the root is the repository
// root (see ../shell.qml) rather than this directory — from `hyprland/` they
// would escape it and load as qrc:/qs-blackhole.
import "../package/contents/code/Format.js" as Format
import "../package/contents/code/UsageHistory.js" as UsageHistory
import "ProviderRegistry.js" as ProviderRegistry
import "../package/contents/code/I18n.js" as I18n

// The popup's content is PopupContent.qml, shared with the Windows tray app
// (windows/qml/Main.qml); this root implements the `shell` interface it and
// SettingsPage.qml read. Keep the two roots' interfaces in step.
ShellRoot {
    id: root

    readonly property string baseDir: Qt.resolvedUrl(".").toString().replace("file://", "")
    // Shared provider backend — the same executable the Plasma widget calls.
    readonly property string backendCommand: baseDir + "/../package/contents/tools/sh/get-ai-usage"
    readonly property string iconSource: "file://" + baseDir + "/../package/contents/icons/org.muddyblack.aiUsageWidget.svg"
    readonly property string iconDir: "file://" + baseDir + "/../package/contents/icons/"

    // Translations: the Plasma widget's translate/<lang>.po, parsed by I18n.js.
    // The shared QML calls shell.i18n(…), which xgettext extracts into that
    // catalog; those bindings re-run once catalogLoad below has read it.
    property var catalog: I18n.empty()
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

    // $LANGUAGE first, as gettext does, then the locale's own list.
    function systemLanguages() {
        var list = (Quickshell.env("LANGUAGE") || "").split(":");
        var ui = Qt.locale().uiLanguages;
        for (var i = 0; i < ui.length; i++)
            list.push(ui[i]);
        return I18n.languageCandidates(list);
    }

    // The settings page's choice: "" follows the system, "en" is the untranslated
    // source, anything else names a translate/<lang>.po.
    readonly property string language: root.settings.language || ""
    onLanguageChanged: root.loadCatalog()
    Component.onCompleted: root.loadCatalog()

    function loadCatalog() {
        catalogLoad.exec({
            command: ["sh", "-c", "for l in \"$@\"; do [ -f \"$0/$l.po\" ] && exec cat \"$0/$l.po\"; done; true", root.baseDir + "/../translate"].concat(root.language !== "" ? [root.language] : root.systemLanguages())
        });
    }

    Process {
        id: catalogLoad
        stdout: StdioCollector {
            onStreamFinished: root.catalog = I18n.parsePo(this.text)
        }
    }

    // The catalogs present, for the language picker.
    property var availableLanguages: []
    Process {
        command: ["sh", "-c", "for f in \"$0\"/*.po; do [ -f \"$f\" ] && basename \"$f\" .po; done; true", root.baseDir + "/../translate"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.availableLanguages = this.text.split("\n").filter(function (l) {
                return l !== "";
            })
        }
    }

    // Brand logo for a provider, or "" when the backend ships no artwork for it
    // (callers fall back to the plain accent dot). The id→file mapping lives in
    // the backend contract so both frontends agree on it.
    function providerIcon(provider) {
        var file = provider && provider.icon ? provider.icon : "";
        return file === "" ? "" : root.iconDir + file;
    }

    // Settings the in-popup page writes; the backend reads the same file
    // (AI_USAGE_CONFIG / XDG_CONFIG_HOME) for provider toggles + API keys.
    readonly property string configDir: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME");
        var base = (xdg && xdg !== "") ? xdg : (Quickshell.env("HOME") + "/.config");
        return base + "/ai-usage-widget";
    }
    readonly property string configPath: configDir + "/hyprland-settings.json"

    // All known providers, in display order (used by the settings toggles).
    readonly property var allProviders: ProviderRegistry.providers

    // Which rows of the shared settings page apply here: this frontend has the
    // floating pill and runs the backend through a chosen interpreter, while
    // starting it at login is the compositor config's business.
    readonly property bool pillControls: true
    readonly property bool interpreterControls: true
    readonly property bool autostartAvailable: false
    // Tray styles and a floating pill are the Windows app's; this has a real panel.
    readonly property bool trayOptions: false
    readonly property bool autostart: false
    function setAutostart(enabled) {
    }

    // Connected outputs by name, for the settings page's monitor picker.
    readonly property var screenNames: {
        var names = [];
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++)
            names.push(screens[i].name);
        return names;
    }

    // Live settings model. providers[id] === false → hidden; keys[*] → API keys.
    property var settings: ({
            providers: {},
            keys: {},
            pollSec: 300,
            showChart: true,
            // The backend reads this straight out of the JSON, but it has to
            // survive a round-trip through this object too: saveSettings()
            // writes the whole thing back, so a field missing here is a field
            // erased from the file by the next unrelated setting change.
            museQuota: false,
            antigravityChartFilter: "both",
            pillMode: "always",
            position: "top-right",
            monitor: "focused",
            pythonPath: "",
            language: ""
        })
    property bool showSettings: false
    // Tray-triggered reveal is legitimately global — one tray icon controls
    // every monitor's pill together. Edge-hover reveal is NOT: with a pill on
    // every output, hovering one screen's edge must not pop out the others, so
    // that state lives per PanelWindow instance (panel.hoverRevealed) instead.
    property bool trayPillRevealed: false
    readonly property string antigravityChartFilter: root.settings.antigravityChartFilter || "both"
    readonly property string pillMode: root.settings.pillMode || "always"
    readonly property string windowPosition: root.settings.position || "top-right"
    readonly property bool positionTop: root.windowPosition.indexOf("top-") === 0
    readonly property bool positionBottom: root.windowPosition.indexOf("bottom-") === 0
    readonly property bool positionLeft: root.windowPosition.indexOf("-left") !== -1
    readonly property bool positionCenter: root.windowPosition.indexOf("-center") !== -1
    readonly property bool positionRight: root.windowPosition.indexOf("-right") !== -1

    // ── Output selection ─────────────────────────────────────────────────────
    // "focused" → a single screenless window, which the compositor keeps on the
    // focused output; "all" → one pill per connected output; anything else is a
    // monitor name. A name that is not currently connected falls back to
    // "focused" rather than leaving the user with no pill at all.
    readonly property string monitorMode: root.settings.monitor || "focused"

    // Quickshell.screens entries and Hyprland.focusedMonitor are different types
    // (ShellScreen vs HyprlandMonitor) that happen to share `name`, which is the
    // only way to turn "the compositor's focused output" into something a
    // PanelWindow can bind `screen:` to.
    readonly property var focusedQsScreen: {
        var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        var all = Quickshell.screens;
        for (var i = 0; i < all.length; i++)
            if (all[i].name === name)
                return all[i];
        return all.length > 0 ? all[0] : null;
    }

    // Re-evaluates whenever Hyprland.focusedMonitor changes, so "focused" tracks
    // the compositor's live focus rather than freezing on whatever was focused
    // when the shell launched — PanelWindow has no reactive "follow focus" mode
    // of its own; `screen:` is a plain assignment, so this is what makes it live.
    readonly property var panelScreens: {
        if (root.monitorMode === "all")
            return Quickshell.screens;
        if (root.monitorMode !== "focused") {
            var all = Quickshell.screens;
            for (var i = 0; i < all.length; i++)
                if (all[i].name === root.monitorMode)
                    return [all[i]];
        }
        return [root.focusedQsScreen];
    }

    // With a pill on every output, only one popup may be open at a time: the one
    // belonging to the pill that was clicked (or, over IPC, the focused monitor).
    property string popupScreenName: ""

    function popupOwnedBy(screen) {
        if (root.panelScreens.length < 2)
            return true;
        return !!screen && screen.name === root.popupScreenName;
    }

    function openPopupOn(screen) {
        root.popupScreenName = screen ? screen.name : "";
        root.popupOpen = true;
    }

    // Where an IPC-driven popup should appear when several pills exist.
    function focusedScreenName() {
        var m = Hyprland.focusedMonitor;
        if (m && m.name)
            return m.name;
        return root.focusedQsScreen ? root.focusedQsScreen.name : "";
    }

    function providerEnabled(id) {
        return ProviderRegistry.enabled(root.settings, id);
    }

    Process {
        id: settingsLoad
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || printf '{}'", "ai-usage", root.configPath]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text.trim());
                    // Every field is carried through, known here or not:
                    // saveSettings() writes the whole object back, and on Linux
                    // the Windows tray app shares this file and keeps its own
                    // switches in it (trayNumbers).
                    var s = Object.assign({}, d);
                    s.providers = d.providers || {};
                    s.keys = d.keys || {};
                    s.pollSec = d.pollSec || 300;
                    s.showChart = d.showChart !== false;
                    s.museQuota = d.museQuota === true;
                    s.antigravityChartFilter = d.antigravityChartFilter || "both";
                    s.pillMode = d.pillMode || (d.floatingPill === false ? "tray" : "always");
                    s.position = d.position || "top-right";
                    s.monitor = d.monitor || "focused";
                    s.pythonPath = d.pythonPath || "";
                    s.language = d.language || "";
                    root.settings = s;
                } catch (e) {}
            }
        }
    }

    Process {
        id: settingsSave
    }

    function saveSettings() {
        var json = JSON.stringify(root.settings);
        settingsSave.exec({
            command: ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\"; printf '%s' \"$1\" > \"$2\"", "ai-usage", json, root.configPath]
        });
    }

    // Mutate one nested settings field and persist. `section` is "providers" or
    // "keys"; assigning a fresh object makes the binding re-evaluate.
    function setSetting(section, key, value) {
        var s = JSON.parse(JSON.stringify(root.settings));
        s[section][key] = value;
        root.settings = s;
        root.saveSettings();
    }

    // Mutate a top-level settings field (pollSec, showChart) and persist.
    function setSetting2(key, value) {
        var s = JSON.parse(JSON.stringify(root.settings));
        s[key] = value;
        root.settings = s;
        root.saveSettings();
    }

    property string historyMsg: ""

    // Export a timestamped copy of the shared history via history-io, which
    // snapshots the file itself rather than taking the series on a command line.
    function exportHistory() {
        exportProcess.exec({
            command: ["sh", "-c", "PYTHON3=\"$1\" exec \"$2\" export", "ai-usage", root.settings.pythonPath || "", root.historyTool()]
        });
    }

    Process {
        id: exportProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text.trim());
                    root.historyMsg = r.path ? root.i18n("Saved to %1", r.path) : (r.error || root.i18n("Export failed"));
                } catch (e) {
                    root.historyMsg = root.i18n("Export failed");
                }
                historyMsgTimer.restart();
            }
        }
    }

    Timer {
        id: historyMsgTimer
        interval: 6000
        onTriggered: root.historyMsg = ""
    }

    property var providers: []
    property string activeId: ""
    property string errorText: ""
    property bool loading: false
    property bool popupOpen: false
    property int updatedAt: 0

    // Unified usage history: [{t, s, w, cp, cw, kr, ag, or, mv, gr, za, gh, ds}] — same format
    // as the Plasma widget so the chart survives across both.
    property var usageHistory: []
    readonly property int historyLimit: 10000

    // Clock driving the countdown chips (30 s tick).
    property double nowTick: new Date().getTime()

    readonly property color dangerColor: "#ff4d4d"

    // Chart state: remembered granularity carries across tabs like in Plasma.
    property string chartWindow: "weekly"
    property string chartGranularity: "7d"

    // Inner sub-tab for providers with activity stats (claude, openai,
    // copilot, muse): "usage" vs "stats"
    property string activeSubTab: "usage"
    readonly property bool activeHasStats: {
        var p = activeProvider();
        return p && (p.id === "claude" || p.id === "openai" || p.id === "copilot" || p.id === "muse" || p.id === "cursor" || p.id === "cline");
    }

    function activeProvider() {
        if (root.providers.length === 0)
            return null;
        for (var i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === root.activeId)
                return root.providers[i];
        }
        return root.providers[0];
    }

    readonly property color activeAccent: {
        var p = activeProvider();
        return p ? p.accent : "#cc785c";
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
    }

    function selectChartWindow(id) {
        root.chartWindow = id;
        var gran = windowGranularity(id);
        if (gran !== "")
            root.chartGranularity = gran;
    }

    // ── Countdown chips ──────────────────────────────────────────────────────
    function countdownFor(resetAt) {
        return Format.countdownFromEpoch(resetAt, root.nowTick);
    }

    // ── History persistence ──────────────────────────────────────────────────
    // Both frontends go through tools/sh/history-io, which owns the shared file:
    // it takes a lock, unions the payload into whatever is on disk, replaces the
    // file by rename and hands the merged series back. So a save is also how the
    // Plasma widget's points reach this panel while both are running.
    //
    // What goes out, when, and what comes back is the state machine in
    // UsageHistory.js, shared with the Plasma widget. Left here: the transport,
    // the clock and the watchdog.
    //
    // The file is still never written before it has been read, because the
    // startup read is async while the poll timer fires immediately.
    property var historyStore: UsageHistory.newStore(root.historyLimit)

    function historyTool() {
        return root.baseDir + "/../package/contents/tools/sh/history-io";
    }

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

    // take() decides whether there is anything to send, and what. The process
    // check is on top of that: exec() cannot start the next one until this one
    // has been reaped.
    function saveHistory() {
        if (saveProcess.running)
            return;

        var batch = UsageHistory.take(root.historyStore);
        if (!batch)
            return;

        historySaveTimeout.restart();
        saveProcess.exec({
            command: ["sh", "-c", "PYTHON3=\"$1\" WIDGET_HISTORY_JSON=\"$2\" exec \"$3\" \"$4\"", "ai-usage", root.settings.pythonPath || "", JSON.stringify(batch.points), root.historyTool(), batch.op]
        });
    }

    function finishHistorySave(merged) {
        historySaveTimeout.stop();
        UsageHistory.done(root.historyStore, merged);
        root.syncUsageHistory();
        // Goes now if the process is already reaped; onExited covers the rest.
        root.saveHistory();
    }

    function failHistorySave() {
        historySaveTimeout.stop();
        UsageHistory.failed(root.historyStore);
    }

    // A save that never answers would otherwise hold its batch in flight for the
    // rest of the session and stop this panel mirroring at all. Kill it, and
    // unwind whether or not the kill produces a last empty answer to unwind on —
    // failed() is idempotent, so whichever happens first is the one that counts.
    Timer {
        id: historySaveTimeout
        interval: 30000
        onTriggered: {
            saveProcess.running = false;
            root.failHistorySave();
        }
    }

    Process {
        id: saveProcess
        stdout: StdioCollector {
            onStreamFinished: {
                var res = null;
                try {
                    res = JSON.parse(this.text.trim());
                } catch (e) {}
                if (!res || res.error) {
                    root.failHistorySave();
                    return;
                }
                // The degraded write answers {"ok":true} with no series, which
                // leaves nothing to adopt.
                root.finishHistorySave(res.data);
            }
        }
        // The answer and the exit arrive in either order and the next batch needs
        // both, so both ends try and take() ignores whichever is early. take()
        // also hands out nothing after a failure — without that, unwinding the
        // batch and starting it again here is a loop of failing saves.
        onExited: root.saveHistory()
    }

    Process {
        id: loadProcess
        command: ["sh", "-c", "PYTHON3=\"$1\" exec \"$2\" autoload", "ai-usage", root.settings.pythonPath || "", root.historyTool()]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text.trim());
                    if (r && Array.isArray(r.data)) {
                        // Samples taken while this read was in flight are this
                        // panel's own and stay on top of the file's.
                        UsageHistory.adopt(root.historyStore, r.data);
                        root.syncUsageHistory();
                    }
                } catch (e) {}
                UsageHistory.opened(root.historyStore);
                root.saveHistory();
            }
        }
    }

    // ── Backend fetch ────────────────────────────────────────────────────────
    function applySnapshot(text) {
        root.loading = false;
        try {
            var data = JSON.parse((text || "").trim());
            root.providers = data.providers || [];
            root.updatedAt = data.updatedAt || 0;
            // Keep the active tab if it's still present; otherwise fall back to
            // the backend's suggestion or the first provider (e.g. after the
            // active provider is disabled in settings).
            var stillThere = false;
            for (var i = 0; i < root.providers.length; i++)
                if (root.providers[i].id === root.activeId)
                    stillThere = true;
            if (!stillThere)
                root.activeId = data.active || (root.providers[0] || {}).id || "";
            root.errorText = "";
            root.nowTick = new Date().getTime();
            root.recordHistory();
        } catch (e) {
            root.errorText = root.i18n("usage backend returned no data");
        }
    }

    function refresh() {
        if (backendProcess.running)
            return;
        root.loading = true;
        // $PYTHON3 overrides the interpreter search in tools/sh/python-interp.sh.
        // Passed as a positional arg rather than interpolated into the script so
        // a path with spaces or shell metacharacters stays intact; an empty
        // value reads as unset there, which is the auto-detect default.
        backendProcess.exec({
            command: ["sh", "-c", "PYTHON3=\"$1\" exec \"$2\" --all", "ai-usage", root.settings.pythonPath || "", root.backendCommand],
            workingDirectory: root.baseDir + "/.."
        });
    }

    Process {
        id: backendProcess
        stdout: StdioCollector {
            onStreamFinished: root.applySnapshot(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    root.errorText = this.text.trim().split("\n")[0];
            }
        }
        onExited: function (exitCode) {
            root.loading = false;
            if (exitCode !== 0 && root.errorText === "")
                root.errorText = root.i18n("usage backend failed");
        }
    }

    Timer {
        interval: Math.max(30, root.settings.pollSec || 300) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowTick = new Date().getTime()
    }

    // `qs ipc call panel toggle` from a keybind or script
    IpcHandler {
        target: "panel"

        function toggle(): void {
            if (root.popupOpen) {
                root.popupOpen = false;
                return;
            }
            // Pin it to the focused output, so a keybind opens exactly one popup
            // even when the pill is mirrored across every monitor.
            root.popupScreenName = root.focusedScreenName();
            root.popupOpen = true;
        }
        function refresh(): void {
            root.refresh();
        }
        function setTab(id: string): void {
            root.activeId = id;
        }
        function settings(): void {
            root.showSettings = !root.showSettings;
        }
        function trayEnter(): void {
            trayPillHideTimer.stop();
            root.trayPillRevealed = true;
        }
        function trayLeave(): void {
            trayPillHideTimer.restart();
        }
        function quit(): void {
            Qt.quit();
        }
    }

    Timer {
        id: trayPillHideTimer
        interval: 350
        onTriggered: root.trayPillRevealed = false
    }

    // ── Panel item ───────────────────────────────────────────────────────────
    // One instance per entry in panelScreens: a single screenless window in the
    // usual case, or one per output when the user pins the pill to all monitors.
    Variants {
        model: root.panelScreens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            // Per-instance reveal state — see the comment on trayPillRevealed.
            property bool hoverRevealed: false
            readonly property bool pillShown: root.pillMode === "always" || root.trayPillRevealed || (root.pillMode === "hover" && (panel.hoverRevealed || (root.popupOpen && root.popupOwnedBy(panel.screen))))
            visible: root.pillMode !== "tray" || root.trayPillRevealed
            implicitWidth: panel.pillShown ? pill.implicitWidth + 12 : 72
            implicitHeight: panel.pillShown ? 42 : 4
            color: "transparent"
            aboveWindows: true
            exclusiveZone: 0

            anchors {
                top: root.positionTop
                bottom: root.positionBottom
                left: root.positionLeft || root.positionCenter
                right: root.positionRight
            }

            margins {
                top: root.positionTop ? 8 : 0
                bottom: root.positionBottom ? 8 : 0
                left: root.positionLeft ? 12 : (root.positionCenter && panel.screen ? Math.max(0, (panel.screen.width - panel.width) / 2) : 0)
                right: root.positionRight ? 12 : 0
            }

            PanelPill {
                id: pill
                visible: panel.pillShown
                anchors.centerIn: parent
                // The active provider's brand logo, falling back to the app icon for
                // providers that ship no artwork. PanelSlot tints whichever it gets to
                // the slot's severity colour, so the panel still reads at a glance.
                readonly property string brandLogo: root.providerIcon(root.activeProvider())
                iconSource: brandLogo !== "" ? brandLogo : root.iconSource
                active: root.popupOpen
                slots: {
                    var p = root.activeProvider();
                    if (root.loading && root.providers.length === 0)
                        return [
                            {
                                pct: 0,
                                color: "#cc785c",
                                text: "…",
                                tooltip: root.i18n("Loading")
                            }
                        ];
                    return p && p.slots ? p.slots : [
                        {
                            pct: 0,
                            color: "#cc785c",
                            text: "—",
                            tooltip: root.i18n("No data")
                        }
                    ];
                }
                stale: {
                    var p = root.activeProvider();
                    return root.errorText !== "" || (p ? !!p.stale : false);
                }
                hasError: {
                    var p = root.activeProvider();
                    return root.errorText !== "" || (p ? p.error !== "" : false);
                }
                onClicked: {
                    if (root.popupOpen && root.popupOwnedBy(panel.screen))
                        root.popupOpen = false;
                    else
                        root.openPopupOn(panel.screen);
                }
            }

            // Continuous hover tracking for `hover` pill mode: one HoverHandler
            // spanning the panel's current bounds (72x4 collapsed, full pill
            // expanded), covering both states without a handoff between them.
            // The old design used a separate edge-zone MouseArea to reveal and
            // the pill's own MouseArea to hide, which broke whenever the cursor
            // left before ever registering as "over the pill" — e.g. sweeping
            // straight through to another monitor — leaving the pill stuck open
            // until it was hovered again directly. HoverHandler is passive/
            // non-exclusive, so it tracks alongside PanelPill's own MouseArea
            // without stealing its clicks.
            HoverHandler {
                id: panelHover
                enabled: root.pillMode === "hover"
                onHoveredChanged: {
                    if (hovered) {
                        pillHideTimer.stop();
                        panel.hoverRevealed = true;
                    } else {
                        pillHideTimer.restart();
                    }
                }
            }

            // Closing the popup (click elsewhere, Esc, etc.) doesn't itself move
            // the cursor, so it never fires HoverHandler.onHoveredChanged — if
            // pillHideTimer had already fired once and been held off by the
            // `popupOpen` guard below, nothing would otherwise re-check it, and
            // the pill would stay revealed until directly re-hovered. Re-arm it
            // whenever the popup closes.
            Connections {
                target: root
                function onPopupOpenChanged() {
                    if (!root.popupOpen && root.pillMode === "hover" && !panelHover.hovered)
                        pillHideTimer.restart();
                }
            }

            Timer {
                id: pillHideTimer
                interval: 650
                onTriggered: {
                    if (root.pillMode === "hover" && !panelHover.hovered && !(root.popupOpen && root.popupOwnedBy(panel.screen)))
                        panel.hoverRevealed = false;
                }
            }

            // Hover tooltip (custom: the QQC2 ToolTip style needs Kirigami, which
            // isn't shipped with Quickshell). Gated on the pill's own hover, not
            // panelHover, so it only shows once the pill is actually visible —
            // not while hovering the collapsed edge-reveal zone.
            Timer {
                id: tooltipDelay
                interval: 500
                onTriggered: tooltipPopup.visible = pill.hovered && !root.popupOpen && pill.tooltipText !== ""
            }
            Connections {
                target: pill
                function onHoveredChanged() {
                    if (pill.hovered) {
                        tooltipDelay.restart();
                    } else {
                        tooltipDelay.stop();
                        tooltipPopup.visible = false;
                    }
                }
            }

            PopupWindow {
                id: tooltipPopup
                implicitWidth: tooltipLabel.implicitWidth + 20
                implicitHeight: tooltipLabel.implicitHeight + 14
                visible: false
                color: "transparent"

                anchor.window: panel
                anchor.rect.x: root.positionLeft ? 0 : (root.positionCenter ? (panel.width - width) / 2 : panel.width - width)
                anchor.rect.y: root.positionTop ? panel.height + 4 : -height - 4

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Qt.rgba(0.04, 0.045, 0.06, 0.94)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)

                    Text {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        text: pill.tooltipText
                        color: "#e2e8f0"
                        font.pixelSize: 11
                    }
                }
            }

            // ── Popup (Plasma full representation port) ──────────────────────────
            PanelWindow {
                id: popup
                implicitWidth: 460
                implicitHeight: Math.min(680, mainColumn.implicitHeight + 40)
                visible: root.popupOpen && root.popupOwnedBy(panel.screen)
                color: "transparent"
                aboveWindows: true
                exclusiveZone: 0

                onVisibleChanged: {
                    // Only the popup that actually owns the open state may close it —
                    // the mirrored windows on other outputs are permanently hidden and
                    // would otherwise slam it shut the moment one opened.
                    if (!visible && root.popupOpen && root.popupOwnedBy(panel.screen))
                        root.popupOpen = false;
                }

                anchors {
                    top: root.positionTop
                    bottom: root.positionBottom
                    left: root.positionLeft || root.positionCenter
                    right: root.positionRight
                }
                margins {
                    top: root.positionTop ? (panel.pillShown ? 44 : 8) : 0
                    bottom: root.positionBottom ? (panel.pillShown ? 44 : 8) : 0
                    left: root.positionLeft ? 12 : (root.positionCenter && popup.screen ? Math.max(0, (popup.screen.width - popup.width) / 2) : 0)
                    right: root.positionRight ? 12 : 0
                }

                // Glassmorphism backdrop: tinted gradient, accent glow, top highlight
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(0.09, 0.10, 0.13, 0.96)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.rgba(0.06, 0.07, 0.09, 0.96)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0.04, 0.045, 0.06, 0.97)
                        }
                    }
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    clip: true

                    // crisp inner top highlight line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 1
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.18)
                    }
                }

                // The popup height is capped, but the settings page is far taller than
                // the cap once every provider and API-key field is listed — without a
                // Flickable the last rows (Python path, Save) are simply unreachable.
                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.margins: 20
                    clip: true
                    contentWidth: width
                    contentHeight: mainColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    // Leave wheel events to the chart's range controls when everything
                    // already fits, which is the usual case on the usage page.
                    interactive: contentHeight > height

                    QC.ScrollBar.vertical: QC.ScrollBar {
                        policy: contentFlick.interactive ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
                        width: 6
                    }

                    PopupContent {
                        id: mainColumn
                        width: contentFlick.width
                        shell: root
                    }
                }
            }

            // Same reasoning as the popup's onVisibleChanged: only the owning output
            // grabs focus, or the hidden mirrors would fight over it.
            HyprlandFocusGrab {
                id: popupFocusGrab
                windows: [popup]
                active: root.popupOpen && root.popupOwnedBy(panel.screen)
                onCleared: {
                    if (root.popupOpen && root.popupOwnedBy(panel.screen))
                        root.popupOpen = false;
                }
            }
        }
    }
}
