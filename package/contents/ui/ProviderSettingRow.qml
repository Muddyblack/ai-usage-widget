import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One provider's settings, whole: the on/off control plus — folded away until
// asked for — its API key and any provider-specific extra. A key belongs to
// exactly one provider, so it lives under that provider rather than in a
// separate list where it has to be matched back up by name.
ColumnLayout {
    id: prow

    // A row from rootItem.providers: { id, label, color, icon, keyConfig? }.
    property var provider: null
    property Item rootItem: null

    readonly property string providerId: provider ? provider.id : ""
    readonly property string keyConfig: provider && provider.keyConfig ? provider.keyConfig : ""
    readonly property bool serviceOn: Plasmoid.configuration[providerId + "Enabled"] === true
    // Muse is the one provider whose plan quota cannot be read for free, so
    // "on" is not one state but two: local-only, and local + the billed live
    // quota. A switch cannot say that; three segments can.
    readonly property bool tristate: providerId === "muse"
    readonly property bool hasDetails: keyConfig !== "" || providerId === "copilot"
    readonly property bool keySet: keyConfig !== "" && String(Plasmoid.configuration[keyConfig] || "") !== ""

    property bool expanded: false

    Layout.fillWidth: true
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            color: prow.provider ? prow.provider.color : "transparent"
            opacity: prow.serviceOn ? 1 : 0.35
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents.Label {
            text: prow.provider ? prow.provider.label : ""
            font.pixelSize: 11
            color: Kirigami.Theme.textColor
            opacity: prow.serviceOn ? 1 : 0.6
            Layout.preferredWidth: 82
            elide: Text.ElideRight
        }

        // Off / Local / Live — the same segmented control the provider tabs
        // use for Usage/Stats, so it reads as a picker rather than a toggle.
        SubTabBar {
            visible: prow.tristate
            Layout.fillWidth: false
            Layout.preferredWidth: 168
            accent: prow.provider ? prow.provider.color : Kirigami.Theme.highlightColor
            tabs: [
                {
                    id: "off",
                    label: i18n("Off")
                },
                {
                    id: "local",
                    label: i18n("Local")
                },
                {
                    id: "live",
                    label: i18n("Live")
                }
            ]
            currentId: !prow.serviceOn ? "off" : (Plasmoid.configuration.museQuotaEnabled === true ? "live" : "local")
            onSelected: id => {
                // Live implies on, and off drops the billed call with it, so
                // the two config keys can never disagree from in here.
                Plasmoid.configuration.museEnabled = id !== "off";
                Plasmoid.configuration.museQuotaEnabled = id === "live";
                if (id !== "off")
                    prow.expanded = true;
            }
        }

        QQC2.Switch {
            visible: !prow.tristate
            implicitHeight: 20
            checked: prow.serviceOn
            onToggled: Plasmoid.configuration[prow.providerId + "Enabled"] = checked
        }

        Item {
            Layout.fillWidth: true
        }

        // Says, without unfolding the row, that a key was already entered.
        PlasmaComponents.Label {
            visible: prow.keySet && !prow.expanded
            text: i18n("key set")
            font.pixelSize: 9
            opacity: 0.4
            color: Kirigami.Theme.textColor
        }

        QQC2.ToolButton {
            visible: prow.serviceOn && (prow.hasDetails || prow.tristate)
            implicitWidth: 22
            implicitHeight: 22
            icon.name: prow.expanded ? "go-up" : "go-down"
            display: QQC2.AbstractButton.IconOnly
            opacity: prow.expanded ? 1 : 0.5
            onClicked: prow.expanded = !prow.expanded
            QQC2.ToolTip.delay: 400
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: prow.expanded ? i18n("Hide options") : i18n("Key and options")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.bottomMargin: visible ? 4 : 0
        spacing: 3
        visible: prow.expanded && prow.serviceOn

        KeyRow {
            label: i18n("API key")
            placeholder: prow.provider && prow.provider.keyPlaceholder ? prow.provider.keyPlaceholder : ""
            configKey: prow.keyConfig
            rowVisible: prow.keyConfig !== ""
        }

        // Every other tab reads its quota for free. Muse cannot, so the price
        // of the Live segment is stated next to the control that buys it.
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: prow.tristate
            text: Plasmoid.configuration.museQuotaEnabled === true ? i18n("Live: plan windows come from a billed model call (~130 tokens per refresh, cached 30 min).") : i18n("Local: read from Muse's own files, free. Meta reports plan windows only on a billed call — that is what Live buys.")
            font.pixelSize: 9
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: prow.providerId === "copilot"

            PlasmaComponents.Label {
                text: i18n("Quota")
                font.pixelSize: 10
                opacity: 0.6
                color: Kirigami.Theme.textColor
                Layout.preferredWidth: 76
                elide: Text.ElideRight
            }
            QQC2.TextField {
                text: Plasmoid.configuration.copilotQuota !== undefined && Plasmoid.configuration.copilotQuota !== null ? Plasmoid.configuration.copilotQuota.toString() : "300"
                placeholderText: "300"
                implicitHeight: 26
                Layout.preferredWidth: 64
                font.pixelSize: 10
                validator: RegularExpressionValidator {
                    regularExpression: /^[0-9]*$/
                }
                onEditingFinished: {
                    var val = parseInt(text);
                    if (isNaN(val))
                        val = 300;
                    Plasmoid.configuration.copilotQuota = val;
                    text = val.toString();
                }
            }
            PlasmaComponents.Label {
                text: i18n("fallback if the plan reports none")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
}
