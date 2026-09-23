import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: chart
    property var stats: ({})
    property color accent: Kirigami.Theme.highlightColor
    property var formatTokens: value => Math.round(value).toString()
    property string selectedRange: "7d"

    function seriesForRange(range, series, now) {
        var dailyTotals = {};
        (series || []).forEach(function (point) {
            if (!point || !/^\d{4}-\d{2}-\d{2}$/.test(point.date || ""))
                return;
            var total = typeof point.total === "number" && isFinite(point.total) ? point.total : 0;
            dailyTotals[point.date] = (dailyTotals[point.date] || 0) + total;
        });
        var dates = Object.keys(dailyTotals).sort();
        if (dates.length === 0)
            return [];

        function dateFromParts(date) {
            return new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)));
        }
        function formatLocalDate(date) {
            var month = String(date.getMonth() + 1).padStart(2, "0");
            var day = String(date.getDate()).padStart(2, "0");
            return date.getFullYear() + "-" + month + "-" + day;
        }
        function utcDay(date) {
            return Date.UTC(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10))) / 86400000;
        }

        var lastDate = formatLocalDate(new Date(now));
        var firstDate = range === "all" ? dates[0] : lastDate;
        if (range !== "all") {
            var windowDays = range === "30d" ? 30 : 7;
            var cutoff = dateFromParts(lastDate);
            cutoff.setDate(cutoff.getDate() - windowDays + 1);
            firstDate = formatLocalDate(cutoff);
        }
        if (firstDate > lastDate)
            return [];

        var spanDays = utcDay(lastDate) - utcDay(firstDate) + 1;
        var maxAllPoints = 366;
        var bucketDays = range === "all" ? Math.max(1, Math.ceil(spanDays / maxAllPoints)) : 1;
        var pointCount = Math.ceil(spanDays / bucketDays);
        var start = dateFromParts(firstDate);
        var output = [];
        for (var i = 0; i < pointCount; i++) {
            var pointDate = new Date(start.getTime());
            pointDate.setDate(pointDate.getDate() + i * bucketDays);
            var endDate = new Date(start.getTime());
            endDate.setDate(endDate.getDate() + Math.min(spanDays - 1, (i + 1) * bucketDays - 1));
            output.push({
                date: formatLocalDate(pointDate),
                endDate: bucketDays > 1 ? formatLocalDate(endDate) : undefined,
                total: 0
            });
        }
        dates.forEach(function (date) {
            if (date < firstDate || date > lastDate)
                return;
            var pointIndex = Math.floor((utcDay(date) - utcDay(firstDate)) / bucketDays);
            if (pointIndex >= 0 && pointIndex < output.length)
                output[pointIndex].total += dailyTotals[date];
        });
        return output;
    }

    function periodForRange(range, periods) {
        var list = periods || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].key === range)
                return list[i];
        }
        return {};
    }

    readonly property var sourceSeries: stats.dailySeries && stats.dailySeries.length ? stats.dailySeries : stats.dailyTokens || []
    readonly property var dailySeries: seriesForRange(selectedRange, sourceSeries, new Date().getTime())
    readonly property var selectedPeriod: periodForRange(selectedRange, stats.periods)
    readonly property bool groupedAll: selectedRange === "all" && dailySeries.length > 0 && dailySeries[0].endDate !== undefined

    Layout.fillWidth: true
    Layout.preferredHeight: chartContents.implicitHeight + 15
    // Same card and range pills as the shared UsageChart (Claude, Codex, ...).
    property color cardColor: Qt.rgba(1, 1, 1, 0.04)
    radius: 10
    color: chart.cardColor
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    clip: true

    // subtle inner top highlight, as in UsageChart
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

            PlasmaComponents.Label {
                text: chart.groupedAll ? i18n("Usage trend") : i18n("Daily usage")
                font.bold: true
                font.pixelSize: 10
                opacity: 0.8
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            Repeater {
                model: [
                    {
                        key: "7d",
                        label: i18n("7D")
                    },
                    {
                        key: "30d",
                        label: i18n("30D")
                    },
                    {
                        key: "all",
                        label: i18n("All")
                    }
                ]

                Rectangle {
                    id: rangePill
                    required property var modelData
                    readonly property bool active: chart.selectedRange === modelData.key
                    radius: 4
                    implicitHeight: 16
                    implicitWidth: rangeLabel.implicitWidth + 12
                    color: active ? chart.accent : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                    opacity: active ? 0.9 : 1.0
                    Accessible.role: Accessible.Button
                    Accessible.name: i18n("Show OpenCode usage for %1", modelData.label)
                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    PlasmaComponents.Label {
                        id: rangeLabel
                        anchors.centerIn: parent
                        text: rangePill.modelData.label
                        font.pixelSize: 10
                        font.bold: rangePill.active
                        // Near-white accents (OpenCode's grey) would swallow white text.
                        color: rangePill.active ? ((0.299 * chart.accent.r + 0.587 * chart.accent.g + 0.114 * chart.accent.b) > 0.6 ? "#1a1a1a" : "#ffffff") : Kirigami.Theme.textColor
                        opacity: rangePill.active ? 1.0 : 0.8
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

            PlasmaComponents.Label {
                text: chart.formatTokens(chart.selectedPeriod.tokens || 0) + " " + i18n("tokens") + " · " + Math.round(chart.selectedPeriod.sessions || 0) + " " + i18n("sessions")
                font.pixelSize: 10
                font.bold: true
                color: chart.accent
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: chart.selectedPeriod.label || (chart.selectedRange === "7d" ? i18n("Last 7 days") : chart.selectedRange === "30d" ? i18n("Last 30 days") : i18n("All time"))
                font.pixelSize: 10
                opacity: 0.6
                color: Kirigami.Theme.textColor
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            visible: !dailyChart.visible
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: i18n("No daily usage in this range")
            font.pixelSize: 10
            opacity: 0.55
            color: Kirigami.Theme.textColor
        }

        // The shared daily-series chart (Spend tab), so OpenCode draws its
        // tokens with the same line, glow, grid, scrub and date ticks.
        SpendTimelineChart {
            id: dailyChart
            Layout.fillWidth: true
            Accessible.name: i18n("Daily OpenCode token usage")
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
