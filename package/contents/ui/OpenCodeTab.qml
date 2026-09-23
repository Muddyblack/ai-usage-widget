import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// OpenCode is local-first: periods describe observed usage, while cost is
// actual ledger cost or an exact catalog estimate when OpenCode did not store
// a provider charge. No quota percentage is invented for the local database.
ColumnLayout {
    id: tab
    property Item rootItem

    function providerFromRawProviders(providers) {
        var list = providers || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === "opencode")
                return list[i];
        }
        return {};
    }

    readonly property var provider: providerFromRawProviders(rootItem.rawProviders)
    readonly property var details: provider.details || ({})
    readonly property var stats: details.stats || ({})
    readonly property bool available: stats.available === true
    readonly property bool goMode: details.accountMode === "go"
    readonly property string accountModeLabel: goMode ? i18n("OpenCode Go") : i18n("OpenCode Zen")
    // Official OpenCode brand color (from opencode.ai logo — light pixel blocks)
    readonly property color accent: "#B7B1B1"
    visible: rootItem.enabledTabs[rootItem.activeTab] === "opencode" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 8

    // ── Empty state ─────────────────────────────────────────────────────────
    PlasmaComponents.Label {
        visible: !tab.available && !tab.goMode
        Layout.fillWidth: true
        Layout.topMargin: 8
        horizontalAlignment: Text.AlignHCenter
        text: i18n("No OpenCode sessions yet.\nZen activity is device-local and does not report account quota. Run a local session to see usage from its SQLite database.")
        font.pixelSize: 11
        opacity: 0.9
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
    }

    PlasmaComponents.Label {
        visible: tab.goMode && !tab.provider.ok
        Layout.fillWidth: true
        Layout.topMargin: 8
        text: tab.details.goError ? i18n("OpenCode Go usage unavailable: %1", tab.details.goError) : (tab.provider.summary || {}).detail || i18n("OpenCode Go usage unavailable")
        font.pixelSize: 10
        opacity: 0.7
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
    }

    // ── Provider header with icon ────────────────────────────────────────────
    RowLayout {
        visible: tab.available || tab.goMode
        Layout.fillWidth: true
        spacing: 8

        Image {
            source: Qt.resolvedUrl("../icons/opencode-color.svg")
            sourceSize.width: 20
            sourceSize.height: 20
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        PlasmaComponents.Label {
            text: i18n("OpenCode")
            font.bold: true
            font.pixelSize: 13
            color: tab.accent
        }

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            text: tab.goMode ? i18n("%1 · account", tab.accountModeLabel) : i18n("%1 · device-local · no account quota", tab.accountModeLabel)
            font.pixelSize: 9
            opacity: 0.4
            color: Kirigami.Theme.textColor
        }

        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.opencode || ({})
        }
    }

    ColumnLayout {
        visible: tab.goMode && tab.provider.ok
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: tab.provider.quotaWindows || []
            PopupRow {
                visible: modelData.showMeter === true && modelData.available === true
                readonly property string countdown: {
                    rootItem.countdownTick;
                    return rootItem.formatCountdown(rootItem.dateFromEpoch(modelData.resetAt));
                }
                label: modelData.label || ""
                value: modelData.pct
                barColor: tab.accent
                countdownText: countdown === "resetting..." ? countdown : (countdown ? i18n("in %1", countdown) : "")
                resetText: modelData.resetText || ""
                tokenText: modelData.detail || ""
                tooltipText: modelData.detail || modelData.label || ""
            }
        }
    }

    PlasmaComponents.Label {
        visible: tab.goMode && tab.available
        Layout.fillWidth: true
        text: i18n("Local OpenCode activity")
        font.pixelSize: 10
        font.bold: true
        opacity: 0.65
        color: Kirigami.Theme.textColor
    }

    // ── Daily token usage: primary OpenCode view ──────────────────────────────
    OpenCodeUsageChart {
        visible: tab.available
        stats: tab.stats
        accent: tab.accent
        formatTokens: rootItem.formatTokens
    }

    // ── Secondary stats grid + top lists ─────────────────────────────────────
    ColumnLayout {
        visible: tab.available
        Layout.fillWidth: true
        spacing: 6

        // Lifetime totals and detail stay secondary to the selected daily range.
        GridLayout {
            Layout.fillWidth: true
            columns: 4
            rowSpacing: 6
            columnSpacing: 6

            StatTile {
                tileValue: rootItem.formatTokens(stats.totalTokens || 0)
                tileLabel: i18nc("stat label", "tokens")
            }
            StatTile {
                visible: (stats.totalCostUSD || 0) > 0
                tileValue: rootItem.formatMoney(stats.totalCostUSD || 0, "USD")
                tileLabel: i18nc("stat label", "cost")
                tileTip: i18n("Recorded provider cost plus exact model catalog estimates")
            }
            StatTile {
                tileValue: Math.round(stats.totalSessions || 0).toString()
                tileLabel: i18nc("stat label", "sessions")
            }
            StatTile {
                tileValue: Math.round(stats.activeDays || 0) + "/" + Math.round(stats.spanDays || 0)
                tileLabel: i18n("active days")
            }
            StatTile {
                // xgettext:no-javascript-format
                tileValue: i18nc("streak length in days, abbreviated", "%1d", Math.round(stats.currentStreak || 0))
                tileLabel: i18nc("stat label", "streak")
                // xgettext:no-javascript-format
                tileSub: i18nc("longest streak in days, abbreviated", "best %1d", Math.round(stats.longestStreak || 0))
            }
            StatTile {
                visible: stats.favoriteModel !== undefined && stats.favoriteModel !== ""
                tileValue: rootItem.shortenModelName(stats.favoriteModel || "")
                tileLabel: i18n("top model")
            }
        }

        StatsTopList {
            entries: stats.topWorkspaces || []
            label: i18n("Top workspaces")
            accent: tab.accent
        }

        // ── Per-model breakdown ──────────────────────────────────────────────
        PlasmaComponents.Label {
            visible: Object.keys(stats.models || {}).length > 0
            text: i18n("Models")
            font.pixelSize: 9
            opacity: 0.4
            color: Kirigami.Theme.textColor
        }

        Repeater {
            model: {
                var models = stats.models || ({});
                var keys = Object.keys(models);
                keys.sort(function (a, b) {
                    return (models[b].total || 0) - (models[a].total || 0);
                });
                return keys;
            }
            RowLayout {
                required property string modelData
                readonly property var entry: (tab.stats.models || ({}))[modelData] || ({})
                Layout.fillWidth: true
                spacing: 6

                PlasmaComponents.Label {
                    text: parent.modelData
                    font.pixelSize: 10
                    opacity: 0.75
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: rootItem.formatTokens(parent.entry.total || 0) + " tok"
                    font.pixelSize: 10
                    opacity: 0.6
                    color: Kirigami.Theme.textColor
                }
                PlasmaComponents.Label {
                    visible: (parent.entry.cost || 0) > 0
                    text: rootItem.formatMoney(parent.entry.cost || 0, "USD")
                    font.pixelSize: 10
                    color: tab.accent
                }
            }
        }
    }

    component StatTile: StatTileBase {
        accentColor: tab.accent
    }
}
