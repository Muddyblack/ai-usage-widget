import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: copilotTabRoot
    property Item rootItem

    // Inner sub-tab: "usage" (premium-request quota) vs "stats" (local Copilot
    // CLI activity), same split as the Claude and OpenAI tabs.
    property string subTab: "usage"

    visible: rootItem.enabledTabs[rootItem.activeTab] === "copilot" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    readonly property real remaining: Math.max(0, rootItem.copilotQuota - rootItem.copilotUsed)

    function fmtRequests(value) {
        return value.toFixed(value % 1 === 0 ? 0 : 1);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.copilotKeyValid

        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.copilotPurple
            isMask: true
            opacity: 0.75
        }

        PlasmaComponents.Label {
            text: rootItem.copilotUsername !== "" ? i18n("GitHub Copilot · @%1", rootItem.copilotUsername) : "GitHub Copilot"
            font.pixelSize: 10
            opacity: 0.65
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Rectangle {
            implicitHeight: 18
            implicitWidth: copilotBadgeLabel.implicitWidth + 12
            radius: 4
            color: Qt.rgba(0.55, 0.36, 0.96, 0.18)
            border.width: 1
            border.color: Qt.rgba(0.55, 0.36, 0.96, 0.35)

            PlasmaComponents.Label {
                id: copilotBadgeLabel
                anchors.centerIn: parent
                // The plan name is the more useful badge when the Copilot API
                // reported one; "CONNECTED" is all the billing endpoint knows.
                text: rootItem.copilotPlan !== "" ? rootItem.copilotPlan.toUpperCase() : i18n("CONNECTED")
                font.pixelSize: 9
                font.bold: true
                color: rootItem.copilotPurple
            }
        }

        // Scoped to GitHub's Copilot components by the backend.
        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.copilot
        }
    }

    ColumnLayout {
        visible: !rootItem.copilotKeyValid && !rootItem.copilotHasKey && rootItem.copilotError === ""
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
            text: i18n("No GitHub login found. Sign in with the Copilot\nCLI or `gh auth login`, or set a token in settings.")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    ColumnLayout {
        visible: rootItem.copilotError !== "" && !rootItem.copilotKeyValid
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents.Label {
            text: i18n("Copilot error")
            font.pixelSize: 12
            font.bold: true
            color: "#ef4444"
        }

        PlasmaComponents.Label {
            text: rootItem.errorText(rootItem.copilotError)
            font.pixelSize: 10
            opacity: 0.7
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    SubTabBar {
        // Nothing to switch between until at least one of the two halves has
        // something to show.
        visible: rootItem.copilotKeyValid || rootItem.copilotStatsAvailable
        accent: rootItem.copilotPurple
        currentId: copilotTabRoot.subTab
        onSelected: id => copilotTabRoot.subTab = id
    }

    // ── Premium requests ───────────────────────────────────────────────────────
    ColumnLayout {
        visible: copilotTabRoot.subTab === "usage" && rootItem.copilotKeyValid
        Layout.fillWidth: true
        spacing: 8

        PopupRow {
            label: i18n("Premium Requests")
            value: rootItem.copilotPct
            barColor: rootItem.copilotPurple
            countdownText: rootItem.copilotCountdown !== "" ? i18n("in %1", rootItem.copilotCountdown) : ""
            tokenText: rootItem.copilotUnlimited ? copilotTabRoot.fmtRequests(rootItem.copilotUsed) + " · " + i18n("unlimited") : copilotTabRoot.fmtRequests(rootItem.copilotUsed) + " / " + copilotTabRoot.fmtRequests(rootItem.copilotQuota)
            tooltipText: i18n("GitHub Copilot premium requests") + (rootItem.copilotCountdown !== "" ? "\n" + i18n("Resets in %1", rootItem.copilotCountdown) : "")
        }

        StatValueCard {
            accent: rootItem.copilotPurple
            rows: [
                {
                    label: i18n("Used"),
                    value: copilotTabRoot.fmtRequests(rootItem.copilotUsed),
                    strong: true
                },
                {
                    label: i18n("Remaining"),
                    value: rootItem.copilotUnlimited ? i18n("unlimited") : copilotTabRoot.fmtRequests(copilotTabRoot.remaining),
                    valueColor: rootItem.copilotUnlimited ? Kirigami.Theme.textColor : rootItem.usageColor(rootItem.copilotPct)
                },
                {
                    label: i18nc("reset time", "Reset"),
                    value: rootItem.copilotCountdown !== "" ? rootItem.copilotCountdown : i18n("next month")
                }
            ]
        }
    }

    // ── No-stats placeholder ───────────────────────────────────────────────────
    PlasmaComponents.Label {
        visible: copilotTabRoot.subTab === "stats" && !rootItem.copilotStatsAvailable
        Layout.fillWidth: true
        Layout.topMargin: 8
        horizontalAlignment: Text.AlignHCenter
        text: i18n("No local activity stats yet.\nRun the Copilot CLI to fill ~/.copilot/session-store.db")
        font.pixelSize: 10
        opacity: 0.5
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
    }

    // ── Copilot CLI local activity ─────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: copilotTabRoot.subTab === "stats" && rootItem.copilotStatsAvailable

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
                text: "Copilot CLI"
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
                tileValue: Math.round(rootItem.copilotStatsTotalSessions).toString()
                tileLabel: i18n("sessions")
                tileTip: i18n("%1 messages total", rootItem.formatTokens(rootItem.copilotStatsTotalMessages))
            }
            StatTile {
                tileValue: rootItem.formatTokens(rootItem.copilotStatsTotalMessages)
                tileLabel: i18n("messages")
                tileTip: i18n("Prompts sent across all Copilot CLI sessions")
            }
            StatTile {
                tileValue: Math.round(rootItem.copilotStatsActiveDays) + (rootItem.copilotStatsSpanDays > 0 ? "/" + Math.round(rootItem.copilotStatsSpanDays) : "")
                tileLabel: i18n("active days")
                tileTip: rootItem.copilotStatsFirstDate ? i18n("Since %1", Qt.formatDate(new Date(rootItem.copilotStatsFirstDate), "MMM d, yyyy")) : ""
            }
            StatTile {
                // xgettext:no-javascript-format
                tileValue: i18nc("streak length in days, abbreviated", "%1d", Math.round(rootItem.copilotStatsCurrentStreak))
                tileLabel: i18n("streak")
                // xgettext:no-javascript-format
                tileSub: i18nc("longest streak in days, abbreviated", "best %1d", Math.round(rootItem.copilotStatsLongestStreak))
                tileTip: i18np("Current consecutive-day streak\nLongest: %1 day", "Current consecutive-day streak\nLongest: %1 days", Math.round(rootItem.copilotStatsLongestStreak))
            }
            StatTile {
                tileValue: rootItem.formatDuration(rootItem.copilotStatsLongestSessionMs)
                tileLabel: i18n("longest session")
                tileSub: rootItem.copilotStatsLongestSessionMessages > 0 ? i18np("%1 msg", "%1 msgs", Math.round(rootItem.copilotStatsLongestSessionMessages)) : ""
            }
            StatTile {
                visible: rootItem.copilotStatsPeakHour >= 0
                tileValue: rootItem.copilotStatsPeakHour >= 0 ? (rootItem.copilotStatsPeakHour < 10 ? "0" : "") + rootItem.copilotStatsPeakHour + ":00" : "—"
                tileLabel: i18n("peak hour")
                tileTip: i18n("Hour of day with the most activity (UTC)")
            }
            StatTile {
                visible: rootItem.copilotStatsTotalToolCalls > 0
                tileValue: rootItem.formatTokens(rootItem.copilotStatsTotalToolCalls)
                tileLabel: i18n("tool calls")
                tileTip: i18n("Total tool invocations across all sessions")
            }
            StatTile {
                visible: rootItem.copilotStatsTotalFiles > 0
                tileValue: rootItem.formatTokens(rootItem.copilotStatsTotalFiles)
                tileLabel: i18n("files touched")
                tileTip: i18n("Distinct files read or edited across all sessions")
            }
            StatTile {
                visible: rootItem.copilotStatsTotalRepositories > 0
                tileValue: Math.round(rootItem.copilotStatsTotalRepositories).toString()
                tileLabel: i18n("repos")
                tileTip: i18n("Repositories the CLI has been run in")
            }
        }

        StatsSparkline {
            series: rootItem.copilotStatsDailyMessages
            unit: i18n("messages")
            barColor: rootItem.copilotPurple
            formatValue: rootItem.formatTokens
        }

        StatsTopList {
            entries: rootItem.copilotStatsTopRepositories
            label: i18n("Top repositories")
            accent: rootItem.copilotPurple
        }
    }

    component StatTile: StatTileBase {
        accentColor: rootItem.copilotPurple
    }
}
