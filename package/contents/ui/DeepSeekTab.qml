import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: deepSeekTabRoot
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "deepseek" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    function money(value, currency) {
        return rootItem.formatMoney(value, currency);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.deepseekKeyValid

        Kirigami.Icon {
            source: "wallet-open"
            width: 14
            height: 14
            color: rootItem.deepseekBlue
            isMask: true
            opacity: 0.75
        }

        PlasmaComponents.Label {
            text: "DeepSeek"
            font.pixelSize: 10
            opacity: 0.65
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Rectangle {
            height: 18
            width: deepSeekBadgeLabel.implicitWidth + 12
            radius: 4
            color: rootItem.deepseekIsAvailable ? Qt.rgba(0.31, 0.55, 1.0, 0.18) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: rootItem.deepseekIsAvailable ? Qt.rgba(0.31, 0.55, 1.0, 0.35) : Qt.rgba(1, 1, 1, 0.12)
            PlasmaComponents.Label {
                id: deepSeekBadgeLabel
                anchors.centerIn: parent
                text: rootItem.deepseekIsAvailable ? i18n("AVAILABLE") : i18n("LOW BALANCE")
                font.pixelSize: 9
                font.bold: true
                color: rootItem.deepseekIsAvailable ? rootItem.deepseekBlue : Kirigami.Theme.textColor
            }
        }

        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.deepseek
        }
    }

    ColumnLayout {
        visible: !rootItem.deepseekKeyValid && !rootItem.deepseekHasKey && rootItem.deepseekError === ""
        Layout.fillWidth: true
        spacing: 6
        PlasmaComponents.Label {
            text: i18n("Not connected")
            font.pixelSize: 12
            font.bold: true
            color: Kirigami.Theme.textColor
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: i18n("Set a DeepSeek API key in settings or via\n$DEEPSEEK_API_KEY / ~/.config/deepseek/api-key")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    ColumnLayout {
        visible: rootItem.deepseekError !== "" && !rootItem.deepseekKeyValid
        Layout.fillWidth: true
        spacing: 6
        PlasmaComponents.Label {
            text: i18n("DeepSeek error")
            font.pixelSize: 12
            font.bold: true
            color: "#ef4444"
        }
        PlasmaComponents.Label {
            text: rootItem.errorText(rootItem.deepseekError)
            font.pixelSize: 10
            opacity: 0.7
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    ColumnLayout {
        visible: rootItem.deepseekKeyValid
        Layout.fillWidth: true
        spacing: 8

        StatValueCard {
            accent: rootItem.deepseekBlue
            rows: [
                {
                    label: i18n("Total Balance"),
                    value: deepSeekTabRoot.money(rootItem.deepseekPrimaryTotal, rootItem.deepseekPrimaryCurrency),
                    strong: true
                },
                {
                    label: i18n("Granted"),
                    value: deepSeekTabRoot.money(rootItem.deepseekPrimaryGranted, rootItem.deepseekPrimaryCurrency)
                },
                {
                    label: i18n("Topped Up"),
                    value: deepSeekTabRoot.money(rootItem.deepseekPrimaryToppedUp, rootItem.deepseekPrimaryCurrency)
                }
            ]
        }

        Rectangle {
            visible: rootItem.deepseekBalances.length > 1
            Layout.fillWidth: true
            height: deepSeekBalancesCol.implicitHeight + 16
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            ColumnLayout {
                id: deepSeekBalancesCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                PlasmaComponents.Label {
                    text: i18n("Currencies")
                    font.pixelSize: 11
                    font.bold: true
                    opacity: 0.75
                    color: Kirigami.Theme.textColor
                }

                Repeater {
                    model: rootItem.deepseekBalances
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        PlasmaComponents.Label {
                            text: modelData.currency || i18n("unknown")
                            font.pixelSize: 10
                            color: Kirigami.Theme.textColor
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            text: deepSeekTabRoot.money(Number(modelData.total_balance || 0), modelData.currency || "")
                            font.pixelSize: 10
                            font.bold: true
                            color: rootItem.deepseekBlue
                        }
                    }
                }
            }
        }
    }
}
