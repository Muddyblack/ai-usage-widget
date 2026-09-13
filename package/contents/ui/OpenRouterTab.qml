import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: openRouterTabRoot
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "openrouter" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    // Beta / Untested warning banner
    Rectangle {
        Layout.fillWidth: true
        height: orBetaCol.implicitHeight + 16
        radius: 8
        color: Qt.rgba(0.93, 0.45, 0.1, 0.08)
        border.width: 1
        border.color: Qt.rgba(0.93, 0.45, 0.1, 0.20)

        RowLayout {
            id: orBetaCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Kirigami.Icon {
                source: "dialog-warning"
                width: 16
                height: 16
                color: "#f97316"
                isMask: true
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents.Label {
                text: i18n("OpenRouter support is in BETA and currently untested.")
                font.pixelSize: 10
                font.bold: true
                color: "#f97316"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    // Account row
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.openrouterKeyValid

        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.openrouterPurple
            isMask: true
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: rootItem.openrouterLabel || "OpenRouter"
            font.pixelSize: 10
            opacity: 0.6
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Rectangle {
            height: 18
            width: orPlanLabel.implicitWidth + 12
            radius: 4
            color: rootItem.openrouterIsFreeTier ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.576, 0.2, 0.918, 0.18)
            border.width: 1
            border.color: rootItem.openrouterIsFreeTier ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.576, 0.2, 0.918, 0.35)
            PlasmaComponents.Label {
                id: orPlanLabel
                anchors.centerIn: parent
                text: rootItem.openrouterIsFreeTier ? i18n("FREE") : i18n("PAID")
                font.pixelSize: 9
                font.bold: true
                color: rootItem.openrouterIsFreeTier ? Kirigami.Theme.textColor : rootItem.openrouterPurple
            }
        }
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.openrouter
        }
    }

    // No key message
    ColumnLayout {
        visible: !rootItem.openrouterKeyValid && !rootItem.openrouterHasKey
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
            text: i18n("Set an OpenRouter API key in ⚙ settings or via\n$OPENROUTER_API_KEY / ~/.config/openrouter/api-key")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // Usage stats
    ColumnLayout {
        visible: rootItem.openrouterKeyValid
        Layout.fillWidth: true
        spacing: 8

        // Usage bar (only when limit is set)
        PopupRow {
            visible: rootItem.openrouterLimitUSD !== null && rootItem.openrouterLimitUSD > 0
            label: i18n("Credit Usage")
            value: rootItem.openrouterLimitUSD !== null && rootItem.openrouterLimitUSD > 0 ? Math.min(100, (rootItem.openrouterUsageUSD / rootItem.openrouterLimitUSD) * 100) : 0
            barColor: rootItem.openrouterPurple
            etaText: rootItem.usageHistory.length >= 0 ? rootItem.etaToFull("or", value) : ""
            deltaText: rootItem.usageHistory.length >= 0 ? rootItem.periodDelta("or", value, 30 * 24 * 3600000, i18n("last month")) : ""
            tokenText: i18n("%1 used", "$" + rootItem.openrouterUsageUSD.toFixed(4) + " / $" + (rootItem.openrouterLimitUSD !== null ? rootItem.openrouterLimitUSD.toFixed(2) : "∞"))
            tooltipText: i18n("OpenRouter credit spend\n$%1 of $%2 limit", rootItem.openrouterUsageUSD.toFixed(4), rootItem.openrouterLimitUSD !== null ? rootItem.openrouterLimitUSD.toFixed(2) : i18n("unlimited"))
        }

        // Usage summary card
        Rectangle {
            Layout.fillWidth: true
            height: orStatsCol.implicitHeight + 16
            radius: 8
            color: Qt.rgba(0.576, 0.2, 0.918, 0.08)
            border.width: 1
            border.color: Qt.rgba(0.576, 0.2, 0.918, 0.22)

            ColumnLayout {
                id: orStatsCol
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
                        text: i18n("All-time Spend")
                        font.pixelSize: 11
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: "$" + rootItem.openrouterUsageUSD.toFixed(4)
                        font.bold: true
                        font.pixelSize: 14
                        color: rootItem.openrouterPurple
                    }
                }

                // Credit limit row
                RowLayout {
                    visible: rootItem.openrouterLimitUSD !== null
                    Layout.fillWidth: true
                    spacing: 8
                    PlasmaComponents.Label {
                        text: i18n("Credit Limit")
                        font.pixelSize: 11
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: rootItem.openrouterLimitUSD !== null ? "$" + rootItem.openrouterLimitUSD.toFixed(2) : "∞"
                        font.bold: true
                        font.pixelSize: 12
                        color: Kirigami.Theme.textColor
                        opacity: 0.85
                    }
                }

                // Remaining row
                RowLayout {
                    visible: rootItem.openrouterLimitRemainingUSD !== null
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
                        text: rootItem.openrouterLimitRemainingUSD !== null ? "$" + rootItem.openrouterLimitRemainingUSD.toFixed(4) : "—"
                        font.bold: true
                        font.pixelSize: 12
                        color: {
                            if (rootItem.openrouterLimitRemainingUSD === null)
                                return Kirigami.Theme.textColor;
                            var pct = rootItem.openrouterLimitUSD > 0 ? ((rootItem.openrouterLimitUSD - rootItem.openrouterLimitRemainingUSD) / rootItem.openrouterLimitUSD) * 100 : 0;
                            return rootItem.usageColor(pct);
                        }
                    }
                }

                // Rate limit info
                RowLayout {
                    visible: rootItem.openrouterRateLimit && rootItem.openrouterRateLimit.requests !== undefined
                    Layout.fillWidth: true
                    spacing: 8
                    PlasmaComponents.Label {
                        text: i18n("Rate Limit")
                        font.pixelSize: 11
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: rootItem.openrouterRateLimit.requests !== undefined ? i18n("%1 req / %2", rootItem.openrouterRateLimit.requests, rootItem.openrouterRateLimit.interval || i18n("min")) : ""
                        font.pixelSize: 10
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                    }
                }
            }
        }

        // Free tier note
        Rectangle {
            visible: rootItem.openrouterIsFreeTier
            Layout.fillWidth: true
            height: orFreeCol.implicitHeight + 12
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)
            ColumnLayout {
                id: orFreeCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                spacing: 3
                PlasmaComponents.Label {
                    text: i18n("Free tier active — rate limits apply")
                    font.pixelSize: 10
                    opacity: 0.5
                    color: Kirigami.Theme.textColor
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}
