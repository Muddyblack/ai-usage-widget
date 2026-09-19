import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QC

// In-popup settings page, ported from the Plasma SettingsPanel. Four sections,
// one on screen at a time — the whole page at once was a wall of unrelated rows
// in which a provider's own options (its key, its quota) sat far from the
// switch that turns it on. Everything is persisted through
// shell.setSetting()/saveSettings() into the JSON config the backend reads.
//
// Shared by the Quickshell panel and the Windows tray app, so nothing here
// imports Quickshell: the shell hands over its screen names, and says through
// pillControls / interpreterControls / autostartAvailable which rows apply.
ColumnLayout {
    id: page

    property var shell
    // Which section is on screen. Session-only on purpose: the page always
    // opens on Providers, the section people come here for.
    property string section: "providers"

    spacing: 12

    component SectionLabel: Text {
        font.bold: true
        font.pixelSize: 10
        opacity: 0.5
        color: "#f8fafc"
    }

    component SettingCombo: QC.ComboBox {
        id: combo
        implicitHeight: 26
        font.pixelSize: 10
        contentItem: Text {
            leftPadding: 8
            text: combo.displayText
            font: combo.font
            color: "#f8fafc"
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 5
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
        }
        popup: QC.Popup {
            y: combo.height + 2
            width: combo.width
            padding: 1
            background: Rectangle {
                radius: 5
                color: "#12141a"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
            }
            contentItem: ListView {
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                clip: true
            }
        }
        delegate: QC.ItemDelegate {
            width: combo.width
            implicitHeight: 26
            contentItem: Text {
                text: modelData
                color: "#f8fafc"
                font.pixelSize: 10
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                color: highlighted ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            }
            highlighted: combo.highlightedIndex === index
        }
    }

    function pricingMessage() {
        var status = page.shell.pricingStatus || "";
        if (page.shell.pricingLoading === true)
            return page.shell.i18n("Refreshing pricing…");
        if (status === "refreshed")
            return page.shell.i18n("Pricing updated.");
        if (status === "stale-good")
            return page.shell.i18n("Pricing refresh failed; using saved rates.") + (page.shell.pricingError ? " " + page.shell.pricingError : "");
        if (status === "no-cache")
            return page.shell.pricingError || page.shell.i18n("No pricing rates available; try again.");
        return page.shell.pricingError || "";
    }

    function pricingMessageColor() {
        var status = page.shell.pricingStatus || "";
        if (status === "no-cache" || (status === "" && page.shell.pricingError !== ""))
            return "#f87171";
        if (status === "stale-good")
            return "#f5a623";
        if (status === "refreshed")
            return "#34d399";
        return "#f8fafc";
    }

    SegmentBar {
        accent: page.shell.activeAccent
        currentId: page.section
        tabs: [
            {
                id: "providers",
                label: page.shell.i18n("Providers")
            },
            {
                id: "views",
                label: page.shell.i18n("Views")
            },
            {
                id: "panel",
                // Without a pill there is no panel to set up, only the chart.
                label: page.shell.pillControls ? page.shell.i18n("Panel") : page.shell.i18n("Display")
            },
            {
                id: "data",
                label: page.shell.i18nc("settings tab", "Data")
            },
            {
                id: "advanced",
                label: page.shell.i18n("Advanced")
            }
        ]
        onSelected: id => page.section = id
    }

    // ── Providers ────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: page.section === "providers"

        Repeater {
            // Labels, accents and key names all come from ProviderRegistry.js,
            // so adding a provider there is enough to make it configurable here.
            model: page.shell.allProviders

            ProviderSettingRow {
                required property var modelData
                provider: modelData
                shell: page.shell
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 6
            text: page.shell.i18n("Expand a provider for its API key and options. Keys are stored in %1; leave one blank to use env vars or an existing CLI login.", page.shell.configPath)
            font.pixelSize: 9
            opacity: 0.4
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }
    }

    // ── Views (Overview / Spend / Sessions) ──────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: page.section === "views"

        Text {
            Layout.fillWidth: true
            text: page.shell.i18n("Optional tabs that sit ahead of your providers in the popup.")
            font.pixelSize: 9
            opacity: 0.45
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: [
                {
                    id: "overview",
                    label: page.shell.i18n("Overview"),
                    help: page.shell.i18n("All enabled providers at a glance"),
                    accent: "#38bdf8"
                },
                {
                    id: "spend",
                    label: page.shell.i18n("Usage & Spend"),
                    help: page.shell.i18n("Combined cost figures across providers"),
                    accent: "#34d399"
                },
                {
                    id: "sessions",
                    label: page.shell.i18n("Sessions"),
                    help: page.shell.i18n("Recent local agent sessions (no transcripts)"),
                    accent: "#a78bfa"
                }
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: modelData.accent
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: modelData.label
                    font.pixelSize: 11
                    color: "#f8fafc"
                    Layout.preferredWidth: 120
                    elide: Text.ElideRight
                }
                StyledToggle {
                    checked: {
                        var v = page.shell.settings[modelData.id + "Enabled"];
                        if (modelData.id === "sessions")
                            return v === true;
                        return v !== false;
                    }
                    onToggled: page.shell.setSetting2(modelData.id + "Enabled", checked)
                }
                Text {
                    text: modelData.help
                    font.pixelSize: 9
                    opacity: 0.45
                    color: "#f8fafc"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ── Panel ────────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: page.section === "panel"

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#38bdf8"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Language")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingCombo {
                id: languageCombo
                Layout.preferredWidth: 130
                // "" follows the system and "en" is the untranslated source; the
                // rest are whichever translate/*.po catalogs exist, so a new one
                // shows up here without touching this file.
                readonly property var values: {
                    var v = ["", "en"];
                    var langs = page.shell.availableLanguages || [];
                    for (var i = 0; i < langs.length; i++)
                        if (v.indexOf(langs[i]) === -1)
                            v.push(langs[i]);
                    return v;
                }
                model: values.map(function (code) {
                    if (code === "")
                        return page.shell.i18n("System default");
                    if (code === "en")
                        return "English";
                    var name = Qt.locale(code).nativeLanguageName;
                    return name ? name.charAt(0).toUpperCase() + name.slice(1) : code;
                })
                currentIndex: Math.max(0, values.indexOf(page.shell.settings.language || ""))
                onActivated: page.shell.setSetting2("language", values[currentIndex])
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.pillControls
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#e2e8f0"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Pill")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingCombo {
                Layout.preferredWidth: 130
                readonly property var values: ["always", "hover", "tray"]
                model: [page.shell.i18n("Always"), page.shell.i18n("Edge hover"), page.shell.i18n("Tray only")]
                currentIndex: Math.max(0, values.indexOf(page.shell.settings.pillMode || "always"))
                onActivated: page.shell.setSetting2("pillMode", values[currentIndex])
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.pillControls
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#7dd3fc"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Position")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingCombo {
                Layout.preferredWidth: 130
                readonly property var values: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
                model: [page.shell.i18n("Top left"), page.shell.i18n("Top center"), page.shell.i18n("Top right"), page.shell.i18n("Bottom left"), page.shell.i18n("Bottom center"), page.shell.i18n("Bottom right")]
                currentIndex: Math.max(0, values.indexOf(page.shell.settings.position || "top-right"))
                onActivated: page.shell.setSetting2("position", values[currentIndex])
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.pillControls
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#a78bfa"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Monitor")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingCombo {
                id: monitorCombo
                Layout.preferredWidth: 130
                // The connected outputs are appended live, so the list reflects what is
                // actually plugged in; a saved name that has since been unplugged still
                // shows as the current value and keeps working when it comes back.
                readonly property var values: {
                    var v = ["focused", "all"];
                    var screens = page.shell.screenNames || [];
                    for (var i = 0; i < screens.length; i++)
                        v.push(screens[i]);
                    if (v.indexOf(page.shell.monitorMode) === -1)
                        v.push(page.shell.monitorMode);
                    return v;
                }
                model: {
                    var m = [page.shell.i18n("Follow focus"), page.shell.i18n("All monitors")];
                    for (var i = 2; i < monitorCombo.values.length; i++)
                        m.push(monitorCombo.values[i]);
                    return m;
                }
                currentIndex: Math.max(0, values.indexOf(page.shell.monitorMode))
                onActivated: page.shell.setSetting2("monitor", values[currentIndex])
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#f5a623"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Usage chart")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            StyledToggle {
                checked: page.shell.settings.showChart !== false
                onToggled: page.shell.setSetting2("showChart", checked)
            }
            Item {
                Layout.fillWidth: true
            }
        }

        // The Windows tray app's own display choices (windows/app.py,
        // tray_entries); a shell with a real panel has none of them.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.trayOptions === true
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#34d399"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Tray")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingCombo {
                Layout.preferredWidth: 130
                readonly property var values: ["icons", "numbers", "ring"]
                model: [page.shell.i18n("Logo and percent"), page.shell.i18n("Numbers"), page.shell.i18n("Ring")]
                currentIndex: Math.max(0, values.indexOf(page.shell.settings.trayStyle || "icons"))
                onActivated: page.shell.setSetting2("trayStyle", values[currentIndex])
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.trayOptions === true
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#f472b6"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Floating pill")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            StyledToggle {
                checked: page.shell.settings.floatingPill === true
                onToggled: page.shell.setSetting2("floatingPill", checked)
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Text {
            visible: page.shell.trayOptions === true
            Layout.fillWidth: true
            text: page.shell.i18n("Logo and percent reads like the panel pill; the tray gives every icon the same square, so each value is two icons. The floating pill is the panel's own pill in a small window: drag it anywhere, click it for this popup.")
            font.pixelSize: 9
            opacity: 0.4
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }
    }

    // ── Data ─────────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: page.section === "data"

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: Qt.rgba(1, 1, 1, 0.3)
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Refresh")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            QC.ComboBox {
                id: pollCombo
                implicitHeight: 26
                Layout.preferredWidth: 120
                font.pixelSize: 10
                readonly property var secs: [60, 120, 300, 600, 900, 1800]
                model: [page.shell.i18n("1 min"), page.shell.i18n("2 min"), page.shell.i18n("5 min"), page.shell.i18n("10 min"), page.shell.i18n("15 min"), page.shell.i18n("30 min")]
                currentIndex: Math.max(0, secs.indexOf(page.shell.settings.pollSec || 300))
                onActivated: page.shell.setSetting2("pollSec", secs[currentIndex])

                contentItem: Text {
                    leftPadding: 8
                    text: pollCombo.displayText
                    font: pollCombo.font
                    color: "#f8fafc"
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 5
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                }
                popup: QC.Popup {
                    y: pollCombo.height + 2
                    width: pollCombo.width
                    padding: 1
                    background: Rectangle {
                        radius: 5
                        color: "#12141a"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                    }
                    contentItem: ListView {
                        implicitHeight: contentHeight
                        model: pollCombo.popup.visible ? pollCombo.delegateModel : null
                        clip: true
                    }
                }
                delegate: QC.ItemDelegate {
                    width: pollCombo.width
                    implicitHeight: 24
                    contentItem: Text {
                        text: modelData
                        color: "#f8fafc"
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: highlighted ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                    }
                    highlighted: pollCombo.highlightedIndex === index
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: page.shell.pricingLoading ? "#f5a623" : page.shell.pricingStatus === "" ? Qt.rgba(1, 1, 1, 0.3) : page.shell.pricingStatus === "stale-good" ? "#f5a623" : page.shell.pricingStatus === "no-cache" ? "#f87171" : "#34d399"
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("Pricing")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingsButton {
                text: page.shell.pricingLoading ? page.shell.i18n("Refreshing…") : page.shell.i18n("Refresh pricing")
                enabled: !page.shell.pricingLoading
                onClicked: page.shell.refreshPricing()
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Text {
            visible: page.shell.pricingLoading || page.shell.pricingStatus !== "" || page.shell.pricingError !== ""
            Layout.fillWidth: true
            text: page.pricingMessage()
            font.pixelSize: 9
            opacity: 0.8
            color: page.pricingMessageColor()
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: page.shell.activeAccent
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                text: page.shell.i18n("History")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            SettingsButton {
                text: page.shell.i18n("Export")
                onClicked: page.shell.exportHistory()
            }
            Item {
                Layout.fillWidth: true
            }
            Text {
                text: page.shell.i18np("%1 point", "%1 points", page.shell.usageHistory.length)
                font.pixelSize: 9
                opacity: 0.5
                color: "#f8fafc"
            }
        }

        Text {
            visible: page.shell.historyMsg !== ""
            text: page.shell.historyMsg
            font.pixelSize: 9
            opacity: 0.6
            color: "#f8fafc"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            text: page.shell.i18n("The chart's recorded history, as JSON — for a backup, or to carry it to another machine.")
            font.pixelSize: 9
            opacity: 0.4
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }
    }

    // ── Advanced ─────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: page.section === "advanced"

        // Registers the app to start at login — the Windows tray app only; a
        // Quickshell config is started by the compositor's own config.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.autostartAvailable === true

            Text {
                text: page.shell.i18n("Start at login")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            StyledToggle {
                checked: page.shell.autostart === true
                onToggled: page.shell.setAutostart(checked)
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Text {
            visible: page.shell.autostartAvailable === true
            Layout.fillWidth: true
            text: page.shell.i18n("Starts AI Usage in the tray when you sign in. The same switch is in the tray icon's menu.")
            font.pixelSize: 9
            opacity: 0.4
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }

        // Interpreter override, exported as $PYTHON3 to the shell tools. Unlike the
        // API keys this is a top-level setting, not a keys[] entry, because the
        // shell scripts need it before any Python runs.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.interpreterControls

            Text {
                text: page.shell.i18n("Python")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 5
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: pythonField.activeFocus ? Qt.rgba(0.31, 0.62, 0.87, 0.6) : Qt.rgba(1, 1, 1, 0.12)

                QC.TextField {
                    id: pythonField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 4
                    text: page.shell.settings.pythonPath || ""
                    font.pixelSize: 10
                    color: "#f8fafc"
                    placeholderText: page.shell.i18n("auto-detect")
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.3)
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                    selectByMouse: true
                    onTextEdited: {
                        page.shell.setSetting2("pythonPath", text.trim());
                        pythonRefreshDebounce.restart();
                    }
                }
            }
        }

        Text {
            visible: page.shell.interpreterControls
            Layout.fillWidth: true
            text: page.shell.i18n("Interpreter for the backend — e.g. a venv's bin/python. Empty auto-detects from PATH (python3 → python3.x → python). The tray helper picks this up on its next refresh.")
            font.pixelSize: 9
            opacity: 0.4
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }

        // Same debounce as KeyField: don't respawn the backend on every keystroke.
        Timer {
            id: pythonRefreshDebounce
            interval: 1200
            onTriggered: page.shell.refresh()
        }

        // Read-only path to the shared CLI, resolved at runtime like backendCommand
        // so it stays correct wherever this is installed.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: page.shell.interpreterControls

            Text {
                text: page.shell.i18n("Terminal")
                font.pixelSize: 11
                color: "#f8fafc"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 5
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                QC.TextField {
                    id: cliPathField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 4
                    readOnly: true
                    text: page.shell.baseDir + "/../package/contents/tools/sh/ai-usage-cli"
                    font.pixelSize: 10
                    color: "#f8fafc"
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                    selectByMouse: true
                }
            }

            SettingsButton {
                text: page.shell.i18n("Copy")
                // QML has no clipboard API without a C++ helper; selecting the
                // read-only field and copying it is the portable way.
                onClicked: {
                    cliPathField.selectAll();
                    cliPathField.copy();
                    cliPathField.deselect();
                }
            }
        }

        Text {
            visible: page.shell.interpreterControls
            Layout.fillWidth: true
            text: page.shell.i18n("Same data as this popup, as a table in a shell. Link it into ~/.local/bin to run it as ai-usage-cli, or pass --compact for one status-bar line.")
            font.pixelSize: 9
            opacity: 0.4
            color: "#f8fafc"
            wrapMode: Text.WordWrap
        }
    }
}
