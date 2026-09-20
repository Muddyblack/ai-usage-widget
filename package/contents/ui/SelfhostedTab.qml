import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: tab
    property Item rootItem
    readonly property var provider: rootItem.selfhostedProvider || ({})
    readonly property var details: provider.details || ({})
    readonly property var servers: details.servers || (details.engine ? [details] : [])
    visible: rootItem.enabledTabs[rootItem.activeTab] === "selfhosted" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 10

    PlasmaComponents.Label {
        text: i18n("Local Models")
        font.bold: true
        font.pixelSize: 14
        color: Kirigami.Theme.textColor
    }
    PlasmaComponents.Label {
        visible: !!tab.provider.error
        text: tab.provider.error || ""
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: tab.servers
        ColumnLayout {
            id: serverRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 5
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: serverRow.modelData.url || serverRow.modelData.engine || ""
                font.bold: true
                elide: Text.ElideMiddle
                color: Kirigami.Theme.textColor
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: serverRow.modelData.error || ((serverRow.modelData.engine || "") + (serverRow.modelData.version ? " " + serverRow.modelData.version : "") + " · " + (serverRow.modelData.state || ""))
                color: serverRow.modelData.error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }
            PlasmaComponents.Label {
                visible: !!serverRow.modelData.gpu && !!serverRow.modelData.gpu.name
                text: serverRow.modelData.gpu ? serverRow.modelData.gpu.name + " · " + serverRow.modelData.gpu.utilization + "% GPU · " + serverRow.modelData.gpu.temperature + "°C" : ""
                color: Kirigami.Theme.textColor
            }
            Repeater {
                model: serverRow.modelData.quotaWindows || (tab.servers.length === 1 ? tab.provider.quotaWindows || [] : [])
                PopupRow {
                    required property var modelData
                    label: modelData.label
                    value: modelData.pct
                    tokenText: modelData.detail
                    barColor: "#38bdf8"
                }
            }
            Repeater {
                model: serverRow.modelData.models || []
                PlasmaComponents.Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name + (modelData.quant ? " · " + modelData.quant : "") + (modelData.sizeVram ? " · " + (modelData.sizeVram / 1073741824).toFixed(1) + " GB" : "")
                    elide: Text.ElideRight
                    color: Kirigami.Theme.textColor
                }
            }
            PlasmaComponents.Label {
                visible: (serverRow.modelData.promptTokens || 0) + (serverRow.modelData.generationTokens || 0) > 0
                text: i18n("Since server start: %1 prompt · %2 generated tokens", serverRow.modelData.promptTokens || 0, serverRow.modelData.generationTokens || 0)
                color: Kirigami.Theme.textColor
            }
            PlasmaComponents.Label {
                visible: serverRow.modelData.tokensPerSec !== undefined && serverRow.modelData.tokensPerSec !== null
                text: i18n("Generation: %1 tokens/s", Number(serverRow.modelData.tokensPerSec).toFixed(1))
                color: Kirigami.Theme.textColor
            }
            Repeater {
                model: serverRow.modelData.runtimeSlots || []
                PlasmaComponents.Label {
                    required property var modelData
                    text: i18n("Slot %1: %2 · %3 / %4 context tokens", modelData.id, modelData.state, modelData.used, modelData.limit)
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }
}
