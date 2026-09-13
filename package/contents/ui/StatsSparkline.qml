import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One bar per day of a stats series. What is being counted differs per
// provider — tokens for Claude, messages for the Copilot CLI — so the caller
// passes the series, the noun and how to format a value.
ColumnLayout {
    id: spark

    property var series: []
    property string unit: i18n("tokens")
    property color barColor: Kirigami.Theme.highlightColor
    // rootItem.formatTokens, so the abbreviation matches every other number.
    property var formatValue: null

    readonly property real maxValue: {
        var mx = 1;
        for (var i = 0; i < spark.series.length; i++)
            if (spark.series[i].total > mx)
                mx = spark.series[i].total;
        return mx;
    }

    function display(value) {
        return spark.formatValue ? spark.formatValue(value) : Math.round(value).toString();
    }

    Layout.fillWidth: true
    spacing: 3
    visible: series.length > 1

    PlasmaComponents.Label {
        text: i18n("%1 / day", spark.unit.charAt(0).toUpperCase() + spark.unit.slice(1))
        font.pixelSize: 9
        opacity: 0.45
        color: Kirigami.Theme.textColor
    }

    Row {
        id: barRow

        Layout.fillWidth: true
        height: 34
        spacing: 1

        readonly property real barW: Math.max(1, (width - (spark.series.length - 1)) / Math.max(1, spark.series.length))

        Repeater {
            model: spark.series

            Rectangle {
                required property var modelData

                width: barRow.barW
                height: barRow.height
                color: "transparent"
                QQC2.ToolTip.visible: barMA.containsMouse
                QQC2.ToolTip.delay: 300
                QQC2.ToolTip.text: modelData.date + "\n" + spark.display(modelData.total) + " " + spark.unit

                MouseArea {
                    id: barMA

                    anchors.fill: parent
                    hoverEnabled: true
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    radius: 1
                    height: Math.max(2, parent.height * (parent.modelData.total / spark.maxValue))
                    color: spark.barColor
                    opacity: barMA.containsMouse ? 1.0 : 0.6
                }
            }
        }
    }
}
