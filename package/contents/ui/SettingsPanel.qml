import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The settings page. Four sections, one on screen at a time — the whole page at
// once was a wall of unrelated rows in which a provider's own options (its key,
// its quota) sat far from the switch that turns it on.
ColumnLayout {
    id: settingsPanelRoot
    property Item rootItem

    visible: rootItem.showSettings
    Layout.fillWidth: true
    spacing: 10

    function pricingMessage() {
        var status = settingsPanelRoot.rootItem.pricingStatus || "";
        if (settingsPanelRoot.rootItem.pricingLoading === true)
            return i18n("Refreshing pricing…");
        if (status === "refreshed")
            return i18n("Pricing updated.");
        if (status === "stale-good")
            return i18n("Pricing refresh failed; using saved rates.") + (settingsPanelRoot.rootItem.pricingError ? " " + settingsPanelRoot.rootItem.pricingError : "");
        if (status === "no-cache")
            return settingsPanelRoot.rootItem.pricingError || i18n("No pricing rates available; try again.");
        return settingsPanelRoot.rootItem.pricingError || "";
    }

    function pricingMessageColor() {
        var status = settingsPanelRoot.rootItem.pricingStatus || "";
        if (status === "no-cache" || (status === "" && settingsPanelRoot.rootItem.pricingError !== ""))
            return rootItem.dangerColor;
        if (status === "stale-good")
            return "#f5a623";
        if (status === "refreshed")
            return "#34d399";
        return Kirigami.Theme.textColor;
    }

    SubTabBar {
        accent: rootItem.activeAccent
        currentId: rootItem.settingsTab
        tabs: [
            {
                id: "providers",
                label: i18n("Providers")
            },
            {
                id: "views",
                label: i18n("Views")
            },
            {
                id: "appearance",
                label: i18n("Appearance")
            },
            {
                id: "data",
                label: i18nc("settings tab", "Data")
            },
            {
                id: "advanced",
                label: i18n("Advanced")
            }
        ]
        onSelected: id => rootItem.settingsTab = id
    }

    // ── Providers ───────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: rootItem.settingsTab === "providers"

        Repeater {
            // Labels, brand colours and key names all come from the provider
            // registry in main.qml rather than being restated here, so adding a
            // provider there is enough to make it configurable here.
            model: rootItem.providers

            ProviderSettingRow {
                required property var modelData
                provider: modelData
                rootItem: settingsPanelRoot.rootItem
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: i18n("Expand a provider for its API key and options. Keys are optional wherever a local CLI login can be read instead.")
            font.pixelSize: 9
            opacity: 0.4
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }
    }

    // ── Views (Overview / Spend / Sessions) ─────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: rootItem.settingsTab === "views"

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("Optional tabs that sit ahead of your providers in the popup.")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: [
                {
                    id: "overview",
                    label: i18n("Overview"),
                    help: i18n("All enabled providers at a glance")
                },
                {
                    id: "spend",
                    label: i18n("Usage & Spend"),
                    help: i18n("Combined cost figures across providers")
                },
                {
                    id: "sessions",
                    label: i18n("Sessions"),
                    help: i18n("Recent local agent sessions (no transcripts)")
                }
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: {
                        if (modelData.id === "overview")
                            return "#38bdf8";
                        if (modelData.id === "spend")
                            return "#34d399";
                        return "#a78bfa";
                    }
                    Layout.alignment: Qt.AlignVCenter
                }
                PlasmaComponents.Label {
                    text: modelData.label
                    font.pixelSize: 11
                    color: Kirigami.Theme.textColor
                    Layout.preferredWidth: 120
                    elide: Text.ElideRight
                }
                QQC2.Switch {
                    implicitHeight: 20
                    // Same defaults as FeatureTabs.js / Hyprland / Windows:
                    // Overview and Spend are on unless explicitly turned off,
                    // Sessions stays off until explicitly turned on.
                    checked: {
                        var v = Plasmoid.configuration[modelData.id + "Enabled"];
                        if (v === undefined || v === null)
                            return modelData.id !== "sessions";
                        return v === true;
                    }
                    onToggled: Plasmoid.configuration[modelData.id + "Enabled"] = checked
                }
                PlasmaComponents.Label {
                    text: modelData.help
                    font.pixelSize: 9
                    opacity: 0.45
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ── Appearance ──────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: rootItem.settingsTab === "appearance"

        // Plasma loads one translation per plasmashell process, so the widget
        // cannot pick its own language the way the Hyprland and Windows apps do.
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("Language follows System Settings → Region & Language.")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: rootItem.weeklyColor
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("Usage chart")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            QQC2.Switch {
                implicitHeight: 20
                checked: Plasmoid.configuration.showUsageChart
                onToggled: Plasmoid.configuration.showUsageChart = checked
            }
            PlasmaComponents.Label {
                text: i18n("History graph in the popup")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: Kirigami.Theme.highlightColor
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("Theme accent")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            QQC2.Switch {
                implicitHeight: 20
                checked: Plasmoid.configuration.useThemeAccent
                onToggled: {
                    Plasmoid.configuration.useThemeAccent = checked;
                    rootItem.useThemeAccent = checked;
                }
            }
            PlasmaComponents.Label {
                text: i18n("Use Plasma accent color")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: rootItem.activeAccent
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("Panel rotation")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            QQC2.ComboBox {
                id: panelRotationCombo
                implicitHeight: 24
                Layout.preferredWidth: 120
                font.pixelSize: 10
                readonly property var secs: [0, 30, 60, 120, 300, 600]
                model: [i18n("Off"), i18n("30 seconds"), i18n("1 minute"), i18n("2 minutes"), i18n("5 minutes"), i18n("10 minutes")]
                currentIndex: Math.max(0, secs.indexOf(Plasmoid.configuration.panelRotationIntervalSec || 0))
                onActivated: {
                    var seconds = secs[currentIndex];
                    Plasmoid.configuration.panelRotationIntervalSec = seconds;
                }
            }
            PlasmaComponents.Label {
                text: i18n("Rotate pinned providers in the compact panel")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            columns: 3
            columnSpacing: 8
            rowSpacing: 6

            // Row 1: Popup Background Color & Opacity
            PlasmaComponents.Label {
                text: i18n("Popup BG")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            RowLayout {
                spacing: 4
                Layout.fillWidth: true
                Rectangle {
                    width: 12
                    height: 12
                    radius: 2
                    color: rootItem.resolvedPopupBg
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.2)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            rootItem.openColorDialog("popup", rootItem.popupBgColor);
                        }
                        QQC2.ToolTip.delay: 400
                        QQC2.ToolTip.visible: containsMouse
                        QQC2.ToolTip.text: i18n("Click to open color picker")
                    }
                }
                QQC2.TextField {
                    text: Plasmoid.configuration.popupBgColor || "#000000"
                    placeholderText: "#000000"
                    implicitHeight: 22
                    Layout.fillWidth: true
                    font.pixelSize: 9
                    onTextEdited: {
                        if (/^#[0-9A-Fa-f]{6}$/.test(text)) {
                            Plasmoid.configuration.popupBgColor = text;
                            rootItem.popupBgColor = text;
                        }
                    }
                }
            }
            RowLayout {
                spacing: 4
                PlasmaComponents.Label {
                    text: i18n("Opacity:")
                    font.pixelSize: 10
                    opacity: 0.6
                }
                QQC2.TextField {
                    text: Math.round(rootItem.popupBgOpacity * 100)
                    placeholderText: "0"
                    implicitHeight: 22
                    Layout.preferredWidth: 32
                    font.pixelSize: 9
                    validator: IntValidator {
                        bottom: 0
                        top: 100
                    }
                    onTextEdited: {
                        var val = parseInt(text);
                        if (!isNaN(val) && val >= 0 && val <= 100) {
                            var opacityVal = val / 100.0;
                            Plasmoid.configuration.popupBgOpacity = opacityVal;
                            rootItem.popupBgOpacity = opacityVal;
                        }
                    }
                }
                PlasmaComponents.Label {
                    text: "%"
                    font.pixelSize: 10
                    opacity: 0.6
                }
            }

            // Row 2: Card Background Color & Opacity
            PlasmaComponents.Label {
                text: i18n("Card BG")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            RowLayout {
                spacing: 4
                Layout.fillWidth: true
                Rectangle {
                    width: 12
                    height: 12
                    radius: 2
                    color: rootItem.resolvedCardBg
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.2)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            rootItem.openColorDialog("card", rootItem.cardBgColor);
                        }
                        QQC2.ToolTip.delay: 400
                        QQC2.ToolTip.visible: containsMouse
                        QQC2.ToolTip.text: i18n("Click to open color picker")
                    }
                }
                QQC2.TextField {
                    text: Plasmoid.configuration.cardBgColor || "#100a1a"
                    placeholderText: "#100a1a"
                    implicitHeight: 22
                    Layout.fillWidth: true
                    font.pixelSize: 9
                    onTextEdited: {
                        if (/^#[0-9A-Fa-f]{6}$/.test(text)) {
                            Plasmoid.configuration.cardBgColor = text;
                            rootItem.cardBgColor = text;
                        }
                    }
                }
            }
            RowLayout {
                spacing: 4
                PlasmaComponents.Label {
                    text: i18n("Opacity:")
                    font.pixelSize: 10
                    opacity: 0.6
                }
                QQC2.TextField {
                    text: Math.round(rootItem.cardBgOpacity * 100)
                    placeholderText: "90"
                    implicitHeight: 22
                    Layout.preferredWidth: 32
                    font.pixelSize: 9
                    validator: IntValidator {
                        bottom: 0
                        top: 100
                    }
                    onTextEdited: {
                        var val = parseInt(text);
                        if (!isNaN(val) && val >= 0 && val <= 100) {
                            var opacityVal = val / 100.0;
                            Plasmoid.configuration.cardBgOpacity = opacityVal;
                            rootItem.cardBgOpacity = opacityVal;
                        }
                    }
                }
                PlasmaComponents.Label {
                    text: "%"
                    font.pixelSize: 10
                }
            }

            // Row 3: Widget Background Style
            PlasmaComponents.Label {
                text: i18n("Bg Style")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            QQC2.ComboBox {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: 22
                font.pixelSize: 10
                model: [i18n("Plasma Native"), i18n("Translucent (Flat)"), i18n("Glassmorphic (Shadow + Blur)")]
                currentIndex: {
                    var val = rootItem.backgroundHints;
                    if (val === 0)
                        return 0;
                    if (val === 1)
                        return 1;
                    if (val === 2)
                        return 2;
                    return 1;
                }
                onActivated: {
                    var hints = 1;
                    if (index === 0)
                        hints = 0;
                    else if (index === 1)
                        hints = 1;
                    else if (index === 2)
                        hints = 2;
                    Plasmoid.configuration.backgroundHints = hints;
                    rootItem.backgroundHints = hints;
                }
            }
        }
    }

    // ── Data ────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: rootItem.settingsTab === "data"

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: Qt.rgba(1, 1, 1, 0.3)
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("Refresh")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            QQC2.ComboBox {
                id: pollCombo
                implicitHeight: 24
                Layout.preferredWidth: 120
                font.pixelSize: 10
                readonly property var secs: [60, 120, 300, 600, 900, 1800]
                model: [i18n("1 min"), i18n("2 min"), i18n("5 min"), i18n("10 min"), i18n("15 min"), i18n("30 min")]
                currentIndex: Math.max(0, secs.indexOf(Plasmoid.configuration.pollIntervalSec || 300))
                onActivated: {
                    var s = secs[currentIndex];
                    Plasmoid.configuration.pollIntervalSec = s;
                    rootItem.pollIntervalSec = s;
                }
            }
            PlasmaComponents.Label {
                text: i18n("How often usage is re-read")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: rootItem.pricingLoading ? "#f5a623" : rootItem.pricingStatus === "" ? Qt.rgba(1, 1, 1, 0.3) : rootItem.pricingStatus === "stale-good" ? "#f5a623" : rootItem.pricingStatus === "no-cache" ? rootItem.dangerColor : "#34d399"
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("Pricing")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            PlasmaComponents.Button {
                text: rootItem.pricingLoading ? i18n("Refreshing…") : i18n("Refresh pricing")
                implicitHeight: 26
                font.pixelSize: 10
                enabled: !rootItem.pricingLoading
                onClicked: rootItem.refreshPricing()
            }
            Item {
                Layout.fillWidth: true
            }
        }

        PlasmaComponents.Label {
            visible: rootItem.pricingLoading || rootItem.pricingStatus !== "" || rootItem.pricingError !== ""
            text: settingsPanelRoot.pricingMessage()
            font.pixelSize: 9
            opacity: 0.8
            color: settingsPanelRoot.pricingMessageColor()
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: rootItem.activeAccent
                Layout.alignment: Qt.AlignVCenter
            }
            PlasmaComponents.Label {
                text: i18n("History")
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 120
                elide: Text.ElideRight
            }
            PlasmaComponents.Button {
                text: i18n("Export")
                icon.name: "document-export"
                implicitHeight: 26
                font.pixelSize: 10
                onClicked: rootItem.exportHistory()
            }
            PlasmaComponents.Button {
                text: i18n("Import")
                icon.name: "document-import"
                implicitHeight: 26
                font.pixelSize: 10
                onClicked: rootItem.importHistory()
            }
            Item {
                Layout.fillWidth: true
            }
        }

        PlasmaComponents.Label {
            visible: rootItem.historyIOMsg !== ""
            text: rootItem.historyIOMsg
            font.pixelSize: 9
            opacity: 0.6
            color: Kirigami.Theme.textColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        PlasmaComponents.Label {
            text: i18n("The chart's recorded history, as JSON — for a backup, or to carry it to another machine.")
            font.pixelSize: 9
            opacity: 0.4
            color: Kirigami.Theme.textColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    // ── Advanced ────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: rootItem.settingsTab === "advanced"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                PlasmaComponents.Label {
                    text: i18n("Python")
                    font.pixelSize: 10
                    opacity: 0.6
                    color: Kirigami.Theme.textColor
                    Layout.preferredWidth: 76
                    elide: Text.ElideRight
                }
                QQC2.TextField {
                    id: pythonPathField

                    text: Plasmoid.configuration.pythonPath || ""
                    placeholderText: i18n("auto-detect")
                    implicitHeight: 26
                    Layout.fillWidth: true
                    font.pixelSize: 10
                    // Exported as $PYTHON3 to the shell tools; empty restores the
                    // built-in PATH search (python3 → python3.x → python).
                    onEditingFinished: {
                        var val = String(text).trim();
                        if (val === Plasmoid.configuration.pythonPath)
                            return;

                        Plasmoid.configuration.pythonPath = val;
                        text = val;
                        // Re-run immediately so a wrong path shows up as an error
                        // here rather than at the next poll, minutes later.
                        rootItem.refresh();
                    }
                }
            }
            PlasmaComponents.Label {
                text: i18n("Interpreter for the backend — e.g. a venv's bin/python. Empty auto-detects from PATH.")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                PlasmaComponents.Label {
                    text: i18n("Terminal")
                    font.pixelSize: 10
                    opacity: 0.6
                    color: Kirigami.Theme.textColor
                    Layout.preferredWidth: 76
                    elide: Text.ElideRight
                }
                QQC2.TextField {
                    id: cliPathField

                    // Resolved at runtime like every other tool path, so it stays
                    // correct wherever the plasmoid is installed.
                    readOnly: true
                    text: rootItem.scriptDir + "ai-usage-cli"
                    implicitHeight: 26
                    Layout.fillWidth: true
                    font.pixelSize: 10
                }
                PlasmaComponents.Button {
                    text: i18n("Copy")
                    icon.name: "edit-copy"
                    implicitHeight: 26
                    font.pixelSize: 10
                    // QML has no clipboard API without a C++ helper; selecting the
                    // read-only field and copying it is the portable way.
                    onClicked: {
                        cliPathField.selectAll();
                        cliPathField.copy();
                        cliPathField.deselect();
                    }
                }
            }
            PlasmaComponents.Label {
                text: i18n("Same data as this popup, as a table in a shell. Link it into ~/.local/bin to run it as ai-usage-cli, or pass --compact for one status-bar line.")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
