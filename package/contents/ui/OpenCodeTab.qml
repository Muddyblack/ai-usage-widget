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
    readonly property var provider: rootItem.providerById("opencode") || ({})
    readonly property var details: provider.details || ({})
    readonly property var stats: details.stats || ({})
    readonly property bool available: stats.available === true
    // Official OpenCode brand color (from opencode.ai logo — light pixel blocks)
    readonly property color accent: "#B7B1B1"

    visible: rootItem.enabledTabs[rootItem.activeTab] === "opencode" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 8

    // ── Empty state ─────────────────────────────────────────────────────────
    PlasmaComponents.Label {
        visible: !tab.available
        Layout.fillWidth: true
        Layout.topMargin: 8
        horizontalAlignment: Text.AlignHCenter
        text: i18n("No OpenCode sessions yet.\nEnable OpenCode and run a local session; usage is read from its SQLite database.")
        font.pixelSize: 10
        opacity: 0.5
        color: Kirigami.Theme.textColor
        wrapMode: Text.WordWrap
    }

    // ── Provider header with icon ────────────────────────────────────────────
    RowLayout {
        visible: tab.available
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
            text: i18n("SQLite · local")
            font.pixelSize: 9
            opacity: 0.4
            color: Kirigami.Theme.textColor
        }

        StatusChip {
            Layout.alignment: Qt.AlignVCenter
            status: rootItem.providerStatus.opencode || ({})
        }
    }

    // ── Recent-period summary card ───────────────────────────────────────────
    StatValueCard {
        visible: tab.available && (stats.periods || []).length > 0
        accent: tab.accent
        rows: (stats.periods || []).map(function (period) {
            var count = Math.round(period.sessions || 0);
            var value = rootItem.formatTokens(period.tokens || 0) + " tok · " + count + " " + (count === 1 ? i18n("session") : i18n("sessions"));
            if ((period.cost || 0) > 0)
                value += " · " + rootItem.formatMoney(period.cost, "USD");
            return {
                label: period.label || "",
                value: value,
                strong: period.key === "7d"
            };
        })
    }

    // ── Stats grid + sparkline + top lists ──────────────────────────────────
    ColumnLayout {
        visible: tab.available
        Layout.fillWidth: true
        spacing: 6

        // 4-column grid keeps everything in two compact rows without scrolling
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

        StatsSparkline {
            series: stats.dailySeries || []
            unit: i18n("tokens")
            barColor: tab.accent
            formatValue: rootItem.formatTokens
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
