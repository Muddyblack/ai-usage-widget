import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: ollamaTab
    property Item rootItem
    visible: rootItem.enabledTabs[rootItem.activeTab] === "ollama" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 12

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: i18n("Ollama Cloud usage")
        font.pixelSize: 14
        font.bold: true
        color: Kirigami.Theme.textColor
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: rootItem.ollamaError !== ""
        text: rootItem.errorText(rootItem.ollamaError)
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.negativeTextColor
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: rootItem.ollamaWindows.length === 0 && rootItem.ollamaError === ""
        text: i18n("Checking usage… Enable this provider and sign in to Ollama Cloud in OpenCode, set $OLLAMA_API_KEY, or enter a key in Settings.")
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.textColor
        opacity: 0.7
    }

    Repeater {
        model: rootItem.ollamaWindows
        ColumnLayout {
            id: bucketRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 3
            PopupRow {
                label: bucketRow.modelData.label
                value: bucketRow.modelData.pct
                barColor: "#f0f0f0"
                tokenText: bucketRow.modelData.detail
                tooltipText: i18n("Ollama does not provide a reset time in this response.")
            }
            Repeater {
                model: ollamaTab.rootItem.ollamaModels[bucketRow.modelData.key.replace("ollama_", "")] || []
                PlasmaComponents.Label {
                    required property var modelData
                    Layout.fillWidth: true
                    text: i18n("%1: %2 requests", modelData.name, modelData.requestCount)
                    font.pixelSize: 10
                    opacity: 0.55
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                }
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: rootItem.ollamaActivityCost !== ""
        text: i18n("Recent activity cost: $%1", rootItem.ollamaActivityCost)
        font.pixelSize: 11
        color: Kirigami.Theme.textColor
        opacity: 0.7
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: i18n("Usage comes from an undocumented Ollama Cloud endpoint; its fields may change.")
        font.pixelSize: 10
        color: Kirigami.Theme.textColor
        opacity: 0.5
        wrapMode: Text.WordWrap
    }
}
