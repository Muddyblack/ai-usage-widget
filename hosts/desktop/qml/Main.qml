import QtQuick
import QtQuick.Controls.Basic as QC
import "../../../ui"

// The popup window of the Windows and macOS tray apps (app.py places, shows
// and hides it, and draws the tray icon). Everything inside — and all state
// behind it — is the shared ui/ (AppState.qml, PopupContent.qml), fed by the
// in-process `backend` object app.py exposes. This file is only the window
// around it and the optional floating pill.
Window {
    id: root

    // Wider while the settings studio is open: it has a sidebar.
    width: app.popupWidth
    height: Math.min(720, popupHeader.implicitHeight + 12 + popupContent.height + 28)
    visible: false
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    // Matched by the KWin script in app.py (POPUP_TITLE) on Plasma Wayland.
    title: "AI Usage"

    // Read by app.py (the tray menu's "Settings" and the self-test).
    property alias showSettings: app.showSettings
    readonly property alias settings: app.settings

    // app.py's Backend, a context property. Named apart from AppState's own
    // `backend` property, which would otherwise shadow it in there.
    readonly property var hostBackend: backend

    AppState {
        id: app
        backend: root.hostBackend
        popupVisible: root.visible
        trayOptions: true
    }

    function flushHistory() {
        app.flushHistory();
    }

    // ── Floating pill ────────────────────────────────────────────────────────
    // The panel pill (ui/PanelPill.qml) in a small always-on-top window of
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
        visible: app.settings.floatingPill === true
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
                    app.setSetting2("pillPosition", {
                        x: pillWindow.x,
                        y: pillWindow.y
                    });
            }
        }

        PanelPill {
            id: pill

            anchors.centerIn: parent
            iconSource: app.pillIcon
            // The pill's own hover sits under the drag area below, so the tint
            // is driven from there.
            active: pillMouse.containsMouse || root.visible
            slots: app.pillSlots
            stale: app.pillStale
            hasError: app.pillHasError
            groups: app.panelGroups
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

    // ── Popup ──
    // The shared glass (ui/PopupBackground.qml), with its tint and decoration.
    PopupBackground {
        anchors.fill: parent
        shell: app
    }

    // Capped height, so the settings page scrolls rather than running off the
    // screen — see the same Flickable in AiUsageShell.qml.
    // Title bar and tabs stay put while the body below scrolls.
    PopupHeader {
        id: popupHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        z: 2
        shell: app
        snapshotTarget: root.contentItem
    }

    Flickable {
        id: contentFlick
        anchors.top: popupHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        anchors.topMargin: 12
        clip: true
        contentWidth: width
        contentHeight: popupContent.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: Math.round(contentHeight) > Math.round(height) + 1

        QC.ScrollBar.vertical: QC.ScrollBar {
            policy: contentFlick.interactive ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
            width: 6
        }

        Item {
            id: popupContent

            width: contentFlick.width
            height: mainColumn.implicitHeight

            PopupContent {
                id: mainColumn
                width: parent.width
                shell: app
            }
        }
    }
}
