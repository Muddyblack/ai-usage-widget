import QtQuick
import QtQuick.Layouts
import "studio"
import "studio/Theme.js" as Theme
import "js/Tone.js" as Tone

// Settings, in the studio design of the Glassy System Monitor and Audio
// Visualizer: a sidebar of sections beside glass cards of described rows. Where
// the host gives it room (the popup widens while settings are open) the
// sections sit in a sidebar; in a narrow popup they become one scrolling row of
// tabs above the same cards. Everything is persisted through
// shell.setSetting()/saveSettings() into the JSON config the backend reads.
//
// Shared by the Plasma widget, the Quickshell panel and the desktop tray app,
// so nothing here imports a host: the shell hands over its screen names, and
// says through pillControls / interpreterControls / autostartAvailable /
// trayOptions which rows apply.
ColumnLayout {
    id: page

    property var shell
    // Which section is on screen. Session-only on purpose: the page always
    // opens on Providers, the section people come here for.
    property string section: shell && shell.settingsSection ? shell.settingsSection : "providers"
    // The popup's header names the section, so it is told which one is open.
    onSectionChanged: if (shell && shell.settingsSection !== section)
        shell.settingsSection = section

    // Data → History: the days "Delete older" keeps, and the armed state of
    // the two-step "Delete all".
    property int pruneDays: 30
    property bool confirmClear: false

    readonly property bool wide: width >= 600
    readonly property color accent: Theme.brand

    // Icons are SVG paths on a 24 x 24 grid.
    readonly property var sections: [
        {
            id: "providers",
            label: shell.i18n("Providers"),
            icon: "M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 12l8-4.5M12 12v9M12 12L4 7.5"
        },
        {
            id: "local",
            label: shell.i18n("Local Models"),
            icon: "M4 5h16v11H4zM8 20h8M12 16v4"
        },
        {
            id: "panel",
            // Without a pill there is no panel to set up, only the chart.
            label: shell.pillControls ? shell.i18n("Panel") : shell.i18n("Display"),
            icon: "M4 5h16v5H4zM4 14h7v6H4zM15 14h5v6h-5z"
        },
        {
            id: "appearance",
            label: shell.i18n("Appearance"),
            icon: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0zM12 3a9 9 0 0 0 0 18z"
        },
        {
            id: "data",
            label: shell.i18nc("settings tab", "Data"),
            icon: "M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3zM4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"
        },
        {
            id: "advanced",
            label: shell.i18n("Advanced"),
            icon: "M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6"
        },
        {
            id: "info",
            label: shell.i18n("Info"),
            icon: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 11v6M12 7.5v.5"
        }
    ]

    spacing: 14

    // [[value, label], …] from parallel arrays.
    function zip(values, labels) {
        return values.map(function (v, i) {
            return [v, labels[i]];
        });
    }

    // The entry of `values` nearest to `current`, for settings stored as a
    // number but picked from a short list.
    function nearest(values, current) {
        var best = values[0];
        for (var i = 1; i < values.length; i++)
            if (Math.abs(values[i] - current) < Math.abs(best - current))
                best = values[i];
        return best;
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
            return Theme.bad;
        if (status === "stale-good")
            return Theme.warn;
        if (status === "refreshed")
            return Theme.ok;
        return Tone.c(palette, Theme.text);
    }

    // Narrow: the sections as a row of tabs above the cards.
    StudioNav {
        Layout.fillWidth: true
        visible: !page.wide
        horizontal: true
        entries: page.sections
        currentId: page.section
        accent: page.accent
        onSelected: id => page.section = id
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        StudioNav {
            visible: page.wide
            Layout.preferredWidth: 156
            Layout.alignment: Qt.AlignTop
            entries: page.sections
            currentId: page.section
            accent: page.accent
            onSelected: id => page.section = id
        }

        // One section at a time; invisible ones take no room in the layout.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 0

            // ── Providers ────────────────────────────────────────────────
            Column {
                Layout.fillWidth: true
                visible: page.section === "providers"
                spacing: 12

                // Detection first: it is what fills the list below on a new install.
                Row {
                    spacing: 12
                    StudioButton {
                        text: page.shell.providerDetectBusy ? page.shell.i18n("Detecting…") : page.shell.i18n("Detect installed providers")
                        enabled: !page.shell.providerDetectBusy
                        onClicked: page.shell.redetectProviders()
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 320)
                        visible: page.shell.providerDetectStatus !== ""
                        text: page.shell.providerDetectStatus
                        color: Tone.c(palette, Theme.muted)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                StudioCard {
                    title: page.shell.i18n("Providers")
                    caption: page.shell.i18n("Expand a provider for its API key and options. Keys are stored in %1; leave one blank to use env vars or an existing CLI login.", page.shell.configPath)

                    // Two columns when there is room, each its own stack so
                    // unfolding one provider only grows its own column.
                    Item {
                        id: providerGrid
                        width: parent.width
                        height: Math.max(colA.height, colB.height)

                        // Labels, accents and key names all come from ProviderRegistry.js,
                        // so adding a provider there is enough to make it configurable here.
                        readonly property var list: (page.shell.allProviders || []).filter(function (p) {
                            return p.id !== "selfhosted";
                        })
                        readonly property bool two: page.wide
                        readonly property real gap: 20

                        Column {
                            id: colA
                            width: providerGrid.two ? (providerGrid.width - providerGrid.gap) / 2 : providerGrid.width
                            Repeater {
                                model: providerGrid.two ? providerGrid.list.filter(function (p, i) {
                                    return i % 2 === 0;
                                }) : providerGrid.list

                                ProviderSettingRow {
                                    required property var modelData
                                    provider: modelData
                                    shell: page.shell
                                }
                            }
                        }

                        Column {
                            id: colB
                            visible: providerGrid.two
                            x: colA.width + providerGrid.gap
                            width: colA.width
                            Repeater {
                                model: providerGrid.two ? providerGrid.list.filter(function (p, i) {
                                    return i % 2 === 1;
                                }) : []

                                ProviderSettingRow {
                                    required property var modelData
                                    provider: modelData
                                    shell: page.shell
                                }
                            }
                        }

                        Rectangle {
                            visible: providerGrid.two
                            x: colA.width + providerGrid.gap / 2
                            width: 1
                            height: parent.height
                            color: Tone.c(palette, Theme.line)
                        }
                    }
                }
            }

            // ── Local Models ─────────────────────────────────────────────
            Column {
                Layout.fillWidth: true
                visible: page.section === "local"
                spacing: 14

                StudioCard {
                    title: page.shell.i18n("Local Models")
                    caption: page.shell.i18n("Token counters reflect usage since server start. GPU VRAM tracking is enabled automatically where supported.")

                    StudioRow {
                        label: page.shell.i18n("Local Models")
                        desc: page.shell.i18n("Monitor Ollama, vLLM, or llama.cpp servers")
                        dot: "#38bdf8"
                        StudioSwitch {
                            checked: page.shell.providerEnabled("selfhosted")
                            onToggled: on => {
                                page.shell.setSetting("providers", "selfhosted", on);
                                page.shell.refresh();
                            }
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Server URLs")
                        desc: page.shell.i18n("Separate multiple endpoints with commas. Leave empty to auto-discover Ollama (:11434), vLLM (:8000), and llama.cpp (:8080).")
                        full: true
                        StudioField {
                            width: parent.width
                            value: page.shell.settings.selfhostedEndpoint || ""
                            placeholder: page.shell.i18n("e.g. http://127.0.0.1:11434, http://127.0.0.1:8000")
                            onCommitted: v => {
                                page.shell.setSetting2("selfhostedEndpoint", v);
                                page.shell.refresh();
                            }
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Engine")
                        StudioSelect {
                            options: [["auto", "auto"], ["ollama", "ollama"], ["vllm", "vllm"], ["llama.cpp", "llama.cpp"]]
                            value: page.shell.settings.selfhostedEngine || "auto"
                            onChosen: v => {
                                page.shell.setSetting2("selfhostedEngine", v);
                                page.shell.refresh();
                            }
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Bearer Token (optional)")
                        StudioField {
                            secret: true
                            width: 220
                            value: (page.shell.settings.keys && page.shell.settings.keys.selfhosted) || ""
                            placeholder: page.shell.i18n("Optional auth token")
                            onCommitted: v => {
                                page.shell.setSetting("keys", "selfhosted", v);
                                page.shell.refresh();
                            }
                        }
                    }
                }
            }

            // ── Panel & views ────────────────────────────────────────────
            Column {
                Layout.fillWidth: true
                visible: page.section === "panel"
                spacing: 14

                StudioCard {
                    title: page.shell.i18n("Views")
                    caption: page.shell.i18n("Optional tabs that sit ahead of your providers in the popup.")

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

                        StudioRow {
                            required property var modelData
                            label: modelData.label
                            desc: modelData.help
                            dot: modelData.accent
                            StudioSwitch {
                                checked: {
                                    var v = page.shell.settings[modelData.id + "Enabled"];
                                    if (modelData.id === "sessions")
                                        return v === true;
                                    return v !== false;
                                }
                                onToggled: on => page.shell.setSetting2(modelData.id + "Enabled", on)
                            }
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("General")

                    StudioRow {
                        label: page.shell.i18n("Language")
                        dot: "#38bdf8"
                        StudioSelect {
                            // "" follows the system and "en" is the untranslated source; the
                            // rest are whichever translate/*.po catalogs exist, so a new one
                            // shows up here without touching this file.
                            options: {
                                var v = ["", "en"];
                                var langs = page.shell.availableLanguages || [];
                                for (var i = 0; i < langs.length; i++)
                                    if (v.indexOf(langs[i]) === -1)
                                        v.push(langs[i]);
                                return v.map(function (code) {
                                    if (code === "")
                                        return [code, page.shell.i18n("System default")];
                                    if (code === "en")
                                        return [code, "English"];
                                    var name = Qt.locale(code).nativeLanguageName;
                                    return [code, name ? name.charAt(0).toUpperCase() + name.slice(1) : code];
                                });
                            }
                            value: page.shell.settings.language || ""
                            onChosen: v => page.shell.setSetting2("language", v)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Usage chart")
                        dot: Theme.warn
                        StudioSwitch {
                            checked: page.shell.settings.showChart !== false
                            onToggled: on => page.shell.setSetting2("showChart", on)
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("Pill")
                    visible: page.shell.pillControls

                    StudioRow {
                        // TRANSLATORS: the small rounded usage readout floating on the desktop edge
                        label: page.shell.i18n("Pill")
                        dot: Tone.c(palette, "#e2e8f0")
                        StudioSelect {
                            options: page.zip(["always", "hover", "tray"], [page.shell.i18n("Always"), page.shell.i18n("Edge hover"), page.shell.i18n("Tray only")])
                            value: page.shell.settings.pillMode || "always"
                            onChosen: v => page.shell.setSetting2("pillMode", v)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Position")
                        dot: "#7dd3fc"
                        StudioSelect {
                            options: page.zip(["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"], [page.shell.i18n("Top left"), page.shell.i18n("Top center"), page.shell.i18n("Top right"), page.shell.i18n("Bottom left"), page.shell.i18n("Bottom center"), page.shell.i18n("Bottom right")])
                            value: page.shell.settings.position || "top-right"
                            onChosen: v => page.shell.setSetting2("position", v)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Monitor")
                        dot: "#a78bfa"
                        StudioSelect {
                            // The connected outputs are appended live, so the list reflects what is
                            // actually plugged in; a saved name that has since been unplugged still
                            // shows as the current value and keeps working when it comes back.
                            options: {
                                var o = [["focused", page.shell.i18n("Follow focus")], ["all", page.shell.i18n("All monitors")]];
                                var screens = page.shell.screenNames || [];
                                for (var i = 0; i < screens.length; i++)
                                    o.push([screens[i], screens[i]]);
                                var mode = page.shell.monitorMode;
                                if (mode !== "focused" && mode !== "all" && screens.indexOf(mode) === -1)
                                    o.push([mode, mode]);
                                return o;
                            }
                            value: page.shell.monitorMode
                            onChosen: v => page.shell.setSetting2("monitor", v)
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("Panel rotation")
                    caption: page.shell.pinnedTabs.length > 0 ? page.shell.i18np("%1 provider pinned. With several pinned, the panel shows them side by side, or one at a time when rotation is on.", "%1 providers pinned. With several pinned, the panel shows them side by side, or one at a time when rotation is on.", page.shell.pinnedTabs.length) : page.shell.i18n("Pin a provider with the pin on its tab to keep it on the panel whatever the popup shows.")

                    StudioRow {
                        label: page.shell.i18n("Panel rotation")
                        dot: "#fbbf24"
                        StudioSelect {
                            options: page.zip([0, 30, 60, 120, 300, 600], [page.shell.i18n("Off"), page.shell.i18n("30 seconds"), page.shell.i18n("1 minute"), page.shell.i18n("2 minutes"), page.shell.i18n("5 minutes"), page.shell.i18n("10 minutes")])
                            value: page.shell.panelRotationSec
                            onChosen: v => page.shell.setSetting2("panelRotationSec", v)
                        }
                    }
                }

                // The desktop tray app's own display choices (hosts/desktop/app.py,
                // tray_entries); a shell with a real panel has none of them.
                StudioCard {
                    title: page.shell.i18n("Tray")
                    visible: page.shell.trayOptions === true
                    caption: page.shell.i18n("Logo and percent reads like the panel pill; the tray gives every icon the same square, so each value is two icons. The floating pill is the panel's own pill in a small window: drag it anywhere, click it for this popup.")

                    StudioRow {
                        label: page.shell.i18n("Tray")
                        dot: "#34d399"
                        StudioSelect {
                            options: page.zip(["icons", "numbers", "ring"], [page.shell.i18n("Logo and percent"), page.shell.i18n("Numbers"), page.shell.i18n("Ring")])
                            value: page.shell.settings.trayStyle || "icons"
                            onChosen: v => page.shell.setSetting2("trayStyle", v)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Floating pill")
                        dot: "#f472b6"
                        StudioSwitch {
                            checked: page.shell.settings.floatingPill === true
                            onToggled: on => page.shell.setSetting2("floatingPill", on)
                        }
                    }
                }
            }

            // ── Appearance ───────────────────────────────────────────────
            Column {
                Layout.fillWidth: true
                visible: page.section === "appearance"
                spacing: 14

                StudioCard {
                    title: page.shell.i18n("Popup glass")

                    // Light or dark popup (AppState.light, ui/js/Tone.js). Not on
                    // Plasma, where the popup follows the Plasma theme's dialog.
                    StudioRow {
                        // TRANSLATORS: light or dark look of the popup
                        label: page.shell.i18n("Theme")
                        desc: page.shell.i18n("Auto follows the system's light or dark appearance.")
                        dot: "#cbd5e1"
                        visible: !page.shell.appearanceFollowsHost
                        StudioSeg {
                            options: [["auto", page.shell.i18n("Auto")], ["light", page.shell.i18n("Light")], ["dark", page.shell.i18n("Dark")]]
                            value: page.shell.settings.appearance || "auto"
                            onChosen: v => page.shell.setSetting2("appearance", v)
                        }
                    }

                    // Tint and glass are this popup's own fill. On Plasma the
                    // frame is the background and a fill shows as an inner
                    // border (see PopupBackground.qml), so they are not offered.
                    StudioRow {
                        label: page.shell.i18n("Popup tint")
                        dot: page.shell.settings.popupBgColor || "#64748b"
                        visible: !page.shell.backgroundStyleAvailable
                        Row {
                            spacing: 12
                            // A few presets; any #rrggbb can be typed in the field.
                            StudioSwatches {
                                width: 6 * 20 + 5 * 8
                                anchors.verticalCenter: parent.verticalCenter
                                swatches: ["#000000", "#1e3a8a", "#4c1d95", "#134e4a", "#831843", "#78350f"]
                                value: page.shell.settings.popupBgColor || "#000000"
                                onActivated: v => page.shell.setSetting2("popupBgColor", v)
                            }
                            StudioField {
                                width: 88
                                hex: true
                                mono: true
                                value: page.shell.settings.popupBgColor || "#000000"
                                onCommitted: v => page.shell.setSetting2("popupBgColor", v)
                            }
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Glass opacity")
                        desc: page.shell.i18n("How solid the popup's glass is: lower lets the desktop (and the blur, if on) show through.")
                        dot: Tone.c(palette, "#cbd5e1")
                        visible: !page.shell.backgroundStyleAvailable
                        StudioPercent {
                            from: 0.2
                            value: page.shell.settings.popupGlassOpacity === undefined ? 1 : Number(page.shell.settings.popupGlassOpacity)
                            onChosen: v => page.shell.setSetting2("popupGlassOpacity", v)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Tint strength")
                        desc: page.shell.i18n("How much of the tint colour is laid over the glass.")
                        dot: Tone.c(palette, "#94a3b8")
                        visible: !page.shell.backgroundStyleAvailable
                        StudioPercent {
                            value: Number(page.shell.settings.popupBgOpacity || 0)
                            onChosen: v => page.shell.setSetting2("popupBgOpacity", v)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Frost")
                        desc: page.shell.i18n("A milky, grainy frosted look over the glass; keeps text readable over a busy desktop. Pairs well with Blur.")
                        dot: Tone.c(palette, "#e2e8f0")
                        visible: !page.shell.backgroundStyleAvailable
                        StudioPercent {
                            value: Number(page.shell.settings.popupFrost || 0)
                            onChosen: v => page.shell.setSetting2("popupFrost", v)
                        }
                    }
                    StudioRow {
                        // TRANSLATORS: the compositor (KWin or Hyprland) blurs what is behind the popup
                        label: page.shell.i18n("Blur")
                        desc: page.shell.systemBlur === true ? page.shell.i18n("macOS blurs the desktop behind the popup, in the popup's light or dark.") : page.shell.compositorGlassAvailable === true ? page.shell.i18n("Hyprland blurs the desktop behind the popup; the widget adds the layer rule itself.") : page.shell.backgroundStyleApplies ? page.shell.i18n("KWin blurs the desktop behind the widget.") : page.shell.backgroundStyleAvailable ? page.shell.i18n("In a panel, Plasma draws this popup with your Plasma theme: KWin blurs it when the Blur desktop effect is on and the theme's dialog background is translucent.") : page.shell.i18n("This app has no blur of its own; it is drawn by Hyprland or Plasma.")
                        dot: "#7dd3fc"
                        // Plasma: the widget's background hint, translucent (2,
                        // which KWin blurs) or the standard flat dialog (1).
                        // The old "native" choice (0) looked no different, so it
                        // reads as off here. Only on the desktop: a panel
                        // popup ignores the hint (backgroundStyleApplies).
                        StudioSwitch {
                            enabled: page.shell.compositorGlassAvailable === true || page.shell.backgroundStyleApplies === true
                            // macOS: always on, nothing to switch (systemBlur).
                            checked: page.shell.systemBlur === true || (page.shell.compositorGlassAvailable === true ? page.shell.settings.compositorGlass === true : Number(page.shell.settingValue("backgroundHints")) === 2)
                            onToggled: on => {
                                if (page.shell.compositorGlassAvailable === true)
                                    page.shell.setSetting2("compositorGlass", on);
                                else
                                    page.shell.setSetting2("backgroundHints", on ? 2 : 1);
                            }
                        }
                    }
                    StudioRow {
                        // TRANSLATORS: what is drawn faintly behind the popup's content
                        label: page.shell.i18n("Decoration")
                        dot: page.shell.activeAccent
                        StudioSelect {
                            options: [[0, page.shell.i18n("Accent glow")], [1, page.shell.i18n("Provider logo")], [2, page.shell.i18n("None")]]
                            value: Math.max(0, Math.min(2, Number(page.shell.settings.popupDecoration || 0)))
                            onChosen: v => page.shell.setSetting2("popupDecoration", v)
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("Colours")

                    StudioRow {
                        label: page.shell.i18n("Theme accent")
                        desc: page.shell.i18n("Use the system accent colour")
                        dot: "#38bdf8"
                        visible: page.shell.themeAccentAvailable
                        StudioSwitch {
                            checked: page.shell.settings.themeAccent === true
                            onToggled: on => page.shell.setSetting2("themeAccent", on)
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Card background")
                        desc: page.shell.i18n("Colour of the cards inside the popup, and how opaque they are: lower is more see-through.")
                        dot: page.shell.settings.cardBgColor || "#100a1a"
                        Row {
                            spacing: 12
                            StudioField {
                                width: 88
                                hex: true
                                mono: true
                                value: page.shell.settings.cardBgColor || "#100a1a"
                                onCommitted: v => page.shell.setSetting2("cardBgColor", v)
                            }
                            StudioPercent {
                                value: page.shell.settings.cardBgOpacity === undefined ? 0.9 : Number(page.shell.settings.cardBgOpacity)
                                onChosen: v => page.shell.setSetting2("cardBgOpacity", v)
                            }
                        }
                    }
                }
            }

            // ── Data ─────────────────────────────────────────────────────
            Column {
                Layout.fillWidth: true
                visible: page.section === "data"
                spacing: 14

                StudioCard {
                    title: page.shell.i18n("Refresh")

                    StudioRow {
                        label: page.shell.i18n("Refresh")
                        dot: Tone.c(palette, Theme.dim)
                        StudioSelect {
                            width: 130
                            options: page.zip([60, 120, 300, 600, 900, 1800], [page.shell.i18n("1 min"), page.shell.i18n("2 min"), page.shell.i18n("5 min"), page.shell.i18n("10 min"), page.shell.i18n("15 min"), page.shell.i18n("30 min")])
                            value: page.shell.settings.pollSec || 300
                            onChosen: v => page.shell.setSetting2("pollSec", v)
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("Pricing")

                    StudioRow {
                        label: page.shell.i18n("Pricing")
                        desc: page.shell.pricingLoading || page.shell.pricingStatus !== "" || page.shell.pricingError !== "" ? page.pricingMessage() : ""
                        dot: page.shell.pricingLoading ? Theme.warn : page.shell.pricingStatus === "" ? Tone.c(palette, Theme.dim) : page.shell.pricingStatus === "stale-good" ? Theme.warn : page.shell.pricingStatus === "no-cache" ? Theme.bad : Theme.ok
                        StudioButton {
                            text: page.shell.pricingLoading ? page.shell.i18n("Refreshing…") : page.shell.i18n("Refresh pricing")
                            enabled: !page.shell.pricingLoading
                            onClicked: page.shell.refreshPricing()
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("History")
                    caption: page.shell.i18n("The chart's recorded history, as JSON — for a backup, or to carry it to another machine.")

                    StudioRow {
                        label: page.shell.i18n("History")
                        desc: page.shell.historyMsg !== "" ? page.shell.historyMsg : page.shell.i18np("%1 point", "%1 points", page.shell.usageHistory.length)
                        dot: page.shell.activeAccent
                        StudioButton {
                            text: page.shell.i18n("Export")
                            onClicked: page.shell.exportHistory()
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Delete older history")
                        desc: page.shell.i18n("Keep the last N days and delete everything before that.")
                        dot: Theme.warn
                        Row {
                            spacing: 8
                            StudioField {
                                width: 64
                                value: String(page.pruneDays)
                                onCommitted: v => {
                                    var n = parseInt(v, 10);
                                    if (n > 0)
                                        page.pruneDays = n;
                                    else
                                        value = String(page.pruneDays);
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.shell.i18n("days")
                                color: Tone.c(palette, Theme.muted)
                                font.pixelSize: 11
                            }
                            StudioButton {
                                text: page.shell.i18n("Delete older")
                                onClicked: page.shell.pruneHistory(page.pruneDays)
                            }
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Auto-delete")
                        desc: page.shell.i18n("On every start, delete history older than this many days. 0 keeps everything.")
                        dot: Tone.c(palette, Theme.dim)
                        Row {
                            spacing: 8
                            StudioField {
                                width: 64
                                value: String(Number(page.shell.settings.historyKeepDays || 0))
                                onCommitted: v => {
                                    var n = parseInt(v, 10);
                                    if (n >= 0)
                                        page.shell.setSetting2("historyKeepDays", n);
                                    else
                                        value = String(Number(page.shell.settings.historyKeepDays || 0));
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.shell.i18n("days")
                                color: Tone.c(palette, Theme.muted)
                                font.pixelSize: 11
                            }
                        }
                    }
                    StudioRow {
                        label: page.shell.i18n("Delete all history")
                        desc: page.shell.i18n("Removes the whole chart history. Exported copies stay.")
                        dot: Theme.bad
                        StudioButton {
                            text: page.confirmClear ? page.shell.i18n("Click again to delete") : page.shell.i18n("Delete all…")
                            primary: page.confirmClear
                            onClicked: {
                                if (page.confirmClear) {
                                    page.confirmClear = false;
                                    page.shell.clearHistory();
                                } else {
                                    page.confirmClear = true;
                                    confirmTimer.restart();
                                }
                            }
                        }
                    }
                }

                // The confirm lapses on its own, so a stray first click is harmless.
                Timer {
                    id: confirmTimer
                    interval: 4000
                    onTriggered: page.confirmClear = false
                }
            }

            // ── Advanced ─────────────────────────────────────────────────
            Column {
                Layout.fillWidth: true
                visible: page.section === "advanced"
                spacing: 14

                // Registers the app to start at login — the Windows tray app only; a
                // Quickshell config is started by the compositor's own config.
                StudioCard {
                    title: page.shell.i18n("Start at login")
                    visible: page.shell.autostartAvailable === true

                    StudioRow {
                        label: page.shell.i18n("Start at login")
                        desc: page.shell.i18n("Starts AI Usage in the tray when you sign in. The same switch is in the tray icon's menu.")
                        StudioSwitch {
                            checked: page.shell.autostart === true
                            onToggled: on => page.shell.setAutostart(on)
                        }
                    }
                }

                StudioCard {
                    title: page.shell.i18n("Backend")
                    visible: page.shell.interpreterControls

                    // Interpreter override, exported as $PYTHON3 to the shell tools. Unlike the
                    // API keys this is a top-level setting, not a keys[] entry, because the
                    // shell scripts need it before any Python runs.
                    StudioRow {
                        label: page.shell.i18n("Python")
                        desc: page.shell.i18n("Interpreter for the backend — e.g. a venv's bin/python. Empty auto-detects from PATH (python3 → python3.x → python). The tray helper picks this up on its next refresh.")
                        full: true
                        StudioField {
                            width: parent.width
                            live: true
                            mono: true
                            value: page.shell.settings.pythonPath || ""
                            placeholder: page.shell.i18n("auto-detect")
                            onCommitted: v => {
                                page.shell.setSetting2("pythonPath", v);
                                // Same debounce as the key fields: don't respawn the
                                // backend on every keystroke.
                                pythonRefreshDebounce.restart();
                            }
                        }
                    }
                }

                // Read-only path to the shared CLI, resolved at runtime like backendCommand
                // so it stays correct wherever this is installed.
                StudioCard {
                    title: page.shell.i18n("Terminal")
                    visible: page.shell.interpreterControls
                    caption: page.shell.cliMessage !== "" ? page.shell.cliMessage : ""

                    StudioRow {
                        label: page.shell.i18n("Terminal")
                        desc: page.shell.i18n("Same data as this popup, as a table in a shell. Link it into ~/.local/bin to run it as ai-usage-cli, or pass --compact for one status-bar line.")
                        full: true
                        Column {
                            width: parent.width
                            spacing: 8
                            StudioField {
                                id: cliPathField
                                width: parent.width
                                readOnly: true
                                mono: true
                                value: page.shell.cliPath
                            }
                            Row {
                                spacing: 8
                                // QML has no clipboard API without a C++ helper; selecting the
                                // read-only field and copying it is the portable way.
                                StudioButton {
                                    text: page.shell.i18n("Copy")
                                    onClicked: cliPathField.copyAll()
                                }
                                // Runs it right away, in a terminal window of its own.
                                StudioButton {
                                    visible: page.shell.canOpenCli === true
                                    text: page.shell.i18n("Open in terminal")
                                    onClicked: page.shell.openCli()
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: pythonRefreshDebounce
                    interval: 1200
                    onTriggered: page.shell.refresh()
                }
            }

            // ── Info ─────────────────────────────────────────────────────
            ProjectInfoPane {
                id: infoPane
                Layout.fillWidth: true
                visible: page.section === "info"
                shell: page.shell
            }
        }
    }
}
