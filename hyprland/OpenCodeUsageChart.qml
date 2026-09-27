import QtQuick
import QtQuick.Layouts
import "../package/contents/code/OpenCodeUsage.js" as OpenCodeUsage

// Daily OpenCode token usage with 7D / 30D / All ranges, ported from the
// Plasma OpenCodeUsageChart. OpenCode Zen has no plan windows, so this is the
// chart its Usage tab shows instead of the quota history.
Rectangle {
    id: chart

    property var shell
    property var stats: ({})
    property color accent: "#B7B1B1"
    property string selectedRange: "7d"

    readonly property var sourceSeries: stats.dailySeries && stats.dailySeries.length ? stats.dailySeries : stats.dailyTokens || []
    readonly property var dailySeries: OpenCodeUsage.seriesForRange(selectedRange, sourceSeries, new Date().getTime())
    readonly property var selectedPeriod: OpenCodeUsage.periodForRange(selectedRange, stats.periods)
    readonly property bool groupedAll: selectedRange === "all" && dailySeries.length > 0 && dailySeries[0].endDate !== undefined

    function formatTokens(n) {
        if (!n || n <= 0)
            return "0";
        if (n >= 1000000)
            return (n / 1000000).toFixed(2) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(1) + "K";
        return Math.round(n).toString();
    }

    Layout.fillWidth: true
    implicitHeight: chartContents.implicitHeight + 15
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.045)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    clip: true

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(1, 1, 1, 0.10)
        radius: 10
    }

    ColumnLayout {
        id: chartContents
        anchors.fill: parent
        anchors.topMargin: 7
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        anchors.bottomMargin: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: chart.groupedAll ? chart.shell.i18n("Usage trend") : chart.shell.i18n("Daily usage")
                font.bold: true
                font.pixelSize: 10
                opacity: 0.8
                color: "#f8fafc"
                Layout.fillWidth: true
            }

            Repeater {
                model: [
                    {
                        key: "7d",
                        label: chart.shell.i18n("7D")
                    },
                    {
                        key: "30d",
                        label: chart.shell.i18n("30D")
                    },
                    {
                        key: "all",
                        label: chart.shell.i18n("All")
                    }
                ]

                Rectangle {
                    id: rangePill
                    required property var modelData
                    readonly property bool active: chart.selectedRange === modelData.key
                    radius: 4
                    implicitHeight: 16
                    implicitWidth: rangeLabel.implicitWidth + 12
                    color: active ? chart.accent : Qt.rgba(1, 1, 1, 0.06)
                    opacity: active ? 0.9 : 1.0
                    Accessible.role: Accessible.Button
                    Accessible.name: chart.shell.i18n("Show OpenCode usage for %1", modelData.label)
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    Text {
                        id: rangeLabel
                        anchors.centerIn: parent
                        text: rangePill.modelData.label
                        font.pixelSize: 9
                        font.bold: rangePill.active
                        // Near-white accents (OpenCode's grey) would swallow white text.
                        color: rangePill.active ? ((0.299 * chart.accent.r + 0.587 * chart.accent.g + 0.114 * chart.accent.b) > 0.6 ? "#1a1a1a" : "#ffffff") : "#f8fafc"
                        opacity: rangePill.active ? 1.0 : 0.6
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: chart.selectedRange = rangePill.modelData.key
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: chart.formatTokens(chart.selectedPeriod.tokens || 0) + " " + chart.shell.i18n("tokens") + " · " + Math.round(chart.selectedPeriod.sessions || 0) + " " + chart.shell.i18n("sessions")
                font.pixelSize: 10
                font.bold: true
                color: chart.accent
                Layout.fillWidth: true
            }

            Text {
                text: chart.selectedPeriod.label || (chart.selectedRange === "7d" ? chart.shell.i18n("Last 7 days") : chart.selectedRange === "30d" ? chart.shell.i18n("Last 30 days") : chart.shell.i18n("All time"))
                font.pixelSize: 10
                opacity: 0.6
                color: "#f8fafc"
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: !dailyChart.visible
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: chart.shell.i18n("No daily usage in this range")
            font.pixelSize: 10
            opacity: 0.55
            color: "#f8fafc"
        }

        // The shared daily-series chart, so OpenCode draws its tokens with the
        // same line, grid, scrub and date ticks as the Spend page.
        SpendTimelineChart {
            id: dailyChart
            Layout.fillWidth: true
            shell: chart.shell
            showWindowPills: false
            Accessible.name: chart.shell.i18n("Daily OpenCode token usage")
            points: chart.dailySeries.map(function (point) {
                return {
                    date: point.date,
                    usd: 0,
                    total: point.total || 0
                };
            })
            tokenColor: chart.accent
        }
    }
}
