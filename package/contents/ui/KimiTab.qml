import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: kimiTabRoot
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "kimi" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    // Kimi has no account header to sit in, so the chip gets a row of its own.
    RowLayout {
        Layout.fillWidth: true
        visible: kimiStatusChip.visible

        Item {
            Layout.fillWidth: true
        }
        StatusChip {
            id: kimiStatusChip
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.kimi
        }
    }

    // ── Kimi Code plan (the `kimi` CLI login) ────────────────────────────────
    ColumnLayout {
        visible: rootItem.kimiPlanAvailable
        Layout.fillWidth: true
        spacing: 12

        Repeater {
            model: rootItem.kimiPlanWindows
            PopupRow {
                readonly property string countdown: {
                    rootItem.countdownTick;
                    return rootItem.formatCountdown(rootItem.dateFromEpoch(modelData.resetAt));
                }
                label: rootItem.kimiWindowLabel(modelData)
                countdownText: countdown === "resetting..." ? countdown : (countdown ? i18n("in %1", countdown) : "")
                value: modelData.pct
                barColor: rootItem.kimiBlue
                tokenText: i18n("%1 / %2 used", modelData.used, modelData.limit)
                tooltipText: i18n("Kimi Code: %1", rootItem.kimiWindowLabel(modelData)) + "\n" + i18n("Used: %1 / %2", modelData.used, modelData.limit)
            }
        }

        // A used-up plan answers without windows, only "Credits used up".
        PopupRow {
            visible: rootItem.kimiPlanExhausted && rootItem.kimiPlanWindows.length === 0
            label: i18n("Kimi Code plan")
            value: 100
            barColor: rootItem.kimiBlue
            tokenText: rootItem.kimiPlanMessageText()
            tooltipText: i18n("Kimi Code reports the plan quota as used up for this billing cycle")
        }

        RowLayout {
            visible: rootItem.kimiBooster !== null
            Layout.fillWidth: true
            PlasmaComponents.Label {
                text: i18n("Extra usage")
                font.pixelSize: 11
                opacity: 0.65
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                text: rootItem.kimiBooster ? i18n("%1 of %2", rootItem.formatMoney(rootItem.kimiBooster.balance, rootItem.kimiBooster.currency), rootItem.formatMoney(rootItem.kimiBooster.total, rootItem.kimiBooster.currency)) : ""
                font.pixelSize: 12
                font.bold: true
                color: Kirigami.Theme.textColor
            }
        }

        PlasmaComponents.Label {
            text: i18n("Read with the kimi CLI login (~/.kimi-code). Run kimi once when the login expires.")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // The plan failed while the Moonshot balance still answers.
    PlasmaComponents.Label {
        visible: rootItem.kimiPlanError !== "" && rootItem.kimiKeyValid
        text: i18n("Kimi Code: %1", rootItem.kimiPlanError)
        font.pixelSize: 10
        opacity: 0.6
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    ColumnLayout {
        visible: !rootItem.kimiKeyValid && !rootItem.kimiHasKey && !rootItem.kimiPlanAvailable && rootItem.kimiError === ""
        Layout.fillWidth: true
        spacing: 6
        PlasmaComponents.Label {
            text: i18n("Not connected")
            font.pixelSize: 12
            font.bold: true
            opacity: 0.7
            color: Kirigami.Theme.textColor
        }
        PlasmaComponents.Label {
            text: i18n("Sign in to Kimi Code (kimi → /login), or set a Moonshot API key in settings or via $MOONSHOT_API_KEY / $KIMI_API_KEY")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    ColumnLayout {
        visible: rootItem.kimiError !== "" && !rootItem.kimiKeyValid && !rootItem.kimiPlanAvailable
        Layout.fillWidth: true
        spacing: 6
        PlasmaComponents.Label {
            text: i18n("Kimi error")
            font.pixelSize: 12
            font.bold: true
            color: "#ef4444"
        }
        PlasmaComponents.Label {
            text: rootItem.errorText(rootItem.kimiError)
            font.pixelSize: 10
            opacity: 0.7
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    Rectangle {
        visible: rootItem.kimiKeyValid
        Layout.fillWidth: true
        height: balanceColumn.implicitHeight + 24
        radius: 8
        color: Qt.rgba(0.12, 0.23, 0.54, 0.10)
        border.width: 1
        border.color: Qt.rgba(0.12, 0.23, 0.54, 0.28)

        ColumnLayout {
            id: balanceColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            PlasmaComponents.Label {
                text: "Kimi / Moonshot"
                font.pixelSize: 11
                font.bold: true
                color: Kirigami.Theme.textColor
            }

            Repeater {
                model: [
                    {
                        label: i18n("Available balance"),
                        value: rootItem.kimiAvailableBalance,
                        prominent: true
                    },
                    {
                        label: i18n("Voucher balance"),
                        value: rootItem.kimiVoucherBalance,
                        prominent: false
                    },
                    {
                        label: i18n("Cash balance"),
                        value: rootItem.kimiCashBalance,
                        prominent: false
                    }
                ]
                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: modelData.label
                        font.pixelSize: 11
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: rootItem.formatMoney(modelData.value, "USD")
                        font.pixelSize: modelData.prominent ? 16 : 12
                        font.bold: modelData.prominent
                        color: modelData.prominent ? rootItem.kimiBlue : Kirigami.Theme.textColor
                    }
                }
            }
        }
    }
}
