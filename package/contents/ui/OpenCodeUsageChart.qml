import QtQuick
import org.kde.kirigami as Kirigami
import "../code/OpenCodeUsage.js" as OpenCodeUsage

// Adapt a local ledger to UsageChart's existing Plasma host interface. The
// navigation, axes, grid, line and hover tooltip all belong to UsageChart.
UsageChart {
    id: chart
    property var stats: ({})
    property color accent: Kirigami.Theme.highlightColor
    property color cardColor: Qt.rgba(1, 1, 1, 0.04)
    property alias selectedRange: model.chartWindow
    readonly property var sourceSeries: stats.dailySeries && stats.dailySeries.length ? stats.dailySeries : stats.dailyTokens || []
    readonly property var windows: OpenCodeUsage.chartWindows(sourceSeries, referenceTime)
    persistSelection: false
    Accessible.name: i18n("Daily token usage")

    rootItem: Item {
        id: model
        property var enabledTabs: ["local"]
        property int activeTab: 0
        property bool showSettings: false
        property bool showUsageChart: true
        property string errorMsg: ""
        property color resolvedCardBg: chart.cardColor
        property color activeAccent: chart.accent
        property color googleBlue: "#4285f4"
        property color googleGreen: "#34a853"
        property string chartWindow: "7d"
        property string chartGranularity: "7d"
        property real chartTimeOffset: 0
        property var usageHistory: OpenCodeUsage.history(chart.sourceSeries)
        property var weeklyUsageHistory: OpenCodeUsage.chartSeries(chartWindow, chart.sourceSeries, chart.referenceTime, chartTimeOffset)
        onChartWindowChanged: chartTimeOffset = 0

        function chartWindowsFor(tab) {
            return chart.windows;
        }
        function currentChartWindow() {
            return chart.windows.find(function (window) {
                return window.id === model.chartWindow;
            }) || chart.windows[0];
        }
        function _historyKey() {
            return "tokens";
        }
        function hasAnySeriesData() {
            return usageHistory.length > 0;
        }
        function getChartWindowSize() {
            return currentChartWindow().size;
        }
        function usageSlopePerHour(key, lookback) {
            return null;
        }
        function windowLabel(label) {
            return label === "All" ? i18n("All") : label;
        }
        function getChartRangeText() {
            var end = chart.referenceTime - chartTimeOffset;
            return Qt.formatDate(new Date(end - getChartWindowSize()), "MMM d") + " - " + Qt.formatDate(new Date(end), "MMM d");
        }
    }
}
