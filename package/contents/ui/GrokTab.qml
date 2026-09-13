import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "grok" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.grokWhite
            isMask: true
        }
        PlasmaComponents.Label {
            text: rootItem.grokTeamName || rootItem.grokEmail || "Grok CLI"
            font.pixelSize: 10
            opacity: 0.65
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        PlasmaComponents.Label {
            text: rootItem.grokTierId
            visible: text !== ""
            font.pixelSize: 9
            font.bold: true
            opacity: 0.7
        }
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.grok
        }
    }

    ColumnLayout {
        visible: !rootItem.grokLoggedIn && !rootItem.grokHasKey
        Layout.fillWidth: true
        spacing: 6
        PlasmaComponents.Label {
            text: i18n("Not connected")
            font.bold: true
        }
        PlasmaComponents.Label {
            text: i18n("Run grok --oauth, or add an xAI API key in settings.")
            font.pixelSize: 10
            opacity: 0.55
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    PopupRow {
        visible: rootItem.grokHasBilling
        label: i18n("Credit usage")
        value: rootItem.grokPct
        barColor: rootItem.grokWhite
        resetText: rootItem.grokQuotaKind === "free-tier" ? rootItem.grokQuotaWindowText() : (rootItem.grokBillingPeriodEnd ? i18n("resets %1", rootItem.grokBillingPeriodEnd) : "")
        tokenText: rootItem.grokMonthlyLimit > 0 ? rootItem.grokUsed.toFixed(2) + " / " + rootItem.grokMonthlyLimit.toFixed(2) : ""
        tooltipText: i18n("Grok CLI billing credits")
    }

    PlasmaComponents.Label {
        visible: (rootItem.grokLoggedIn || rootItem.grokHasKey) && !rootItem.grokHasBilling
        text: i18n("Billing quota is not exposed for this Grok account.")
        font.pixelSize: 10
        opacity: 0.55
        Layout.fillWidth: true
    }

    PlasmaComponents.Label {
        visible: rootItem.grokSessionCount > 0
        text: i18np("1 local session", "%1 local sessions", rootItem.grokSessionCount) + " · " + i18n("%1 tokens", rootItem.formatTokens(rootItem.grokTotalTokens)) + " · " + i18np("%1 tool call", "%1 tool calls", rootItem.grokTotalToolCalls)
        font.pixelSize: 10
        opacity: 0.55
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
