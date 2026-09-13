import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: claudeTabRoot
    property Item rootItem

    // Inner sub-tab: "usage" (live quota/cost) vs "stats" (local /stats activity)
    property string subTab: "usage"

    visible: rootItem.enabledTabs[rootItem.activeTab] === "claude" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 14

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: rootItem.claudeSubscriptionType !== ""

        Kirigami.Icon {
            source: "user-identity"
            width: 14
            height: 14
            color: rootItem.claudeOrange
            isMask: true
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: rootItem.claudeTierLabel() || (rootItem.claudeOrganizationUuid ? rootItem.claudeOrganizationUuid.slice(0, 8) + "…" : i18n("Claude Code User"))
            font.pixelSize: 10
            opacity: 0.6
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        // Effort chip
        Rectangle {
            visible: rootItem.claudeEffortLevel !== ""
            implicitHeight: 16
            implicitWidth: effortChipLabel.implicitWidth + 12
            radius: 3
            readonly property color effortColor: {
                if (rootItem.claudeEffortLevel === "high")
                    return Qt.rgba(0.8, 0.47, 0.36, 0.85);
                if (rootItem.claudeEffortLevel === "low")
                    return Qt.rgba(0.4, 0.7, 0.4, 0.7);
                return Qt.rgba(1, 1, 1, 0.55);
            }
            color: Qt.rgba(effortColor.r, effortColor.g, effortColor.b, 0.15)
            border.width: 1
            border.color: Qt.rgba(effortColor.r, effortColor.g, effortColor.b, 0.35)
            QQC2.ToolTip.visible: effortMA.containsMouse
            QQC2.ToolTip.text: i18n("Thinking budget: %1", rootItem.claudeEffortLevel)
            QQC2.ToolTip.delay: 400
            MouseArea {
                id: effortMA
                anchors.fill: parent
                hoverEnabled: true
                propagateComposedEvents: true
            }
            PlasmaComponents.Label {
                id: effortChipLabel
                anchors.centerIn: parent
                text: i18nc("effort level", "effort: %1", rootItem.effortLabel(rootItem.claudeEffortLevel))
                font.pixelSize: 9
                font.bold: true
                color: parent.effortColor
            }
        }

        // Dream (extended thinking) chip
        Rectangle {
            visible: true
            implicitHeight: 16
            implicitWidth: dreamChipLabel.implicitWidth + 12
            radius: 3
            readonly property color dreamColor: rootItem.claudeAutoDream ? Qt.rgba(0.43, 0.35, 0.78, 0.9) : Qt.rgba(1, 1, 1, 0.3)
            color: Qt.rgba(dreamColor.r, dreamColor.g, dreamColor.b, 0.15)
            border.width: 1
            border.color: Qt.rgba(dreamColor.r, dreamColor.g, dreamColor.b, 0.35)
            QQC2.ToolTip.visible: dreamMA.containsMouse
            QQC2.ToolTip.text: rootItem.claudeAutoDream ? i18n("Extended thinking (dream mode): ON\nClaude will reason longer on complex tasks") : i18n("Extended thinking (dream mode): OFF")
            QQC2.ToolTip.delay: 400
            MouseArea {
                id: dreamMA
                anchors.fill: parent
                hoverEnabled: true
                propagateComposedEvents: true
            }
            PlasmaComponents.Label {
                id: dreamChipLabel
                anchors.centerIn: parent
                text: rootItem.claudeAutoDream ? i18n("dream: on") : i18n("dream: off")
                font.pixelSize: 9
                font.bold: rootItem.claudeAutoDream
                color: parent.dreamColor
            }
        }

        Rectangle {
            implicitHeight: 18
            implicitWidth: planLabelClaude.implicitWidth + 16
            Layout.alignment: Qt.AlignVCenter
            radius: 4
            color: rootItem.claudeSubscriptionType === "free" ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.8, 0.47, 0.36, 0.18)
            border.width: 1
            border.color: rootItem.claudeSubscriptionType === "free" ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.8, 0.47, 0.36, 0.35)
            PlasmaComponents.Label {
                id: planLabelClaude
                anchors.centerIn: parent
                text: rootItem.claudeSubscriptionType.toUpperCase()
                font.pixelSize: 10
                font.bold: true
                color: rootItem.claudeSubscriptionType === "free" ? Kirigami.Theme.textColor : rootItem.claudeOrange
            }
        }

        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.claude
        }
    }

    SubTabBar {
        accent: rootItem.claudeOrange
        currentId: claudeTabRoot.subTab
        onSelected: id => claudeTabRoot.subTab = id
    }

    PopupRow {
        visible: claudeTabRoot.subTab === "usage" && rootItem.sessionAvailable
        label: i18n("5 Hours")
        resetText: rootItem.sessionResetTime ? i18n("resets %1", rootItem.sessionResetTime) : ""
        countdownText: rootItem.sessionCountdown === "resetting..." ? i18n("resetting...") : (rootItem.sessionCountdown ? i18n("in %1", rootItem.sessionCountdown) : "")
        value: rootItem.sessionPct
        barColor: rootItem.sessionColor
        etaText: rootItem.usageHistory.length >= 0 ? rootItem.etaToFull("s", rootItem.sessionPct) : ""
        deltaText: rootItem.usageHistory.length >= 0 ? rootItem.periodDelta("s", rootItem.sessionPct, 24 * 3600000, i18n("yesterday")) : ""
        tokenText: rootItem.sessionTokensUsed > 0 ? i18n("%1 tokens", rootItem.formatTokens(rootItem.sessionTokensUsed) + (rootItem.sessionTokenLimit > 0 ? " / " + rootItem.formatTokens(rootItem.sessionTokenLimit) : "")) : ""
        tooltipText: i18n("Claude 5-hour rolling window\nUsage: %1%", Math.round(rootItem.sessionPct)) + (rootItem.sessionTokensUsed > 0 ? "\n" + i18n("%1 tokens", rootItem.formatTokens(rootItem.sessionTokensUsed) + (rootItem.sessionTokenLimit > 0 ? " / " + rootItem.formatTokens(rootItem.sessionTokenLimit) : "")) : "") + (rootItem.sessionResetTime ? "\n" + i18n("Resets: %1", rootItem.sessionResetTime) : "")
    }

    PopupRow {
        visible: claudeTabRoot.subTab === "usage" && rootItem.weeklyAvailable
        label: i18n("7 Days")
        resetText: rootItem.weeklyResetTime ? i18n("resets %1", rootItem.weeklyResetTime) : ""
        countdownText: rootItem.weeklyCountdown === "resetting..." ? i18n("resetting...") : (rootItem.weeklyCountdown ? i18n("in %1", rootItem.weeklyCountdown) : "")
        value: rootItem.weeklyPct
        barColor: rootItem.weeklyColor
        etaText: rootItem.usageHistory.length >= 0 ? rootItem.etaToFull("w", rootItem.weeklyPct) : ""
        deltaText: rootItem.usageHistory.length >= 0 ? rootItem.periodDelta("w", rootItem.weeklyPct, 7 * 24 * 3600000, i18n("last week")) : ""
        tokenText: rootItem.weeklyTokensUsed > 0 ? i18n("%1 tokens", rootItem.formatTokens(rootItem.weeklyTokensUsed) + (rootItem.weeklyTokenLimit > 0 ? " / " + rootItem.formatTokens(rootItem.weeklyTokenLimit) : "")) : ""
        tooltipText: i18n("Claude 7-day rolling window\nUsage: %1%", Math.round(rootItem.weeklyPct)) + (rootItem.weeklyTokensUsed > 0 ? "\n" + i18n("%1 tokens", rootItem.formatTokens(rootItem.weeklyTokensUsed) + (rootItem.weeklyTokenLimit > 0 ? " / " + rootItem.formatTokens(rootItem.weeklyTokenLimit) : "")) : "") + (rootItem.weeklyResetTime ? "\n" + i18n("Resets: %1", rootItem.weeklyResetTime) : "")
    }

    // ── API cost estimate (subscription users without admin API key) ───────────
    // Shown when we have token data but no real billing data from an admin key.
    // Assumes a 3:1 input:output token ratio (typical for coding workflows).
    // Pricing: sonnet-4 ($3/$15 per M), opus-4 ($15/$75 per M).
    Rectangle {
        id: apiCostEstimate
        visible: claudeTabRoot.subTab === "usage" && rootItem.weeklyTokensUsed > 0 && !rootItem.claudeHasAdminKey
        Layout.fillWidth: true
        height: costEstCol.implicitHeight + 16
        radius: 6
        color: Qt.rgba(0.8, 0.47, 0.36, 0.06)
        border.width: 1
        border.color: Qt.rgba(0.8, 0.47, 0.36, 0.15)

        readonly property real _tok: rootItem.weeklyTokensUsed / 1000000
        // blended rate: 0.75 input + 0.25 output
        readonly property real _sonnet: _tok * (0.75 * 3.0 + 0.25 * 15.0)
        readonly property real _opus: _tok * (0.75 * 15.0 + 0.25 * 75.0)

        QQC2.ToolTip.visible: costEstMA.containsMouse
        QQC2.ToolTip.delay: 300
        QQC2.ToolTip.text: i18n("Estimated API cost for your 7-day token usage\nif billed at pay-as-you-go rates.\n\nAssumes 3:1 input:output token ratio.\nActual cost depends on model mix used.\n\nAdd a Claude Admin API key in settings\nfor exact per-model billing data.")

        MouseArea {
            id: costEstMA
            anchors.fill: parent
            hoverEnabled: true
        }

        ColumnLayout {
            id: costEstCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                PlasmaComponents.Label {
                    text: i18n("API equiv. (7d)")
                    font.pixelSize: 10
                    font.bold: true
                    opacity: 0.55
                    color: Kirigami.Theme.textColor
                }
                PlasmaComponents.Label {
                    text: "~" + i18n("%1 tokens", rootItem.formatTokens(rootItem.weeklyTokensUsed))
                    font.pixelSize: 9
                    opacity: 0.35
                    color: Kirigami.Theme.textColor
                }
                Item {
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: i18n("est. ≈")
                    font.pixelSize: 9
                    opacity: 0.4
                    color: Kirigami.Theme.textColor
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // sonnet-4
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 4
                    color: Qt.rgba(0.8, 0.47, 0.36, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(0.8, 0.47, 0.36, 0.22)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "sonnet-4"
                            font.pixelSize: 8
                            opacity: 0.5
                            color: Kirigami.Theme.textColor
                        }
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "$" + apiCostEstimate._sonnet.toFixed(apiCostEstimate._sonnet < 0.01 ? 4 : 2)
                            font.pixelSize: 12
                            font.bold: true
                            color: rootItem.claudeOrange
                        }
                    }
                }

                // opus-4
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 4
                    color: Qt.rgba(0.8, 0.47, 0.36, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(0.8, 0.47, 0.36, 0.15)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "opus-4"
                            font.pixelSize: 8
                            opacity: 0.5
                            color: Kirigami.Theme.textColor
                        }
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "$" + apiCostEstimate._opus.toFixed(apiCostEstimate._opus < 0.01 ? 4 : 2)
                            font.pixelSize: 12
                            font.bold: true
                            color: Kirigami.Theme.textColor
                            opacity: 0.75
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: claudeTabRoot.subTab === "usage" && rootItem.claudeExtraTokens > 0
        Layout.fillWidth: true
        height: 30
        radius: 6
        color: Qt.rgba(0.8, 0.47, 0.36, 0.12)
        border.width: 1
        border.color: Qt.rgba(0.8, 0.47, 0.36, 0.25)
        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 6
            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: rootItem.claudeOrange
            }
            PlasmaComponents.Label {
                text: i18n("Extra budget")
                font.pixelSize: 11
                font.bold: true
                color: rootItem.claudeOrange
            }
            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                text: i18n("%1 tokens remaining", rootItem.formatTokens(rootItem.claudeExtraTokens))
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                opacity: 0.8
            }
        }
    }

    PopupRow {
        visible: claudeTabRoot.subTab === "usage" && rootItem.claudeExtraUsageEnabled && rootItem.claudeExtraUsageLimit > 0
        label: i18n("Extra Purchases")
        value: rootItem.claudeExtraUsagePct
        barColor: rootItem.claudeOrange
        tokenText: i18n("%1 / %2 %3 used", rootItem.claudeExtraUsageUsed.toFixed(2), rootItem.claudeExtraUsageLimit.toFixed(2), rootItem.claudeExtraUsageCurrency)
        tooltipText: i18n("Claude pay-as-you-go credit spend\nLimit: %1 %2", rootItem.claudeExtraUsageLimit, rootItem.claudeExtraUsageCurrency)
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: claudeTabRoot.subTab === "usage" && Object.keys(rootItem.claudeModels).length > 0

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PlasmaComponents.Label {
                text: i18n("API Usage (30d)")
                font.bold: true
                font.pixelSize: 11
                opacity: 0.7
                color: Kirigami.Theme.textColor
            }
            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents.Label {
                text: "$" + rootItem.claudeTotalCostUSD.toFixed(2)
                font.bold: true
                font.pixelSize: 13
                color: rootItem.claudeOrange
            }
        }
        PlasmaComponents.Label {
            text: i18n("%1 in", rootItem.formatTokens(rootItem.claudeTotalInputTokens)) + "  ·  " + i18n("%1 out", rootItem.formatTokens(rootItem.claudeTotalOutputTokens))
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
        }

        Repeater {
            model: {
                var keys = Object.keys(rootItem.claudeModels);
                keys.sort(function (a, b) {
                    return rootItem.claudeModels[b].cost_usd - rootItem.claudeModels[a].cost_usd;
                });
                return keys;
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                // HoverHandler rather than a MouseArea: a MouseArea here would be a
                // layout child, and anchoring it to fill the layout is undefined behavior.
                HoverHandler {
                    id: costHover
                }
                QQC2.ToolTip.visible: costHover.hovered
                QQC2.ToolTip.delay: 400
                QQC2.ToolTip.text: {
                    var m = rootItem.claudeModels[modelData];
                    if (!m)
                        return modelData;
                    return modelData + "\n" + i18n("Input: %1 tokens", rootItem.formatTokens(m.input_tokens)) + "\n" + i18n("Output: %1 tokens", rootItem.formatTokens(m.output_tokens)) + "\n" + i18n("Cost: %1", m.priced ? "$" + m.cost_usd.toFixed(4) : i18n("unpriced"));
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PlasmaComponents.Label {
                        text: rootItem.shortenModelName(modelData)
                        font.pixelSize: 10
                        opacity: 0.65
                        Layout.preferredWidth: 90
                        elide: Text.ElideRight
                        color: Kirigami.Theme.textColor
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: i18n("%1 in", rootItem.formatTokens(rootItem.claudeModels[modelData].input_tokens))
                        font.pixelSize: 9
                        opacity: 0.4
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: i18n("%1 out", rootItem.formatTokens(rootItem.claudeModels[modelData].output_tokens))
                        font.pixelSize: 9
                        opacity: 0.4
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: rootItem.claudeModels[modelData].priced ? "$" + rootItem.claudeModels[modelData].cost_usd.toFixed(3) : "—"
                        font.pixelSize: 11
                        font.bold: true
                        color: Kirigami.Theme.textColor
                        opacity: rootItem.claudeModels[modelData].priced ? 1.0 : 0.4
                        Layout.preferredWidth: 52
                        horizontalAlignment: Text.AlignRight
                    }
                }
                Item {
                    Layout.fillWidth: true
                    height: 3
                    Rectangle {
                        anchors.fill: parent
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.05)
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 1.5
                        color: rootItem.claudeOrange
                        opacity: 0.7
                        width: rootItem.claudeTotalCostUSD > 0 ? parent.width * (rootItem.claudeModels[modelData].cost_usd / rootItem.claudeTotalCostUSD) : 0
                        Behavior on width {
                            NumberAnimation {
                                duration: 500
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }

    // ── No-stats placeholder ───────────────────────────────────────────────────
    PlasmaComponents.Label {
        visible: claudeTabRoot.subTab === "stats" && !rootItem.claudeStatsAvailable
        Layout.fillWidth: true
        Layout.topMargin: 8
        horizontalAlignment: Text.AlignHCenter
        text: i18n("No local activity stats yet.\nRun Claude Code to generate ~/.claude/stats-cache.json")
        font.pixelSize: 10
        opacity: 0.5
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
    }

    // ── Claude Code local activity stats (mirrors `/stats`) ────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: claudeTabRoot.subTab === "stats" && rootItem.claudeStatsAvailable

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
            // Favorite (most-used) model chip.
            Rectangle {
                visible: rootItem.claudeStatsFavoriteModel !== ""
                implicitHeight: 16
                implicitWidth: favLabel.implicitWidth + 14
                radius: 3
                color: Qt.rgba(0.8, 0.47, 0.36, 0.15)
                border.width: 1
                border.color: Qt.rgba(0.8, 0.47, 0.36, 0.35)
                PlasmaComponents.Label {
                    id: favLabel
                    anchors.centerIn: parent
                    text: "★ " + rootItem.shortenModelName(rootItem.claudeStatsFavoriteModel)
                    font.pixelSize: 9
                    font.bold: true
                    color: rootItem.claudeOrange
                }
            }
        }

        // ── Stat tiles grid ────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 6
            columnSpacing: 6

            StatTile {
                tileValue: rootItem.formatTokens(rootItem.claudeStatsTotalTokens)
                tileLabel: i18nc("stat label", "tokens")
                tileTip: i18n("Total input+output tokens across all models (all time)")
            }
            StatTile {
                tileValue: Math.round(rootItem.claudeStatsTotalSessions).toString()
                tileLabel: i18nc("stat label", "sessions")
                tileTip: i18n("%1 messages total", rootItem.formatTokens(rootItem.claudeStatsTotalMessages))
            }
            StatTile {
                tileValue: Math.round(rootItem.claudeStatsActiveDays) + (rootItem.claudeStatsSpanDays > 0 ? "/" + Math.round(rootItem.claudeStatsSpanDays) : "")
                tileLabel: i18n("active days")
                tileTip: rootItem.claudeStatsFirstDate ? i18n("Since %1", Qt.formatDate(new Date(rootItem.claudeStatsFirstDate), "MMM d, yyyy")) : ""
            }
            StatTile {
                // xgettext:no-javascript-format
                tileValue: i18nc("streak length in days, abbreviated", "%1d", Math.round(rootItem.claudeStatsCurrentStreak))
                tileLabel: i18nc("stat label", "streak")
                // xgettext:no-javascript-format
                tileSub: i18nc("longest streak in days, abbreviated", "best %1d", Math.round(rootItem.claudeStatsLongestStreak))
                tileTip: i18np("Current consecutive-day streak\nLongest: %1 day", "Current consecutive-day streak\nLongest: %1 days", Math.round(rootItem.claudeStatsLongestStreak))
            }
            StatTile {
                tileValue: rootItem.formatDuration(rootItem.claudeStatsLongestSessionMs)
                tileLabel: i18n("longest session")
                tileSub: rootItem.claudeStatsLongestSessionMessages > 0 ? i18np("%1 msg", "%1 msgs", Math.round(rootItem.claudeStatsLongestSessionMessages)) : ""
            }
            StatTile {
                visible: rootItem.claudeStatsPeakHour >= 0
                tileValue: rootItem.claudeStatsPeakHour >= 0 ? (rootItem.claudeStatsPeakHour < 10 ? "0" : "") + rootItem.claudeStatsPeakHour + ":00" : "—"
                tileLabel: i18n("peak hour")
                tileTip: i18n("Hour of day with the most activity")
            }
            // Recorded by newer Claude CLI builds; hidden on older stats caches.
            StatTile {
                visible: rootItem.claudeStatsTotalCostUSD > 0
                tileValue: "$" + rootItem.claudeStatsTotalCostUSD.toFixed(2)
                tileLabel: i18nc("stat label", "spend")
                tileTip: i18n("Total cost across all models (all time)")
            }
            StatTile {
                visible: rootItem.claudeStatsTotalToolCalls > 0
                tileValue: rootItem.formatTokens(rootItem.claudeStatsTotalToolCalls)
                tileLabel: i18n("tool calls")
                tileTip: i18n("Total tool invocations across all sessions")
            }
            StatTile {
                visible: rootItem.claudeStatsTotalWebSearches > 0
                tileValue: rootItem.formatTokens(rootItem.claudeStatsTotalWebSearches)
                tileLabel: i18n("web searches")
                tileTip: i18n("Total web search requests across all models")
            }
        }

        StatsSparkline {
            series: rootItem.claudeStatsDailyTokens
            unit: i18n("tokens")
            barColor: rootItem.claudeOrange
            formatValue: rootItem.formatTokens
        }

        // ── Per-model token usage (all time) ───────────────────────────────
        Repeater {
            model: {
                var keys = Object.keys(rootItem.claudeStatsModels);
                keys.sort(function (a, b) {
                    return rootItem.claudeStatsModels[b].total - rootItem.claudeStatsModels[a].total;
                });
                return keys;
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                // HoverHandler rather than a MouseArea: a MouseArea here would be a
                // layout child, and anchoring it to fill the layout is undefined behavior.
                HoverHandler {
                    id: statsHover
                }
                QQC2.ToolTip.visible: statsHover.hovered
                QQC2.ToolTip.delay: 400
                QQC2.ToolTip.text: {
                    var m = rootItem.claudeStatsModels[modelData];
                    if (!m)
                        return modelData;
                    return modelData + "\n" + i18n("Input: %1", rootItem.formatTokens(m.input)) + "\n" + i18n("Output: %1", rootItem.formatTokens(m.output)) + "\n" + i18n("Cache read: %1", rootItem.formatTokens(m.cacheRead)) + "\n" + i18n("Cache write: %1", rootItem.formatTokens(m.cacheCreation)) + (m.cost > 0 ? "\n" + i18n("Cost: %1", "$" + m.cost.toFixed(2)) : "") + (m.webSearches > 0 ? "\n" + i18n("Web searches: %1", m.webSearches) : "");
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PlasmaComponents.Label {
                        text: rootItem.shortenModelName(modelData)
                        font.pixelSize: 10
                        opacity: 0.65
                        Layout.preferredWidth: 90
                        elide: Text.ElideRight
                        color: Kirigami.Theme.textColor
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: i18n("%1 in", rootItem.formatTokens(rootItem.claudeStatsModels[modelData].input))
                        font.pixelSize: 9
                        opacity: 0.4
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: i18n("%1 out", rootItem.formatTokens(rootItem.claudeStatsModels[modelData].output))
                        font.pixelSize: 9
                        opacity: 0.4
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        visible: (rootItem.claudeStatsModels[modelData].cost || 0) > 0
                        text: "$" + (rootItem.claudeStatsModels[modelData].cost || 0).toFixed(2)
                        font.pixelSize: 9
                        opacity: 0.55
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: rootItem.claudeStatsTotalTokens > 0 ? Math.round(rootItem.claudeStatsModels[modelData].total / rootItem.claudeStatsTotalTokens * 100) + "%" : "—"
                        font.pixelSize: 11
                        font.bold: true
                        color: Kirigami.Theme.textColor
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                    }
                }
                Item {
                    Layout.fillWidth: true
                    height: 3
                    Rectangle {
                        anchors.fill: parent
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.05)
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 1.5
                        color: rootItem.claudeOrange
                        opacity: 0.7
                        width: rootItem.claudeStatsTotalTokens > 0 ? parent.width * (rootItem.claudeStatsModels[modelData].total / rootItem.claudeStatsTotalTokens) : 0
                        Behavior on width {
                            NumberAnimation {
                                duration: 500
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        // Freshness note — Claude recomputes this cache daily, so it can lag.
        PlasmaComponents.Label {
            visible: rootItem.claudeStatsComputedDate !== ""
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: i18n("computed %1", rootItem.claudeStatsComputedDate)
            font.pixelSize: 8
            opacity: 0.35
            color: Kirigami.Theme.textColor
        }
    }

    component StatTile: StatTileBase {
        accentColor: rootItem.claudeOrange
    }
}
