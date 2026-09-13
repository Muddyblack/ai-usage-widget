import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: cursorTabRoot
    property Item rootItem

    // Inner sub-tab: "usage" (plan meters) vs "stats" (the dashboard's usage
    // for the billing cycle), same split as the Claude and Muse tabs.
    property string subTab: "usage"
    readonly property var stats: rootItem.cursorStats || ({})
    readonly property bool statsAvailable: stats.available === true

    visible: rootItem.enabledTabs[rootItem.activeTab] === "cursor" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.cursorAvailable

        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.cursorWhite
            isMask: true
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: "Cursor"
            font.pixelSize: 10
            opacity: 0.6
            color: Kirigami.Theme.textColor
            Layout.fillWidth: true
        }
        Rectangle {
            visible: rootItem.cursorPlanName !== ""
            implicitHeight: 18
            implicitWidth: cursorPlanLabel.implicitWidth + 16
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            PlasmaComponents.Label {
                id: cursorPlanLabel
                anchors.centerIn: parent
                text: rootItem.cursorPlanName.toUpperCase()
                font.pixelSize: 9
                font.bold: true
                color: rootItem.cursorWhite
            }
        }
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.cursor
        }
    }

    SubTabBar {
        visible: rootItem.cursorAvailable
        accent: rootItem.cursorWhite
        currentId: cursorTabRoot.subTab
        onSelected: id => cursorTabRoot.subTab = id
    }

    // ── Usage ──────────────────────────────────────────────────────────────────
    ColumnLayout {
        visible: rootItem.cursorAvailable && cursorTabRoot.subTab === "usage"
        Layout.fillWidth: true
        spacing: 14

        PopupRow {
            label: i18n("Included usage")
            countdownText: rootItem.cursorCountdown === "resetting..." ? i18n("resetting...") : (rootItem.cursorCountdown ? i18n("in %1", rootItem.cursorCountdown) : "")
            value: rootItem.cursorTotalPct
            barColor: rootItem.cursorWhite
            etaText: rootItem.usageHistory.length >= 0 ? rootItem.etaToFull("cu", rootItem.cursorTotalPct) : ""
            deltaText: rootItem.usageHistory.length >= 0 ? rootItem.periodDelta("cu", rootItem.cursorTotalPct, 30 * 24 * 3600000, i18n("last month")) : ""
            tokenText: rootItem.cursorLimit > 0 ? i18n("%1 / %2 used", rootItem.formatMoney(rootItem.cursorIncludedSpend, "USD"), rootItem.formatMoney(rootItem.cursorLimit, "USD")) : i18n("%1% of included usage", Math.round(rootItem.cursorTotalPct))
            tooltipText: i18n("Cursor included usage this billing cycle") + (rootItem.cursorResetTime ? "\n" + i18n("Resets: %1", rootItem.cursorResetTime) : "")
        }

        // Cursor meters Auto/Composer and hand-picked API models separately.
        PopupRow {
            visible: rootItem.cursorHasSplit
            label: i18n("Auto + Composer")
            value: rootItem.cursorAutoPct
            barColor: rootItem.cursorWhite
            tooltipText: i18n("Share of the included usage spent by Auto and Composer")
        }

        PopupRow {
            visible: rootItem.cursorHasSplit
            label: i18n("API models")
            value: rootItem.cursorApiPct
            barColor: rootItem.cursorWhite
            tooltipText: i18n("Share of the included usage spent on models picked by name")
        }

        Rectangle {
            visible: rootItem.cursorOnDemandLimit > 0 || rootItem.cursorOnDemandUsed > 0 || rootItem.cursorResetTime !== ""
            Layout.fillWidth: true
            height: cursorStatsCol.implicitHeight + 16
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            ColumnLayout {
                id: cursorStatsCol
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 8

                RowLayout {
                    visible: rootItem.cursorOnDemandLimit > 0 || rootItem.cursorOnDemandUsed > 0
                    Layout.fillWidth: true
                    spacing: 8
                    PlasmaComponents.Label {
                        text: i18n("On-demand")
                        font.pixelSize: 11
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: rootItem.formatMoney(rootItem.cursorOnDemandUsed, "USD") + (rootItem.cursorOnDemandLimit > 0 ? " / " + rootItem.formatMoney(rootItem.cursorOnDemandLimit, "USD") : "")
                        font.bold: true
                        font.pixelSize: 12
                        color: rootItem.cursorOnDemandUsed > 0 ? rootItem.warningColor : Kirigami.Theme.textColor
                    }
                }

                RowLayout {
                    visible: rootItem.cursorResetTime !== ""
                    Layout.fillWidth: true
                    spacing: 8
                    PlasmaComponents.Label {
                        text: i18n("Billing cycle ends")
                        font.pixelSize: 11
                        opacity: 0.65
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: rootItem.cursorResetTime
                        font.bold: true
                        font.pixelSize: 12
                        color: Kirigami.Theme.textColor
                        opacity: 0.85
                    }
                }
            }
        }

        PlasmaComponents.Label {
            text: rootItem.cursorSource === "ide" ? i18n("Read with the Cursor IDE login. No API key required.") : i18n("Read with the cursor-agent login (~/.config/cursor/auth.json). No API key required.")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    // ── Stats: the dashboard's usage for this billing cycle ────────────────────
    PlasmaComponents.Label {
        visible: rootItem.cursorAvailable && cursorTabRoot.subTab === "stats" && !cursorTabRoot.statsAvailable
        Layout.fillWidth: true
        Layout.topMargin: 8
        horizontalAlignment: Text.AlignHCenter
        text: i18n("No Cursor usage this billing cycle yet.\nRequests made with Cursor or cursor-agent will appear here.")
        font.pixelSize: 10
        opacity: 0.5
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        visible: rootItem.cursorAvailable && cursorTabRoot.subTab === "stats" && cursorTabRoot.statsAvailable
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PlasmaComponents.Label {
                text: i18n("Activity Stats")
                font.bold: true
                font.pixelSize: 11
                opacity: 0.7
                color: Kirigami.Theme.textColor
            }
            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                text: i18n("this billing cycle")
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 6
            columnSpacing: 6

            StatTile {
                visible: (cursorTabRoot.stats.totalTokens || 0) > 0
                tileValue: rootItem.formatTokens(cursorTabRoot.stats.totalTokens || 0)
                tileLabel: i18nc("stat label", "tokens")
                tileTip: i18n("%1 output", rootItem.formatTokens(cursorTabRoot.stats.totalOutputTokens || 0)) + " · " + i18n("%1 input", rootItem.formatTokens(cursorTabRoot.stats.totalInputTokens || 0)) + " · " + i18n("%1 cache read", rootItem.formatTokens(cursorTabRoot.stats.totalCachedTokens || 0))
            }
            StatTile {
                visible: (cursorTabRoot.stats.totalCostUSD || 0) > 0
                tileValue: rootItem.formatMoney(cursorTabRoot.stats.totalCostUSD || 0, "USD")
                tileLabel: i18n("usage value")
                tileTip: i18n("What Cursor prices this cycle's requests at — covered by the plan up to its included amount")
            }
            StatTile {
                tileValue: Math.round(cursorTabRoot.stats.totalRequests || 0).toString()
                tileLabel: i18nc("stat label", "requests")
                tileTip: cursorTabRoot.stats.partial ? i18n("Per-day figures cover the newest requests only") : ""
            }
            StatTile {
                tileValue: Math.round(cursorTabRoot.stats.totalSessions || 0).toString()
                tileLabel: i18nc("stat label", "conversations")
            }
            StatTile {
                tileValue: Math.round(cursorTabRoot.stats.activeDays || 0) + ((cursorTabRoot.stats.spanDays || 0) > 0 ? "/" + Math.round(cursorTabRoot.stats.spanDays) : "")
                tileLabel: i18n("active days")
                tileTip: cursorTabRoot.stats.firstDate ? i18n("Since %1", Qt.formatDate(new Date(cursorTabRoot.stats.firstDate), "MMM d, yyyy")) : ""
            }
            StatTile {
                visible: cursorTabRoot.stats.peakHour !== undefined && cursorTabRoot.stats.peakHour >= 0
                tileValue: cursorTabRoot.stats.peakHour >= 0 ? (cursorTabRoot.stats.peakHour < 10 ? "0" : "") + cursorTabRoot.stats.peakHour + ":00" : "—"
                tileLabel: i18n("peak hour")
                tileTip: i18n("Hour of day with the most requests")
            }
            StatTile {
                visible: (cursorTabRoot.stats.longestSessionMs || 0) > 0
                tileValue: rootItem.formatDuration(cursorTabRoot.stats.longestSessionMs || 0)
                tileLabel: i18n("longest chat")
                tileSub: (cursorTabRoot.stats.longestSessionMessages || 0) > 0 ? i18np("%1 req", "%1 reqs", Math.round(cursorTabRoot.stats.longestSessionMessages)) : ""
            }
        }

        StatsSparkline {
            series: cursorTabRoot.stats.dailySeries || []
            unit: cursorTabRoot.stats.dailyUnit || i18n("tokens")
            barColor: rootItem.cursorWhite
            formatValue: rootItem.formatTokens
        }

        // ── Per-model usage (this billing cycle) ───────────────────────────
        Repeater {
            model: {
                var m = cursorTabRoot.stats.models || ({});
                var keys = Object.keys(m);
                keys.sort(function (a, b) {
                    return (m[b].total || 0) - (m[a].total || 0);
                });
                return keys;
            }
            RowLayout {
                required property string modelData
                readonly property var entry: (cursorTabRoot.stats.models || ({}))[modelData] || ({})

                Layout.fillWidth: true
                spacing: 8

                PlasmaComponents.Label {
                    text: rootItem.shortenModelName(parent.modelData)
                    font.pixelSize: 10
                    opacity: 0.75
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: i18n("%1 tok", rootItem.formatTokens(parent.entry.total || 0))
                    font.pixelSize: 10
                    opacity: 0.6
                    color: Kirigami.Theme.textColor
                }
                PlasmaComponents.Label {
                    visible: (parent.entry.cost || 0) > 0
                    text: rootItem.formatMoney(parent.entry.cost || 0, "USD")
                    font.pixelSize: 10
                    color: rootItem.cursorWhite
                }
            }
        }

        PlasmaComponents.Label {
            text: i18n("Cursor dashboard ↗")
            font.pixelSize: 9
            font.underline: dashboardMouse.containsMouse
            opacity: dashboardMouse.containsMouse ? 0.9 : 0.5
            color: Kirigami.Theme.textColor
            Layout.alignment: Qt.AlignRight

            MouseArea {
                id: dashboardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("https://cursor.com/dashboard?tab=usage")
            }
        }
    }

    ColumnLayout {
        visible: !rootItem.cursorAvailable
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents.Label {
            text: rootItem.cursorLoggedIn ? i18n("Cursor error") : i18n("Not signed in")
            font.pixelSize: 12
            font.bold: true
            color: rootItem.cursorLoggedIn ? "#ef4444" : Kirigami.Theme.textColor
            opacity: rootItem.cursorLoggedIn ? 1 : 0.7
        }

        PlasmaComponents.Label {
            text: rootItem.cursorLoggedIn ? rootItem.cursorError : i18n("Run cursor-agent login (or sign in to the Cursor IDE). No API key needed.")
            font.pixelSize: 10
            opacity: 0.6
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    component StatTile: StatTileBase {
        accentColor: rootItem.cursorWhite
    }
}
