import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: museTabRoot
    property Item rootItem

    // Inner sub-tab: "usage" (lifetime totals and spend) vs "stats" (local
    // activity), same split as the Claude, OpenAI and Copilot tabs.
    property string subTab: "usage"

    visible: rootItem.enabledTabs[rootItem.activeTab] === "muse" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.museHasLogin

        Kirigami.Icon {
            source: Qt.resolvedUrl("../icons/muse-color.svg")
            width: 14
            height: 14
        }

        PlasmaComponents.Label {
            text: rootItem.museFullName !== "" ? i18n("Muse Code · %1", rootItem.museFullName) : "Muse Code"
            font.pixelSize: 10
            opacity: 0.65
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        // The model the CLI will actually use next, read from its own
        // settings — never a name pinned in our source.
        Rectangle {
            visible: rootItem.museModel !== ""
            implicitHeight: 18
            implicitWidth: museModelLabel.implicitWidth + 12
            radius: 4
            color: Qt.rgba(rootItem.museBlue.r, rootItem.museBlue.g, rootItem.museBlue.b, 0.18)
            border.width: 1
            border.color: Qt.rgba(rootItem.museBlue.r, rootItem.museBlue.g, rootItem.museBlue.b, 0.35)

            PlasmaComponents.Label {
                id: museModelLabel
                anchors.centerIn: parent
                text: rootItem.shortenModelName(rootItem.museModel)
                font.pixelSize: 9
                font.bold: true
                color: rootItem.museBlue
            }
        }
    }

    ColumnLayout {
        visible: rootItem.museError !== ""
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents.Label {
            text: rootItem.museHasLogin ? i18n("No Muse activity yet") : i18n("Not connected")
            font.pixelSize: 12
            font.bold: true
            color: Kirigami.Theme.textColor
            opacity: 0.7
        }

        PlasmaComponents.Label {
            text: rootItem.museHasLogin ? i18n("Run a Muse Code session and its local logs\nwill appear here.") : i18n("Sign in with `muse login`. Nothing to paste:\nthis tab only reads Muse's own local files.")
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    SubTabBar {
        visible: rootItem.museError === ""
        accent: rootItem.museBlue
        currentId: museTabRoot.subTab
        onSelected: id => museTabRoot.subTab = id
    }

    // ── Lifetime totals ────────────────────────────────────────────────────────
    ColumnLayout {
        visible: museTabRoot.subTab === "usage" && rootItem.museError === ""
        Layout.fillWidth: true
        spacing: 8

        PopupRow {
            visible: rootItem.museCurrentAvailable
            label: i18n("Current")
            value: rootItem.museCurrentPct
            barColor: rootItem.museBlue
            countdownText: rootItem.museCurrentCountdown !== "" ? i18n("in %1", rootItem.museCurrentCountdown) : ""
            tooltipText: i18n("Muse current window") + (rootItem.museCurrentCountdown !== "" ? "\n" + i18n("Resets in %1", rootItem.museCurrentCountdown) : "")
        }

        PopupRow {
            visible: rootItem.museWeeklyAvailable
            label: i18n("Weekly")
            value: rootItem.museWeeklyPct
            barColor: rootItem.museBlue
            countdownText: rootItem.museWeeklyCountdown !== "" ? i18n("in %1", rootItem.museWeeklyCountdown) : ""
            tooltipText: i18n("Muse weekly window") + (rootItem.museWeeklyCountdown !== "" ? "\n" + i18n("Resets in %1", rootItem.museWeeklyCountdown) : "")
        }

        StatValueCard {
            accent: rootItem.museBlue
            rows: {
                var out = [
                    {
                        label: i18nc("stat label", "Tokens"),
                        value: rootItem.formatTokens(rootItem.museTotalTokens),
                        strong: true
                    },
                    {
                        label: i18nc("stat label", "Output"),
                        value: rootItem.formatTokens(rootItem.museOutputTokens)
                    }
                ];
                if (rootItem.museCostUSD > 0)
                    out.push({
                        label: i18nc("stat label", "Spend (est.)"),
                        value: rootItem.formatMoney(rootItem.museCostUSD, rootItem.museCurrency)
                    });
                out.push({
                    label: i18n("Model calls"),
                    value: Math.round(rootItem.museModelCalls).toString()
                });
                return out;
            }
        }

        // Muse is the only provider whose plan quota cannot be read for free,
        // so the tab says why the bars are missing — and, when they are on,
        // that they are the one thing here that is not free.
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: !rootItem.museQuotaOn
            text: i18n("Plan quota is off: Meta reports it only on a billed model call.\nEverything above is read from Muse's own local files.\nSettings › Providers › Muse › Live turns it on.")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: rootItem.museQuotaOn && rootItem.museQuotaError !== ""
            text: {
                if (rootItem.museQuotaError === "rejected")
                    return i18n("Plan quota: Meta refused the credential.");
                if (rootItem.museQuotaError === "unreachable")
                    return i18n("Plan quota: could not reach Meta — the local numbers above are unaffected.");
                if (rootItem.museQuotaError === "no-credential")
                    return i18n("Plan quota needs a Meta API key, or a `muse login` that stored one.");
                if (rootItem.museQuotaError === "no-model")
                    return i18n("Plan quota needs a model: run Muse once so it caches its catalog.");
                return "";
            }
            font.pixelSize: 9
            opacity: 0.55
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: rootItem.museQuotaOn && rootItem.museQuotaError === "" && !rootItem.museCurrentAvailable && !rootItem.museWeeklyAvailable
            text: i18n("No plan windows on this account — pay-as-you-go has none.")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
            wrapMode: Text.WordWrap
        }
    }

    // ── Local activity ─────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: museTabRoot.subTab === "stats" && rootItem.museError === ""

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
                text: i18n("Muse Code CLI")
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
                visible: rootItem.museTotalTokens > 0
                tileValue: rootItem.formatTokens(rootItem.museTotalTokens)
                tileLabel: i18nc("stat label", "tokens")
                tileTip: i18n("%1 output", rootItem.formatTokens(rootItem.museOutputTokens)) + " · " + i18n("%1 input (context is resent each call)", rootItem.formatTokens(rootItem.museInputTokens))
            }
            StatTile {
                visible: rootItem.museCostUSD > 0
                tileValue: rootItem.formatMoney(rootItem.museCostUSD, rootItem.museCurrency)
                tileLabel: i18nc("stat label", "spend (est.)")
                tileTip: i18n("Tokens priced with the model catalog Muse caches locally")
            }
            StatTile {
                tileValue: Math.round(rootItem.museStatsTotalSessions).toString()
                tileLabel: i18nc("stat label", "sessions")
                tileTip: i18n("%1 messages total", rootItem.formatTokens(rootItem.museStatsTotalMessages))
            }
            StatTile {
                tileValue: Math.round(rootItem.museStatsActiveDays) + (rootItem.museStatsSpanDays > 0 ? "/" + Math.round(rootItem.museStatsSpanDays) : "")
                tileLabel: i18n("active days")
                tileTip: rootItem.museStatsFirstDate ? i18n("Since %1", Qt.formatDate(new Date(rootItem.museStatsFirstDate), "MMM d, yyyy")) : ""
            }
            StatTile {
                // xgettext:no-javascript-format
                tileValue: i18nc("streak length in days, abbreviated", "%1d", Math.round(rootItem.museStatsCurrentStreak))
                tileLabel: i18nc("stat label", "streak")
                // xgettext:no-javascript-format
                tileSub: i18nc("longest streak in days, abbreviated", "best %1d", Math.round(rootItem.museStatsLongestStreak))
                tileTip: i18np("Current consecutive-day streak\nLongest: %1 day", "Current consecutive-day streak\nLongest: %1 days", Math.round(rootItem.museStatsLongestStreak))
            }
            StatTile {
                tileValue: rootItem.formatDuration(rootItem.museStatsLongestSessionMs)
                tileLabel: i18n("longest session")
                tileSub: rootItem.museStatsLongestSessionMessages > 0 ? i18np("%1 msg", "%1 msgs", Math.round(rootItem.museStatsLongestSessionMessages)) : ""
            }
            StatTile {
                visible: rootItem.museStatsPeakHour >= 0
                tileValue: rootItem.museStatsPeakHour >= 0 ? (rootItem.museStatsPeakHour < 10 ? "0" : "") + rootItem.museStatsPeakHour + ":00" : "—"
                tileLabel: i18n("peak hour")
                tileTip: i18n("Hour of day with the most activity (UTC)")
            }
            StatTile {
                visible: rootItem.museStatsTotalToolCalls > 0
                tileValue: rootItem.formatTokens(rootItem.museStatsTotalToolCalls)
                tileLabel: i18n("tool calls")
                tileTip: i18n("Total tool invocations across all sessions")
            }
            StatTile {
                visible: rootItem.museStatsSubagentSessions > 0
                tileValue: Math.round(rootItem.museStatsSubagentSessions).toString()
                tileLabel: i18nc("stat label", "subagents")
                tileTip: i18n("Delegated subagent sessions, logged separately by Muse")
            }
        }

        StatsSparkline {
            series: rootItem.museStatsDailyTokens
            unit: i18n("tokens")
            barColor: rootItem.museBlue
            formatValue: rootItem.formatTokens
        }

        StatsTopList {
            entries: rootItem.museStatsTopWorkspaces
            label: i18n("Top workspaces")
            accent: rootItem.museBlue
        }

        // ── Per-model usage (all time) ─────────────────────────────────────
        Repeater {
            model: {
                var keys = Object.keys(rootItem.museStatsModels);
                keys.sort(function (a, b) {
                    return rootItem.museStatsModels[b].output - rootItem.museStatsModels[a].output;
                });
                return keys;
            }
            RowLayout {
                required property string modelData
                readonly property var entry: rootItem.museStatsModels[modelData] || ({})

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
                    text: i18n("%1 out", rootItem.formatTokens(parent.entry.output || 0))
                    font.pixelSize: 10
                    opacity: 0.6
                    color: Kirigami.Theme.textColor
                }
                PlasmaComponents.Label {
                    visible: (parent.entry.cost || 0) > 0
                    text: "$" + (parent.entry.cost || 0).toFixed(2)
                    font.pixelSize: 10
                    color: rootItem.museBlue
                }
            }
        }
    }

    component StatTile: StatTileBase {
        accentColor: rootItem.museBlue
    }
}
