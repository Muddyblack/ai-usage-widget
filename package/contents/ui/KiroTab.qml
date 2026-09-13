import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: kiroTabRoot
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "kiro" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.kiroUsageAvailable

        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.kiroPurple
            isMask: true
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: "Kiro"
            font.pixelSize: 10
            opacity: 0.6
            color: Kirigami.Theme.textColor
            Layout.fillWidth: true
        }
        Rectangle {
            visible: rootItem.kiroPlanType !== ""
            implicitHeight: 18
            implicitWidth: kiroPlanLabel.implicitWidth + 16
            radius: 4
            color: rootItem.kiroPlanType === "free" ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.545, 0.361, 0.965, 0.18)
            border.width: 1
            border.color: rootItem.kiroPlanType === "free" ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.545, 0.361, 0.965, 0.35)

            PlasmaComponents.Label {
                id: kiroPlanLabel
                anchors.centerIn: parent
                text: rootItem.kiroPlanType.toUpperCase()
                font.pixelSize: 9
                font.bold: true
                color: rootItem.kiroPlanType === "free" ? Kirigami.Theme.textColor : rootItem.kiroPurple
            }
        }
    }

    PopupRow {
        visible: rootItem.kiroUsageAvailable
        label: rootItem.kiroDisplayNamePlural !== "" ? rootItem.kiroDisplayNamePlural : i18n("Credits")
        countdownText: rootItem.kiroCountdown === "resetting..." ? i18n("resetting...") : (rootItem.kiroCountdown ? i18n("in %1", rootItem.kiroCountdown) : "")
        value: rootItem.kiroPct
        barColor: rootItem.kiroPurple
        etaText: rootItem.usageHistory.length >= 0 ? rootItem.etaToFull("kr", rootItem.kiroPct) : ""
        deltaText: rootItem.usageHistory.length >= 0 ? rootItem.periodDelta("kr", rootItem.kiroPct, 30 * 24 * 3600000, i18n("last month")) : ""
        tokenText: rootItem.kiroUsageLimit > 0 ? i18n("%1 / %2 used", rootItem.kiroCurrentUsage.toFixed(2), rootItem.kiroUsageLimit.toFixed(0)) : i18n("%1 used", rootItem.kiroCurrentUsage.toFixed(2))
        tooltipText: i18n("Kiro monthly credit usage\nUsed: %1", rootItem.kiroCurrentUsage.toFixed(2) + (rootItem.kiroUsageLimit > 0 ? " / " + rootItem.kiroUsageLimit.toFixed(0) : "")) + (rootItem.kiroResetTime ? "\n" + i18n("Resets: %1", rootItem.kiroResetTime) : "")
    }

    Rectangle {
        visible: rootItem.kiroUsageAvailable
        Layout.fillWidth: true
        height: kiroStatsCol.implicitHeight + 16
        radius: 8
        color: Qt.rgba(0.545, 0.361, 0.965, 0.08)
        border.width: 1
        border.color: Qt.rgba(0.545, 0.361, 0.965, 0.22)

        ColumnLayout {
            id: kiroStatsCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                PlasmaComponents.Label {
                    text: i18n("Current Usage")
                    font.pixelSize: 11
                    opacity: 0.65
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: rootItem.kiroCurrentUsage.toFixed(2) + " " + (rootItem.kiroDisplayNamePlural || i18n("credits")).toLowerCase()
                    font.bold: true
                    font.pixelSize: 13
                    color: rootItem.kiroPurple
                }
            }

            RowLayout {
                visible: rootItem.kiroUsageLimit > 0
                Layout.fillWidth: true
                spacing: 8
                PlasmaComponents.Label {
                    text: i18n("Remaining")
                    font.pixelSize: 11
                    opacity: 0.65
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: rootItem.kiroRemaining.toFixed(2)
                    font.bold: true
                    font.pixelSize: 12
                    color: rootItem.usageColor(rootItem.kiroPct)
                }
            }

            RowLayout {
                visible: rootItem.kiroCurrentOverages > 0 || rootItem.kiroOverageCharges > 0
                Layout.fillWidth: true
                spacing: 8
                PlasmaComponents.Label {
                    text: i18n("Overage")
                    font.pixelSize: 11
                    opacity: 0.65
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: rootItem.kiroCurrencySymbol + rootItem.kiroOverageCharges.toFixed(2) + " (" + rootItem.kiroCurrentOverages.toFixed(2) + ")"
                    font.bold: true
                    font.pixelSize: 12
                    color: rootItem.warningColor
                }
            }

            RowLayout {
                visible: rootItem.kiroOverageRate > 0
                Layout.fillWidth: true
                spacing: 8
                PlasmaComponents.Label {
                    text: i18n("Overage Rate")
                    font.pixelSize: 11
                    opacity: 0.65
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: rootItem.kiroCurrencySymbol + rootItem.kiroOverageRate.toFixed(2) + "/" + (rootItem.kiroDisplayName || i18n("credit")).toLowerCase()
                    font.bold: true
                    font.pixelSize: 12
                    color: Kirigami.Theme.textColor
                    opacity: 0.85
                }
            }
        }
    }

    PlasmaComponents.Label {
        visible: rootItem.kiroUsageAvailable
        text: rootItem.kiroSource === "cli" ? i18n("Read live with the kiro-cli login. No API key required.") : i18n("Read locally from Kiro app state. No API key or network request required.")
        font.pixelSize: 9
        opacity: 0.45
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    ColumnLayout {
        visible: !rootItem.kiroUsageAvailable
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents.Label {
            text: i18n("No Kiro usage data found")
            font.pixelSize: 12
            font.bold: true
            color: Kirigami.Theme.textColor
            opacity: 0.7
        }

        PlasmaComponents.Label {
            text: i18n("Sign in to kiro-cli (kiro-cli login), or open the Kiro IDE and sign in once so the widget can read its usage snapshot. A kiro-cli login expires about an hour after the CLI last ran — start kiro-cli to renew it.")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
