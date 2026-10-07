import QtQuick
import "../package/contents/code/OpenCodeUsage.js" as OpenCodeUsage

// The same chart used by quota providers, fed by a local daily token ledger.
UsageChart {
    id: chart
    property var stats: ({})
    property string selectedRange: "7d"
    readonly property var sourceSeries: stats.dailySeries && stats.dailySeries.length ? stats.dailySeries : stats.dailyTokens || []

    dailySeries: sourceSeries
    usageHistory: OpenCodeUsage.history(sourceSeries)
    windows: OpenCodeUsage.chartWindows(sourceSeries, referenceTime)
    chartWindow: selectedRange
    onWindowSelected: function (id) {
        selectedRange = id;
    }
    Accessible.name: shell.i18n("Daily token usage")
}
