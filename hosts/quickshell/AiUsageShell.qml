import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QC
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../ui"
import "../../ui/js/I18n.js" as I18n

// The Quickshell / Hyprland host: a panel pill, the popup under it, a keybind
// IPC handler. Everything inside the popup — and all state behind it — is the
// shared ui/ (AppState.qml, PopupContent.qml); this file only places windows.
//
// Quickshell sandboxes the QML engine to the config root, so the imports above
// only resolve because the root is the repository root (see ../../shell.qml)
// rather than this directory.
ShellRoot {
    id: root

    readonly property string baseDir: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string repoDir: root.baseDir + "/../.."

    readonly property string configPath: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME");
        var base = (xdg && xdg !== "") ? xdg : (Quickshell.env("HOME") + "/.config");
        return base + "/ai-usage-widget/hyprland-settings.json";
    }

    ProcessRunner {
        id: runner
        workingDirectory: root.repoDir
    }

    CommandBackend {
        id: commandBackend
        runner: runner
        toolsDir: root.repoDir + "/backend/sh"
        translateDir: root.repoDir + "/translate"
        assetsDir: root.repoDir + "/assets"
        configPath: root.configPath
        pythonPath: app.settings.pythonPath || ""
        // $LANGUAGE first, as gettext does, then the locale's own list.
        systemLanguages: {
            var list = (Quickshell.env("LANGUAGE") || "").split(":");
            var ui = Qt.locale().uiLanguages;
            for (var i = 0; i < ui.length; i++)
                list.push(ui[i]);
            return I18n.languageCandidates(list);
        }
    }

    AppState {
        id: app
        backend: commandBackend
        popupVisible: root.popupOpen
        pillControls: true
        interpreterControls: true
        compositorGlassAvailable: true
        cliPath: root.repoDir + "/backend/sh/ai-usage-cli"
        // Connected outputs by name, for the settings page's monitor picker.
        screenNames: {
            var names = [];
            var screens = Quickshell.screens;
            for (var i = 0; i < screens.length; i++)
                names.push(screens[i].name);
            return names;
        }
    }

    property bool popupOpen: false

    // Tray-triggered reveal is legitimately global — one tray icon controls
    // every monitor's pill together. Edge-hover reveal is NOT: with a pill on
    // every output, hovering one screen's edge must not pop out the others, so
    // that state lives per PanelWindow instance (panel.hoverRevealed) instead.
    property bool trayPillRevealed: false
    readonly property string pillMode: app.settings.pillMode || "always"
    readonly property string windowPosition: app.settings.position || "top-right"
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
    readonly property string monitorMode: app.monitorMode

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
    // the compositor's live focus — `screen:` is a plain assignment, so this is
    // what makes it live.
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
            app.refresh();
        }
        function setTab(id: string): void {
            app.activeId = id;
        }
        function settings(): void {
            app.showSettings = !app.showSettings;
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
            // Our own name rather than Quickshell's default "quickshell", which
            // other shells (Caelestia) share, so layer rules can target us alone.
            WlrLayershell.namespace: "ai-usage-widget"

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
                iconSource: app.pillIcon
                active: root.popupOpen
                slots: app.pillSlots
                stale: app.pillStale
                hasError: app.pillHasError
                groups: app.panelGroups
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
                implicitHeight: Math.min(popup.screen ? Math.min(740, popup.screen.height - 60) : 720, mainColumn.implicitHeight + 40)
                visible: root.popupOpen && root.popupOwnedBy(panel.screen)
                color: "transparent"
                aboveWindows: true
                exclusiveZone: 0
                // The blur itself is Hyprland's: hosts/quickshell/glass.conf
                // matches only the -glass name, so it applies when switched on.
                WlrLayershell.namespace: app.settings.compositorGlass === true ? "ai-usage-widget-glass" : "ai-usage-widget"

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

                // The shared glass (ui/PopupBackground.qml), with its tint and decoration.
                PopupBackground {
                    anchors.fill: parent
                    shell: app
                    blurred: app.settings.compositorGlass === true
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
                    interactive: Math.round(contentHeight) > Math.round(height) + 1

                    QC.ScrollBar.vertical: QC.ScrollBar {
                        policy: contentFlick.interactive ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
                        width: 6
                    }

                    PopupContent {
                        id: mainColumn
                        width: contentFlick.width
                        shell: app
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
