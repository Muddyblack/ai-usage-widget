import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// The popup's content — header, tabs, usage rows, stats, chart and footer —
// shared by every frontend that draws the popup itself: the Quickshell panel
// (AiUsageShell.qml) and the Windows tray app (windows/qml/Main.qml). Only the
// window around it differs, so this file is the one place the popup is laid out.
//
// `shell` is the frontend's root object. Everything read here — providers,
// settings, chart state, refresh() — is part of the interface both roots
// implement; SettingsPage.qml reads the same object.
ColumnLayout {
    id: content

    property var shell

    spacing: 12

    // ── Header ──────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        // Above the rows below, which the status chip's
        // hover card overlaps.
        z: 2

        Item {
            id: headerBadge
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22

            // Brand logos carry their own colours, so they render as-is.
            // The generic app icon has none, so it is tinted to the active
            // accent over a soft halo — the settings page always uses it.
            readonly property string brandLogo: shell.showSettings ? "" : shell.providerIcon(shell.activeProvider())

            Image {
                id: headerHalo
                anchors.centerIn: parent
                width: 22
                height: 22
                source: shell.iconSource
                sourceSize.width: 22
                sourceSize.height: 22
                visible: false
            }
            MultiEffect {
                anchors.fill: headerHalo
                source: headerHalo
                visible: !shell.showSettings && headerBadge.brandLogo === ""
                colorization: 1
                colorizationColor: shell.activeAccent
                opacity: 0.22
            }
            Image {
                id: headerIcon
                anchors.centerIn: parent
                width: 18
                height: 18
                source: shell.iconSource
                sourceSize.width: 18
                sourceSize.height: 18
                visible: false
            }
            MultiEffect {
                anchors.fill: headerIcon
                source: headerIcon
                visible: !shell.showSettings && headerBadge.brandLogo === ""
                colorization: 1
                colorizationColor: shell.activeAccent
            }
            Image {
                anchors.centerIn: parent
                width: 18
                height: 18
                source: headerBadge.brandLogo !== "" ? headerBadge.brandLogo : shell.iconSource
                sourceSize.width: 18
                sourceSize.height: 18
                fillMode: Image.PreserveAspectFit
                visible: shell.showSettings || headerBadge.brandLogo !== ""
            }
        }

        ColumnLayout {
            spacing: 0
            Text {
                text: {
                    if (shell.showSettings)
                        return shell.i18n("Settings");
                    var p = shell.activeProvider();
                    return shell.i18n("%1 Usage", p ? p.label : "AI");
                }
                font.bold: true
                font.pixelSize: 15
                color: "#f8fafc"
            }
            Text {
                visible: shell.showSettings
                // Names the section on screen, so the header
                // says where you are rather than repeating
                // what the page is.
                text: {
                    if (settingsPage.section === "panel")
                        return shell.pillControls ? shell.i18n("Language, pill, position and chart") : shell.i18n("Language and usage chart");

                    if (settingsPage.section === "data")
                        return shell.i18n("Refresh interval and usage history");

                    if (settingsPage.section === "advanced")
                        return shell.interpreterControls ? shell.i18n("Python interpreter and terminal tool") : shell.i18n("Start at login");

                    return shell.i18n("Turn providers on and set their keys");
                }
                font.pixelSize: 10
                opacity: 0.5
                color: "#f8fafc"
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Service status of the active provider; hides itself
        // when the provider has no status page at all.
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            shell: content.shell
            status: {
                var p = shell.activeProvider();
                return !shell.showSettings && p && p.details ? (p.details.status || ({})) : ({});
            }
        }

        // Settings gear / back toggle
        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 26
            radius: 6
            color: gearMouse.containsMouse || shell.showSettings ? Qt.rgba(1, 1, 1, 0.11) : "transparent"

            Text {
                anchors.centerIn: parent
                text: shell.showSettings ? "←" : "⚙"
                color: "#e2e8f0"
                font.pixelSize: 14
                opacity: gearMouse.containsMouse || shell.showSettings ? 1.0 : 0.6
            }
            MouseArea {
                id: gearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shell.showSettings = !shell.showSettings
            }
        }

        Rectangle {
            visible: !shell.showSettings
            Layout.preferredWidth: 28
            Layout.preferredHeight: 26
            radius: 6
            color: refreshMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : "transparent"

            Text {
                anchors.centerIn: parent
                text: "⟳"
                color: "#e2e8f0"
                font.pixelSize: 14
                opacity: refreshMouse.containsMouse ? 1.0 : 0.6
                rotation: shell.loading ? refreshSpin.value : 0
            }
            // simple spin while a refresh is running
            Item {
                id: refreshSpin
                property real value: 0
                NumberAnimation on value {
                    running: shell.loading
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                }
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: shell.refresh()
            }
        }
    }

    // ── Settings page ────────────────────────────────────────────
    SettingsPage {
        id: settingsPage

        // Found by name from windows/app.py --selftest, which opens each section.
        objectName: "settingsPage"
        visible: shell.showSettings
        Layout.fillWidth: true
        shell: content.shell
    }

    // ── Tab bar (Plasma style: logo + name) ─────────────────────
    // A Flow rather than a row: the enabled provider set is
    // user-configurable (up to eleven) while the popup width is fixed,
    // so tabs have to wrap onto another line instead of running off the
    // edge — and each one has to be as wide as its own label, or the
    // longest ("Antigravity") gets clipped by its own border.
    Flow {
        Layout.fillWidth: true
        spacing: 4
        visible: shell.providers.length > 1 && !shell.showSettings

        Repeater {
            model: shell.providers

            Rectangle {
                required property var modelData
                required property int index
                readonly property bool isActive: shell.activeId === modelData.id

                width: tabContent.implicitWidth + 18
                height: 32
                radius: 6
                color: isActive ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                border.width: 1
                border.color: isActive ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        shell.activeId = modelData.id;
                        // A shell may throttle what a tab switch fetches
                        // (the Windows app does); the ⟳ button always refreshes.
                        if (typeof shell.refreshTab === "function")
                            shell.refreshTab();
                        else
                            shell.refresh();
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: parent.containsMouse && !isActive ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                    }
                }

                RowLayout {
                    id: tabContent
                    anchors.centerIn: parent
                    spacing: 5
                    Image {
                        readonly property string logo: shell.providerIcon(modelData)
                        visible: logo !== ""
                        source: logo
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        sourceSize.width: 12
                        sourceSize.height: 12
                        fillMode: Image.PreserveAspectFit
                        opacity: isActive ? 1.0 : 0.55
                    }
                    Rectangle {
                        visible: shell.providerIcon(modelData) === ""
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: modelData.accent
                        opacity: isActive ? 1.0 : 0.5
                    }
                    Text {
                        text: modelData.label
                        font.pixelSize: 12
                        font.bold: isActive
                        color: "#f8fafc"
                        opacity: isActive ? 1.0 : 0.6
                    }
                }
            }
        }
    }

    Rectangle {
        visible: !shell.showSettings
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }

    // ── Provider detail line (plan / account) ───────────────────
    Text {
        visible: {
            if (shell.showSettings)
                return false;
            var p = shell.activeProvider();
            return p && p.summary.detail !== "" && p.error === "";
        }
        Layout.fillWidth: true
        text: {
            var p = shell.activeProvider();
            return p ? p.summary.detail : "";
        }
        color: "#94a3b8"
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // ── Error banner ────────────────────────────────────────────
    Rectangle {
        visible: {
            if (shell.showSettings)
                return false;
            var p = shell.activeProvider();
            return p && p.error !== "";
        }
        Layout.fillWidth: true
        Layout.preferredHeight: errText.implicitHeight + 18
        radius: 6
        color: Qt.rgba(0.45, 0.06, 0.06, 0.32)
        border.width: 1
        border.color: Qt.rgba(0.95, 0.30, 0.30, 0.32)

        Text {
            id: errText
            anchors.fill: parent
            anchors.margins: 9
            text: {
                var p = shell.activeProvider();
                return p ? p.error : "";
            }
            color: "#fecaca"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    // ── Usage / Stats sub-tab toggle ────────────────────────────
    Rectangle {
        visible: !shell.showSettings && shell.activeHasStats
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 2

            Repeater {
                model: [
                    {
                        id: "usage",
                        label: shell.i18n("Usage")
                    },
                    {
                        id: "stats",
                        label: shell.i18n("Stats")
                    }
                ]

                Rectangle {
                    required property var modelData
                    readonly property bool active: shell.activeSubTab === modelData.id
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 5
                    color: active ? Qt.rgba(shell.activeAccent.r, shell.activeAccent.g, shell.activeAccent.b, 0.20) : "transparent"
                    border.width: active ? 1 : 0
                    border.color: Qt.rgba(shell.activeAccent.r, shell.activeAccent.g, shell.activeAccent.b, 0.35)

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 11
                        font.bold: parent.active
                        color: parent.active ? shell.activeAccent : "#f8fafc"
                        opacity: parent.active ? 1.0 : 0.6
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shell.activeSubTab = modelData.id
                    }
                }
            }
        }
    }

    // ── Usage rows ──────────────────────────────────────────────
    ColumnLayout {
        visible: !shell.showSettings && (!shell.activeHasStats || shell.activeSubTab === "usage")
        Layout.fillWidth: true
        spacing: 12

        UsageRows {
            Layout.fillWidth: true
            provider: shell.activeProvider()
            activeId: shell.activeId
            accent: shell.activeAccent
            countdown: shell.countdownFor
        }

        // Muse is the only provider whose plan bars cost
        // money to fetch, so the tab says where they went
        // rather than looking like it failed to load.
        Text {
            readonly property string quotaError: shell.activeProvider() ? (shell.activeProvider().details.quotaError || "") : ""

            Layout.fillWidth: true
            visible: shell.activeId === "muse" && quotaError !== ""
            text: {
                if (quotaError === "disabled")
                    return shell.i18n("Plan quota is off: Meta reports it only on a billed model call. Everything above is read from Muse's own local files.");
                if (quotaError === "rejected")
                    return shell.i18n("Plan quota: Meta refused the credential.");
                if (quotaError === "unreachable")
                    return shell.i18n("Plan quota: could not reach Meta — the local numbers above are unaffected.");
                if (quotaError === "no-credential")
                    return shell.i18n("Plan quota needs a Meta API key, or a `muse login` that stored one.");
                if (quotaError === "no-model")
                    return shell.i18n("Plan quota needs a model: run Muse once so it caches its catalog.");
                return "";
            }
            font.pixelSize: 9
            color: "#94a3b8"
            opacity: 0.8
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: shell.activeId === "muse" && shell.activeProvider() && (shell.activeProvider().details.quotaError || "") === "" && !(shell.activeProvider().details.current || {}).available && !(shell.activeProvider().details.weekly || {}).available
            text: shell.i18n("No plan windows on this account — pay-as-you-go has none.")
            font.pixelSize: 9
            color: "#94a3b8"
            opacity: 0.8
            wrapMode: Text.WordWrap
        }
    }

    // ── Stats section ───────────────────────────────────────────
    StatsSection {
        visible: !shell.showSettings && shell.activeHasStats && shell.activeSubTab === "stats"
        stats: shell.activeProvider() ? (shell.activeProvider().details.stats || ({})) : ({})
        providerId: shell.activeId
        accent: shell.activeAccent
        shell: content.shell
        currency: shell.activeProvider() ? (shell.activeProvider().details.currency || "USD") : "USD"
    }

    // ── Usage chart ─────────────────────────────────────────────
    UsageChart {
        extraVisible: !shell.showSettings && (!shell.activeHasStats || shell.activeSubTab === "usage") && shell.settings.showChart && shell.activeProvider() && (shell.activeProvider().error || "") === "" && shell.activeProvider().ok !== false && shell.activeProvider().summary.hasChart !== false
        shell: content.shell
        usageHistory: shell.usageHistory
        windows: shell.windowsForProvider(shell.activeId)
        chartWindow: shell.chartWindow
        accent: shell.activeAccent
        currency: shell.activeProvider() ? (shell.activeProvider().details.currency || "") : ""
        activeId: shell.activeId
        antigravityFilter: shell.antigravityChartFilter
        onWindowSelected: function (id) {
            shell.selectChartWindow(id);
        }
        onAntigravityFilterSelected: function (filter) {
            shell.setSetting2("antigravityChartFilter", filter);
        }
    }

    // ── Footer ──────────────────────────────────────────────────
    RowLayout {
        visible: !shell.showSettings
        Layout.fillWidth: true

        Rectangle {
            visible: shell.errorText !== ""
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: shell.dangerColor
            Layout.alignment: Qt.AlignVCenter
        }
        Text {
            visible: shell.errorText !== ""
            text: shell.errorText
            color: shell.dangerColor
            font.pixelSize: 10
            elide: Text.ElideRight
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            visible: shell.updatedAt > 0 && shell.errorText === ""
            text: shell.i18n("updated %1", new Date(shell.updatedAt * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
            color: "#f8fafc"
            opacity: 0.45
            font.pixelSize: 10
        }
    }
}
