import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
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
    Layout.preferredHeight: chartContents.implicitHeight + 20
    radius: 8
    color: Qt.rgba(chart.accent.r, chart.accent.g, chart.accent.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(chart.accent.r, chart.accent.g, chart.accent.b, 0.18)

    ColumnLayout {
        id: chartContents
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PlasmaComponents.Label {
                text: chart.groupedAll ? i18n("Usage trend") : i18n("Daily usage")
                font.bold: true
                font.pixelSize: 11
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: chart.selectedPeriod.label || (chart.selectedRange === "7d" ? i18n("Last 7 days") : chart.selectedRange === "30d" ? i18n("Last 30 days") : i18n("All time"))
                font.pixelSize: 9
                opacity: 0.65
                color: Kirigami.Theme.textColor
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

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

                PlasmaComponents.Button {
                    required property var modelData
                    text: modelData.label
                    checkable: true
                    checked: chart.selectedRange === modelData.key
                    Accessible.name: i18n("Show OpenCode usage for %1", modelData.label)
                    onClicked: chart.selectedRange = modelData.key
                }
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: chart.formatTokens(chart.selectedPeriod.tokens || 0) + " " + i18n("tokens") + " · " + Math.round(chart.selectedPeriod.sessions || 0) + " " + i18n("sessions")
                font.pixelSize: 10
                font.bold: true
                color: chart.accent
            }
        }

        Item {
            id: dailyChart
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            Accessible.name: i18n("Daily OpenCode token usage")

            readonly property real maxValue: {
                var maximum = 0;
                for (var i = 0; i < chart.dailySeries.length; i++)
                    maximum = Math.max(maximum, chart.dailySeries[i].total || 0);
                return maximum;
            }

            PlasmaComponents.Label {
                anchors.centerIn: parent
                visible: chart.dailySeries.length === 0
                text: i18n("No daily usage in this range")
                font.pixelSize: 10
                opacity: 0.55
                color: Kirigami.Theme.textColor
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 3
                visible: chart.dailySeries.length > 0

                Row {
                    id: dailyBars
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property real barSpacing: chart.dailySeries.length * 2 > width ? 0 : 2
                    spacing: barSpacing
                    readonly property real barWidth: Math.max(0, (width - Math.max(0, chart.dailySeries.length - 1) * spacing) / Math.max(1, chart.dailySeries.length))

                    Repeater {
                        model: chart.dailySeries

                        Rectangle {
                            required property var modelData
                            width: dailyBars.barWidth
                            height: dailyBars.height
                            color: "transparent"
                            Accessible.name: (modelData.endDate ? modelData.date + " – " + modelData.endDate : modelData.date) + ": " + chart.formatTokens(modelData.total || 0) + " tokens"
                            QQC2.ToolTip.visible: barMouse.containsMouse
                            QQC2.ToolTip.delay: 300
                            QQC2.ToolTip.text: (modelData.endDate ? modelData.date + " – " + modelData.endDate : modelData.date) + "\n" + chart.formatTokens(modelData.total || 0) + " " + i18n("tokens")

                            MouseArea {
                                id: barMouse
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: parent.modelData.total > 0 && dailyChart.maxValue > 0 ? Math.max(2, parent.height * (parent.modelData.total / dailyChart.maxValue)) : 0
                                radius: 1
                                color: chart.accent
                                opacity: barMouse.containsMouse ? 1 : 0.72
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    PlasmaComponents.Label {
                        text: chart.dailySeries.length ? Qt.formatDate(new Date(chart.dailySeries[0].date + "T00:00:00"), "MMM d") : ""
                        font.pixelSize: 8
                        opacity: 0.45
                        color: Kirigami.Theme.textColor
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        text: chart.dailySeries.length ? Qt.formatDate(new Date(chart.dailySeries[chart.dailySeries.length - 1].date + "T00:00:00"), "MMM d") : ""
                        font.pixelSize: 8
                        opacity: 0.45
                        color: Kirigami.Theme.textColor
                    }
                }
            }
        }
    }
}
