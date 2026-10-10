import QtQuick
import "studio"
import "studio/Theme.js" as Theme
import "js/Tone.js" as Tone

// What a provider needs beyond how it is read: its API key, and the few
// provider-specific extras. Drawn on the provider's own page, where it used to
// be folded under each row of one long list.
Column {
    id: options

    // An entry from shell.allProviders.
    property var provider: null
    property var shell

    readonly property string providerId: provider ? provider.id : ""
    readonly property string keySetting: provider && provider.keySetting ? provider.keySetting : ""
    // Muse is the one provider whose plan quota cannot be read for free.
    readonly property bool hasMuseQuota: providerId === "muse"
    readonly property bool hasCopilotQuota: providerId === "copilot"
    readonly property bool any: keySetting !== "" || hasMuseQuota || hasCopilotQuota

    visible: any
    width: parent ? parent.width : implicitWidth
    height: visible ? implicitHeight : 0
    spacing: 14

    StudioCard {
        title: options.shell.i18n("API key")
        visible: options.keySetting !== ""

        StudioRow {
            label: options.shell.i18n("API key")
            desc: String((options.shell.settings.keys || {})[options.keySetting] || "") !== "" ? options.shell.i18n("A key is set.") : options.shell.i18n("Optional where a login or an environment variable already covers it.")
            full: true
            StudioField {
                width: parent.width
                secret: true
                live: true
                mono: true
                value: String((options.shell.settings.keys || {})[options.keySetting] || "")
                placeholder: options.provider && options.provider.keyPlaceholder ? options.provider.keyPlaceholder : ""
                // Stored trimmed: a pasted key often carries a trailing space
                // or newline. The field is left alone while typing.
                onCommitted: v => {
                    options.shell.setSetting("keys", options.keySetting, v);
                    refreshDebounce.restart();
                }
            }
        }
    }

    // Every other tab reads its quota for free. Muse cannot, so the price of
    // the Live segment is stated next to the control that buys it.
    StudioCard {
        title: options.shell.i18n("Plan quota")
        visible: options.hasMuseQuota

        StudioRow {
            label: options.shell.i18n("Plan windows")
            desc: options.shell.settings.museQuota === true ? options.shell.i18n("Live: plan windows come from a billed model call (~130 tokens per refresh, cached 30 min).") : options.shell.i18n("Local: read from Muse's own files, free. Meta reports plan windows only on a billed call — that is what Live buys.")
            StudioSeg {
                options: [["local", options.shell.i18n("Local")], ["live", options.shell.i18n("Live")]]
                value: options.shell.settings.museQuota === true ? "live" : "local"
                onChosen: id => {
                    options.shell.setSetting2("museQuota", id === "live");
                    options.shell.refresh();
                }
            }
        }
    }

    StudioCard {
        title: options.shell.i18n("Quota")
        visible: options.hasCopilotQuota

        StudioRow {
            label: options.shell.i18n("Quota")
            desc: options.shell.i18n("fallback if the plan reports none")
            StudioField {
                width: 120
                value: String((options.shell.settings.keys || {}).copilotQuota || "")
                live: true
                onCommitted: v => {
                    options.shell.setSetting("keys", "copilotQuota", v);
                    refreshDebounce.restart();
                }
            }
        }
    }

    // Debounce so we don't spawn a backend refresh on every keystroke.
    Timer {
        id: refreshDebounce
        interval: 1200
        onTriggered: options.shell.refresh()
    }
}
