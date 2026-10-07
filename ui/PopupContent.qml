import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic as QC
import "js/FeatureTabs.js" as FeatureTabs

// The popup's content — header, tabs, usage rows, stats, chart and footer —
// shared by every frontend that draws the popup itself: the Quickshell panel
// (AiUsageShell.qml) and the Windows tray app (hosts/desktop/qml/Main.qml). Only the
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
            readonly property string brandLogo: shell.showSettings || shell.activeIsFeature ? "" : shell.providerIcon(shell.activeProvider())

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
                    if (shell.activeIsFeature)
                        return FeatureTabs.label(shell.activeId, shell.i18n);
                    var p = shell.activeProvider();
                    return shell.i18n("%1 Usage", p ? p.label : "AI");
                }
                font.bold: true
                font.pixelSize: 15
                color: "#f8fafc"
            }
            Text {
                visible: shell.showSettings || shell.activeIsFeature
                text: {
                    if (shell.showSettings) {
                        if (settingsPage.section === "panel")
                            return shell.pillControls ? shell.i18n("Views, pill, position and chart") : shell.i18n("Views, language and usage chart");

                        if (settingsPage.section === "info")
                            return shell.i18n("About AI Usage Monitor and project links");

                        if (settingsPage.section === "local")
                            return shell.i18n("Local endpoints: Ollama, vLLM and llama.cpp");

                        if (settingsPage.section === "data")
                            return shell.i18n("Refresh interval and usage history");

                        if (settingsPage.section === "advanced")
                            return shell.interpreterControls ? shell.i18n("Python interpreter and terminal tool") : shell.i18n("Start at login");

                        return shell.i18n("Turn providers on and set their keys");
                    }
                    if (shell.activeId === "overview") {
                        var pList = shell.providers || [];
                        return shell.i18np("%1 provider", "%1 providers", pList.length);
                    }
                    if (shell.activeId === "sessions")
                        return shell.sessionsLoading ? shell.i18n("Refreshing…") : shell.i18np("%1 local session", "%1 local sessions", shell.sessionsTotal || 0);
                    if (shell.activeId === "spend") {
                        // Provider/API total: metered spend and plan-inclusive spend
                        var providerRows = FeatureTabs.spendProviderRows(shell.providers, shell.localSpend);
                        var allRows = providerRows.concat(FeatureTabs.localSpendRows(shell.localSpend, providerRows, shell.providers));
                        // The same timeframe the Spend view below is cut to.
                        allRows = FeatureTabs.spendRowsForWindow(allRows, Number(shell.settings.spendWindowDays || 0));
                        return FeatureTabs.spendSummaryText(allRows, "USD", shell.i18n);
                    }
                    return "";
                }
                font.pixelSize: 10
                opacity: 0.5
                color: "#f8fafc"
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Save a picture of the popup (PNG or SVG, into Downloads).
        Rectangle {
            id: saveButton
            visible: !shell.showSettings && typeof shell.exportSnapshot === "function"
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 6
            color: saveMouse.containsMouse || saveMenu.visible ? Qt.rgba(1, 1, 1, 0.11) : "transparent"

            Image {
                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                source: shell.iconDir + "header-save.svg"
                opacity: saveMouse.containsMouse || saveMenu.visible ? 1.0 : 0.7
            }
            MouseArea {
                id: saveMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: saveMenu.visible ? saveMenu.close() : saveMenu.open()
            }

            // Tooltip, drawn here: QQC2's is not available under every host.
            Rectangle {
                visible: saveMouse.containsMouse && !saveMenu.visible
                y: parent.height + 4
                x: parent.width - width
                width: saveTip.implicitWidth + 16
                height: saveTip.implicitHeight + 10
                radius: 5
                z: 10
                color: Qt.rgba(0.04, 0.045, 0.06, 0.96)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
                Text {
                    id: saveTip
                    anchors.centerIn: parent
                    text: shell.i18n("Save this view as a picture")
                    font.pixelSize: 11
                    color: "#e2e8f0"
                }
            }

            QC.Popup {
                id: saveMenu
                y: parent.height + 4
                x: parent.width - width
                padding: 4
                closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutside
                background: Rectangle {
                    radius: 6
                    color: "#12141a"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)
                }
                contentItem: Column {
                    spacing: 2
                    Repeater {
                        model: [
                            {
                                format: "png",
                                label: shell.i18n("Save as PNG")
                            },
                            {
                                format: "svg",
                                label: shell.i18n("Save as SVG")
                            }
                        ]
                        Rectangle {
                            required property var modelData
                            width: Math.max(menuLabel.implicitWidth + 24, 120)
                            height: 26
                            radius: 4
                            color: menuMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                            Text {
                                id: menuLabel
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: parent.modelData.label
                                font.pixelSize: 11
                                color: "#f8fafc"
                            }
                            MouseArea {
                                id: menuMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    saveMenu.close();
                                    shell.exportSnapshot(content, parent.modelData.format);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Settings gear / back toggle
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 6
            color: gearMouse.containsMouse || shell.showSettings ? Qt.rgba(1, 1, 1, 0.11) : "transparent"

            Image {
                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                source: shell.iconDir + (shell.showSettings ? "header-back.svg" : "header-settings.svg")
                opacity: gearMouse.containsMouse || shell.showSettings ? 1.0 : 0.7
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
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 6
            color: refreshMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : "transparent"

            Image {
                anchors.centerIn: parent
                width: 20
                height: 20
                sourceSize.width: 40
                sourceSize.height: 40
                source: shell.iconDir + "header-refresh.svg"
                opacity: refreshMouse.containsMouse ? 1.0 : 0.7
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
                onClicked: {
                    shell.refresh();
                    if (shell.sessionsViewVisible && typeof shell.reconcileSessions === "function")
                        shell.reconcileSessions(shell.sessionsQuery || "");
                }
            }
        }
    }

    // ── Settings page ────────────────────────────────────────────
    SettingsPage {
        id: settingsPage

        // Found by name from hosts/desktop/app.py --selftest, which opens each section.
        objectName: "settingsPage"
        visible: shell.showSettings
        Layout.fillWidth: true
        shell: content.shell
    }

    // ── Tab bar ─────────────────────────────────────────────────
    // One row of equal-width tabs, whatever their number: a tab narrower than
    // 62 px drops its name and keeps its logo (the name is a hover tooltip), so
    // eleven providers still fit one row instead of wrapping onto four. The pin
    // sits in a tab's corner (always while pinned, on hover otherwise); a right
    // click pins too.
    RowLayout {
        id: tabBar
        Layout.fillWidth: true
        spacing: 4
        visible: shell.popupTabs.length > 1 && !shell.showSettings

        Repeater {
            model: shell.popupTabs

            Item {
                id: tabCell
                required property var modelData
                required property int index
                readonly property bool isActive: shell.activeId === modelData.id
                readonly property bool labelFits: width > 62
                readonly property bool canPin: !modelData.feature && typeof shell.togglePin === "function"
                readonly property bool pinned: canPin && typeof shell.isPinned === "function" && shell.isPinned(modelData.id)

                // Equal shares of the row.
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                Layout.preferredHeight: 32
                // Above its neighbours while its tooltip is out.
                z: tabMouse.containsMouse ? 5 : 0

                Rectangle {
                    id: tab
                    anchors.fill: parent
                    radius: 6
                    clip: true
                    color: tabCell.isActive ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                    border.width: 1
                    border.color: tabCell.isActive ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)
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
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (tabCell.canPin)
                                    shell.togglePin(tabCell.modelData.id);
                                return;
                            }
                            var wasSessions = tabCell.modelData.id === "sessions" && shell.activeId === "sessions";
                            shell.activeId = tabCell.modelData.id;
                            // A shell may throttle what a tab switch fetches
                            // (the Windows app does); the ⟳ button always refreshes.
                            if (tabCell.modelData.feature) {
                                if (wasSessions) {
                                    if (typeof shell.reconcileSessions === "function")
                                        shell.reconcileSessions();
                                    else if (typeof shell.refreshSessions === "function")
                                        shell.refreshSessions();
                                }
                                return;
                            }
                            if (typeof shell.refreshTab === "function")
                                shell.refreshTab();
                            else
                                shell.refresh();
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: parent.containsMouse && !tabCell.isActive ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                        }
                    }

                    RowLayout {
                        id: tabContent
                        // Centred, but never wider than the tab, so the content
                        // cannot spill onto its neighbours.
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 14)
                        spacing: 5

                        Image {
                            readonly property string logo: shell.providerIcon(tabCell.modelData)
                            visible: logo !== "" && status !== Image.Error
                            source: logo
                            Layout.preferredWidth: 13
                            Layout.preferredHeight: 13
                            Layout.alignment: Qt.AlignVCenter
                            sourceSize.width: 26
                            sourceSize.height: 26
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            opacity: tabCell.isActive ? 1.0 : 0.55
                        }
                        // Providers without a logo get their accent as a dot.
                        Rectangle {
                            visible: shell.providerIcon(tabCell.modelData) === ""
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            Layout.alignment: Qt.AlignVCenter
                            radius: 4
                            color: tabCell.modelData.accent
                            opacity: tabCell.isActive ? 1.0 : 0.5
                        }
                        Text {
                            visible: tabCell.labelFits
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: tabCell.modelData.label
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: 12
                            font.bold: tabCell.isActive
                            color: "#f8fafc"
                            opacity: tabCell.isActive ? 1.0 : 0.6
                        }
                    }

                    // Pin toggle: a pushpin drawn as head + needle, so it does
                    // not depend on an icon theme or an emoji font.
                    Item {
                        id: pinButton
                        visible: tabCell.canPin && (tabCell.pinned || tabMouse.containsMouse || pinMouse.containsMouse)
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 2
                        anchors.rightMargin: 2
                        width: 10
                        height: 12
                        opacity: tabCell.pinned ? 1.0 : (pinMouse.containsMouse ? 0.9 : 0.45)
                        Rectangle {
                            x: 1
                            y: 0
                            width: 8
                            height: 8
                            radius: 4
                            color: tabCell.pinned ? tabCell.modelData.accent : "transparent"
                            border.width: 1.5
                            border.color: tabCell.pinned ? tabCell.modelData.accent : "#f8fafc"
                        }
                        Rectangle {
                            x: 4
                            y: 8
                            width: 2
                            height: 4
                            color: tabCell.pinned ? tabCell.modelData.accent : "#f8fafc"
                        }
                        MouseArea {
                            id: pinMouse
                            anchors.fill: parent
                            anchors.margins: -3
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.togglePin(tabCell.modelData.id)
                        }
                    }
                }

                // The name of an icon-only tab (QQC2's ToolTip is not available
                // under every host, so it is drawn here).
                Rectangle {
                    id: tabTip
                    visible: !tabCell.labelFits && tabMouse.containsMouse
                    y: tabCell.height + 4
                    x: Math.max(-tabCell.x, Math.min(tabBar.width - tabCell.x - width, (tabCell.width - width) / 2))
                    width: tipLabel.implicitWidth + 16
                    height: tipLabel.implicitHeight + 10
                    radius: 5
                    color: Qt.rgba(0.04, 0.045, 0.06, 0.96)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)
                    Text {
                        id: tipLabel
                        anchors.centerIn: parent
                        text: (tabCell.modelData.label || "") + (tabCell.pinned ? "  ·  " + shell.i18n("Pinned on panel") : "")
                        font.pixelSize: 11
                        color: "#e2e8f0"
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

    // ── Account line: who is signed in, plan / model chips, service status ──
    AccountRow {
        id: accountRow
        z: 10
        shell: content.shell
        account: shell.activeProvider() ? (shell.activeProvider().account || ({})) : ({})
        status: {
            var p = shell.activeProvider();
            return p && p.details ? (p.details.status || ({})) : ({});
        }
        accent: shell.activeAccent
        visible: !shell.showSettings && !shell.activeIsFeature && shell.activeProvider() !== null && accountRow.hasContent
        Layout.fillWidth: true
    }

    // ── Error banner ────────────────────────────────────────────
    Rectangle {
        visible: {
            if (shell.showSettings || shell.activeIsFeature)
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
                return p ? shell.tr(p, "error") : "";
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
                        // TRANSLATORS: sub-tab with activity statistics (tokens, sessions, models)
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

    // ── Feature tabs (Overview / Spend / Sessions) ──────────────
    OverviewPage {
        visible: !shell.showSettings && shell.activeId === "overview"
        Layout.fillWidth: true
        shell: content.shell
    }

    SpendPage {
        visible: !shell.showSettings && shell.activeId === "spend"
        Layout.fillWidth: true
        shell: content.shell
    }

    SessionsPage {
        visible: !shell.showSettings && shell.activeId === "sessions"
        Layout.fillWidth: true
        shell: content.shell
    }

    // ── Usage rows ──────────────────────────────────────────────
    ColumnLayout {
        visible: !shell.showSettings && !shell.activeIsFeature && (!shell.activeHasStats || shell.activeSubTab === "usage")
        Layout.fillWidth: true
        spacing: 12

        UsageRows {
            visible: shell.activeId !== "mistral"
            Layout.fillWidth: true
            // The last known values, shown at start until live ones arrive.
            opacity: shell.replaying ? 0.55 : 1
            provider: shell.activeProvider()
            activeId: shell.activeId
            accent: shell.activeAccent
            countdown: shell.countdownFor
            translate: shell.tr
            // Hover: the row's name, used and remaining share, detail and reset time.
            tooltip: function (w) {
                var parts = [shell.tr(w, "label")];
                if (w.showMeter !== false) {
                    var used = Math.round(w.pct || 0);
                    parts.push(shell.i18n("Used: %1%", used) + "  ·  " + shell.i18n("%1% left", 100 - used));
                }
                var detail = shell.tr(w, "detail");
                if (detail !== "")
                    parts.push(detail);
                if ((w.resetAt || 0) > 0)
                    parts.push(shell.i18n("Resets: %1", Qt.formatDateTime(new Date(w.resetAt * 1000), "MMM d, hh:mm")));
                return parts.join("\n");
            }
        }

        // Per-model quota groups, balances, rates and footnotes the provider
        // reports beyond its rows.
        ProviderSections {
            Layout.fillWidth: true
            shell: content.shell
            provider: shell.activeProvider()
            accent: shell.activeAccent
        }

        MistralUsage {
            Layout.fillWidth: true
            visible: shell.activeId === "mistral" && shell.activeProvider() && !shell.activeProvider().error
            shell: content.shell
            vibe: shell.activeId === "mistral" && shell.activeProvider() ? (shell.activeProvider().details.vibe || ({})) : ({})
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

        // Local ledgers use the same navigable chart, with a token scale.
        OpenCodeUsageChart {
            visible: (shell.activeId === "opencode" || shell.activeId === "mimo" || shell.activeId === "junie") && shell.settings.showChart && shell.activeProvider() !== null && ((shell.activeProvider().details || {}).stats || {}).available === true
            shell: content.shell
            stats: shell.activeProvider() ? ((shell.activeProvider().details || {}).stats || ({})) : ({})
            accent: shell.activeAccent
        }
    }

    // ── Stats section ───────────────────────────────────────────
    StatsSection {
        visible: !shell.showSettings && !shell.activeIsFeature && shell.activeHasStats && shell.activeSubTab === "stats"
        stats: shell.activeProvider() ? (shell.activeProvider().details.stats || ({})) : ({})
        providerId: shell.activeId
        accent: shell.activeAccent
        shell: content.shell
        currency: shell.activeProvider() ? (shell.activeProvider().details.currency || "USD") : "USD"
    }

    // ── Usage chart ─────────────────────────────────────────────
    UsageChart {
        extraVisible: !shell.showSettings && !shell.activeIsFeature && (!shell.activeHasStats || shell.activeSubTab === "usage") && shell.settings.showChart && shell.activeProvider() && (shell.activeProvider().error || "") === "" && shell.activeProvider().ok !== false && shell.activeProvider().summary.hasChart !== false
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
        Text {
            visible: shell.snapshotMsg !== ""
            text: shell.snapshotMsg
            color: "#86efac"
            font.pixelSize: 10
            elide: Text.ElideMiddle
            Layout.maximumWidth: 300
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            visible: shell.updatedAt > 0 && shell.errorText === ""
            text: shell.replaying ? shell.i18n("last known %1 · refreshing…", new Date(shell.updatedAt * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)) : shell.i18n("updated %1", new Date(shell.updatedAt * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
            color: "#f8fafc"
            opacity: 0.45
            font.pixelSize: 10
        }
    }

    // Behind everything while the popup is being saved as a picture, so the
    // picture is opaque: the glass behind the content belongs to the host's
    // window and is not part of the grab. A zero-size layout item (it only
    // takes part in the layout while exporting) whose child draws outside it.
    Item {
        id: exportBackdrop
        visible: shell.exporting === true
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0
        z: -1
        Rectangle {
            // The whole content rectangle, whatever the item's own position.
            x: -exportBackdrop.x
            y: -exportBackdrop.y
            width: content.width
            height: exportBackdrop.y + exportBackdrop.height
            radius: 12
            color: "#0d0f14"
        }
    }
}
