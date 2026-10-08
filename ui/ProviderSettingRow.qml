import QtQuick
import "studio"
import "studio/Theme.js" as Theme
import "js/Tone.js" as Tone

// One provider's settings, whole: the on/off control plus — folded away until
// asked for — its API key and any provider-specific extra. Mirrors the Plasma
// frontend's ProviderSettingRow, so a key sits under the provider it belongs to
// instead of in a separate list that has to be matched back up by name.
// Drawn as a row of a StudioCard.
Item {
    id: prow

    // An entry from shell.allProviders: { id, label, accent, keySetting?, keyPlaceholder? }.
    property var provider: null
    property var shell

    readonly property string providerId: provider ? provider.id : ""
    readonly property string keySetting: provider && provider.keySetting ? provider.keySetting : ""
    readonly property bool serviceOn: shell.providerEnabled(providerId)
    // Muse is the one provider whose plan quota cannot be read for free, so
    // "on" is not one state but two: local-only, and local + the billed live
    // quota. A switch cannot say that; three segments can.
    readonly property bool tristate: providerId === "muse"
    readonly property bool hasDetails: keySetting !== "" || providerId === "copilot"
    readonly property bool keySet: keySetting !== "" && String((shell.settings.keys || {})[keySetting] || "") !== ""
    readonly property bool foldable: (serviceOn || providerId === "selfhosted") && (hasDetails || tristate)
    readonly property color accent: provider ? provider.accent : Theme.brand

    property bool expanded: false

    width: parent ? parent.width : implicitWidth
    height: head.height + (details.visible ? details.height + 14 : 0)

    Rectangle {
        width: parent.width
        height: 1
        color: Tone.c(palette, Theme.line)
        visible: prow.y > 0
    }

    Item {
        id: head
        width: parent.width
        height: 38

        MouseArea {
            anchors.fill: parent
            enabled: prow.foldable
            cursorShape: prow.foldable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: prow.expanded = !prow.expanded
        }

        Rectangle {
            id: badge
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 7
            color: Qt.rgba(prow.accent.r, prow.accent.g, prow.accent.b, prow.serviceOn ? 0.2 : 0.08)
            // The provider's own logo, as on its tab; a colour dot where a
            // provider ships none.
            Image {
                id: logo
                anchors.centerIn: parent
                width: 16
                height: 16
                source: prow.shell.providerIcon(prow.provider)
                sourceSize.width: 32
                sourceSize.height: 32
                fillMode: Image.PreserveAspectFit
                opacity: prow.serviceOn ? 1 : 0.45
                visible: source.toString() !== "" && status !== Image.Error
            }
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: prow.accent
                opacity: prow.serviceOn ? 1 : 0.4
                visible: !logo.visible
            }
        }

        // Name and "key set" on one line, so a row stays one line tall.
        Row {
            anchors.left: badge.right
            anchors.leftMargin: 10
            anchors.right: controls.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                text: prow.provider ? prow.provider.label : ""
                color: Tone.c(palette, Theme.text)
                opacity: prow.serviceOn ? 1 : 0.65
                font.pixelSize: 12
                font.weight: Font.Medium
            }
            Text {
                topPadding: 2
                visible: prow.keySet
                text: prow.shell.i18n("key set")
                color: Theme.ok
                font.pixelSize: 10
            }
        }

        Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // Off / Local / Live — one choice among three, so a segmented
            // control rather than a switch.
            StudioSeg {
                visible: prow.tristate
                accent: prow.accent
                anchors.verticalCenter: parent.verticalCenter
                options: [["off", prow.shell.i18n("Off")], ["local", prow.shell.i18n("Local")], ["live", prow.shell.i18n("Live")]]
                value: !prow.serviceOn ? "off" : (prow.shell.settings.museQuota === true ? "live" : "local")
                onChosen: id => {
                    // Live implies on, and off drops the billed call with it, so
                    // the two settings can never disagree from in here.
                    prow.shell.setSetting("providers", prow.providerId, id !== "off");
                    prow.shell.setSetting2("museQuota", id === "live");
                    if (id !== "off")
                        prow.expanded = true;
                    prow.shell.refresh();
                }
            }

            StudioSwitch {
                visible: !prow.tristate
                anchors.verticalCenter: parent.verticalCenter
                checked: prow.serviceOn
                onToggled: on => {
                    prow.shell.setSetting("providers", prow.providerId, on);
                    prow.shell.refresh();
                }
            }

            // A fixed slot, so every switch lines up whether or not its row folds.
            Item {
                width: 14
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.centerIn: parent
                    visible: prow.foldable
                    text: prow.expanded ? "▴" : "▾"
                    color: Tone.c(palette, Theme.muted)
                    font.pixelSize: 12
                }
            }
        }
    }

    Column {
        id: details
        y: head.height
        width: parent.width
        spacing: 8
        visible: prow.expanded && (prow.serviceOn || prow.providerId === "selfhosted")

        // Label over field, so a long key gets the whole card width.
        Column {
            width: parent.width
            spacing: 4
            visible: prow.keySetting !== ""
            Text {
                text: prow.shell.i18n("API key")
                color: Tone.c(palette, Theme.muted)
                font.pixelSize: 10
            }
            StudioField {
                id: keyField
                width: parent.width
                secret: true
                live: true
                mono: true
                value: String((prow.shell.settings.keys || {})[prow.keySetting] || "")
                placeholder: prow.provider && prow.provider.keyPlaceholder ? prow.provider.keyPlaceholder : ""
                // Stored trimmed: a pasted key often carries a trailing space
                // or newline. The field is left alone while typing.
                onCommitted: v => {
                    prow.shell.setSetting("keys", prow.keySetting, v);
                    refreshDebounce.restart();
                }
            }
        }

        Column {
            width: parent.width
            spacing: 4
            visible: prow.providerId === "selfhosted"
            Text {
                text: prow.shell.i18n("Server URL")
                color: Tone.c(palette, Theme.muted)
                font.pixelSize: 10
            }
            StudioField {
                width: parent.width
                value: prow.shell.settings.selfhostedEndpoint || ""
                placeholder: prow.shell.i18n("Server URLs, separated by commas")
                onCommitted: v => {
                    prow.shell.setSetting2("selfhostedEndpoint", v);
                    prow.shell.refresh();
                }
            }
        }

        Row {
            spacing: 10
            visible: prow.providerId === "selfhosted"
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: prow.shell.i18n("Engine")
                color: Tone.c(palette, Theme.muted)
                font.pixelSize: 10
            }
            StudioSelect {
                width: 140
                options: [["auto", "auto"], ["ollama", "ollama"], ["vllm", "vllm"], ["llama.cpp", "llama.cpp"]]
                value: prow.shell.settings.selfhostedEngine || "auto"
                onChosen: v => {
                    prow.shell.setSetting2("selfhostedEngine", v);
                    prow.shell.refresh();
                }
            }
        }

        // Every other tab reads its quota for free. Muse cannot, so the price
        // of the Live segment is stated next to the control that buys it.
        Text {
            width: parent.width
            visible: prow.tristate
            text: prow.shell.settings.museQuota === true ? prow.shell.i18n("Live: plan windows come from a billed model call (~130 tokens per refresh, cached 30 min).") : prow.shell.i18n("Local: read from Muse's own files, free. Meta reports plan windows only on a billed call — that is what Live buys.")
            color: Tone.c(palette, Theme.muted)
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }

        Column {
            width: parent.width
            spacing: 4
            visible: prow.providerId === "copilot"
            Text {
                text: prow.shell.i18n("Quota")
                color: Tone.c(palette, Theme.muted)
                font.pixelSize: 10
            }
            StudioField {
                width: parent.width
                value: String((prow.shell.settings.keys || {}).copilotQuota || "")
                placeholder: prow.shell.i18n("fallback if the plan reports none")
                live: true
                onCommitted: v => {
                    prow.shell.setSetting("keys", "copilotQuota", v);
                    refreshDebounce.restart();
                }
            }
        }
    }

    // Debounce so we don't spawn a backend refresh on every keystroke.
    Timer {
        id: refreshDebounce
        interval: 1200
        onTriggered: prow.shell.refresh()
    }
}
