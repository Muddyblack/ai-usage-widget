import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QC

// One provider's settings, whole: the on/off control plus — folded away until
// asked for — its API key and any provider-specific extra. Mirrors the Plasma
// frontend's ProviderSettingRow, so a key sits under the provider it belongs to
// instead of in a separate list that has to be matched back up by name.
ColumnLayout {
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
    readonly property bool keySet: keySetting !== "" && String(shell.settings.keys[keySetting] || "") !== ""

    property bool expanded: false

    Layout.fillWidth: true
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            Layout.preferredWidth: 7
            Layout.preferredHeight: 7
            radius: 3.5
            color: prow.provider ? prow.provider.accent : "transparent"
            opacity: prow.serviceOn ? 1 : 0.35
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: prow.provider ? prow.provider.label : ""
            font.pixelSize: 11
            color: "#f8fafc"
            opacity: prow.serviceOn ? 1 : 0.6
            Layout.preferredWidth: 86
            elide: Text.ElideRight
        }

        // Off / Local / Live — the same segmented control the popup uses for
        // Usage/Stats, so it reads as a picker rather than a toggle.
        SegmentBar {
            visible: prow.tristate
            Layout.fillWidth: false
            Layout.preferredWidth: 168
            accent: prow.provider ? prow.provider.accent : "#4f9dde"
            tabs: [
                {
                    id: "off",
                    label: prow.shell.i18n("Off")
                },
                {
                    id: "local",
                    label: prow.shell.i18n("Local")
                },
                {
                    id: "live",
                    label: prow.shell.i18n("Live")
                }
            ]
            currentId: !prow.serviceOn ? "off" : (prow.shell.settings.museQuota === true ? "live" : "local")
            onSelected: id => {
                // Live implies on, and off drops the billed call with it, so
                // the two settings can never disagree from in here.
                prow.shell.setSetting("providers", prow.providerId, id !== "off");
                prow.shell.setSetting2("museQuota", id === "live");
                if (id !== "off")
                    prow.expanded = true;
                prow.shell.refresh();
            }
        }

        StyledToggle {
            visible: !prow.tristate
            checked: prow.serviceOn
            onToggled: {
                prow.shell.setSetting("providers", prow.providerId, checked);
                prow.shell.refresh();
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Says, without unfolding the row, that a key was already entered.
        Text {
            visible: prow.keySet && !prow.expanded
            text: prow.shell.i18n("key set")
            font.pixelSize: 9
            color: "#94a3b8"
        }

        Text {
            visible: (prow.serviceOn || prow.providerId === "selfhosted") && (prow.hasDetails || prow.tristate)
            text: prow.expanded ? "▴" : "▾"
            font.pixelSize: 12
            color: "#f8fafc"
            opacity: chevronMouse.containsMouse ? 1.0 : 0.5
            Layout.alignment: Qt.AlignVCenter

            MouseArea {
                id: chevronMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: prow.expanded = !prow.expanded
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.bottomMargin: visible ? 4 : 0
        spacing: 4
        visible: prow.expanded && (prow.serviceOn || prow.providerId === "selfhosted")

        KeyField {
            visible: prow.keySetting !== ""
            shell: prow.shell
            label: prow.shell.i18n("API key")
            placeholder: prow.provider && prow.provider.keyPlaceholder ? prow.provider.keyPlaceholder : ""
            settingKey: prow.keySetting
        }

        RowLayout {
            visible: prow.providerId === "selfhosted"
            Layout.fillWidth: true
            Text {
                text: prow.shell.i18n("Server URL")
                color: "#f8fafc"
                font.pixelSize: 11
            }
            QC.TextField {
                Layout.fillWidth: true
                text: prow.shell.settings.selfhostedEndpoint || ""
                placeholderText: prow.shell.i18n("Server URLs, separated by commas")
                onEditingFinished: {
                    prow.shell.setSetting2("selfhostedEndpoint", text.trim());
                    prow.shell.refresh();
                }
            }
        }
        RowLayout {
            visible: prow.providerId === "selfhosted"
            Layout.fillWidth: true
            Text {
                text: prow.shell.i18n("Engine")
                color: "#f8fafc"
                font.pixelSize: 11
            }
            QC.ComboBox {
                model: ["auto", "ollama", "vllm", "llama.cpp"]
                currentIndex: Math.max(0, model.indexOf(prow.shell.settings.selfhostedEngine || "auto"))
                onActivated: {
                    prow.shell.setSetting2("selfhostedEngine", currentText);
                    prow.shell.refresh();
                }
            }
        }

        // Every other tab reads its quota for free. Muse cannot, so the price
        // of the Live segment is stated next to the control that buys it.
        Text {
            Layout.fillWidth: true
            visible: prow.tristate
            text: prow.shell.settings.museQuota === true ? prow.shell.i18n("Live: plan windows come from a billed model call (~130 tokens per refresh, cached 30 min).") : prow.shell.i18n("Local: read from Muse's own files, free. Meta reports plan windows only on a billed call — that is what Live buys.")
            font.pixelSize: 9
            color: "#94a3b8"
            wrapMode: Text.WordWrap
        }

        KeyField {
            visible: prow.providerId === "copilot"
            shell: prow.shell
            label: prow.shell.i18n("Quota")
            placeholder: prow.shell.i18n("fallback if the plan reports none")
            settingKey: "copilotQuota"
            secret: false
        }
    }
}
