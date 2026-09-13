import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: statusChip

    // One provider's details.status from the backend:
    // { indicator, description, components, incidents, latestUpdate, url }
    property var status: ({})

    // "none" | "minor" | "major" | "critical" | "" (no live feed)
    readonly property string indicator: (status && status.indicator) || ""
    readonly property string description: (status && status.description) || ""
    readonly property var affectedComponents: (status && status.components) || []
    readonly property var incidents: (status && status.incidents) || []
    readonly property string latestUpdate: (status && status.latestUpdate) || ""
    readonly property string statusUrl: (status && status.url) || ""
    // A page without a machine-readable feed is still worth a link.
    readonly property bool linkOnly: indicator === "" && statusUrl !== ""

    visible: indicator !== "" || linkOnly
    implicitHeight: 16
    implicitWidth: chipRow.implicitWidth + 14
    radius: 3

    readonly property color statusColor: {
        if (linkOnly)
            return Qt.rgba(1, 1, 1, 0.45);
        if (indicator === "critical")
            return Qt.rgba(1.0, 0.3, 0.3, 0.9);
        if (indicator === "major")
            return Qt.rgba(1.0, 0.5, 0.1, 0.9);
        if (indicator === "minor")
            return Qt.rgba(1.0, 0.75, 0.2, 0.9);
        return Qt.rgba(0.2, 0.8, 0.4, 0.9);
    }

    color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, linkOnly ? 0.06 : 0.12)
    border.width: 1
    border.color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, linkOnly ? 0.18 : 0.30)

    QQC2.ToolTip.visible: chipMA.containsMouse && !linkOnly
    QQC2.ToolTip.delay: 300
    QQC2.ToolTip.text: {
        var lines = [i18n("Status") + "  ·  " + (description || i18n("Unknown"))];

        var comps = affectedComponents || [];
        if (comps.length > 0) {
            lines.push("");
            lines.push(i18n("Affected:"));
            for (var c = 0; c < comps.length; c++)
                lines.push("  · " + comps[c]);
        }

        var inc = incidents || [];
        if (inc.length > 0) {
            lines.push("");
            lines.push(i18np("Incident:", "Incidents:", inc.length));
            for (var i = 0; i < inc.length; i++)
                lines.push("  · " + inc[i]);
        }

        var upd = latestUpdate || "";
        if (upd !== "") {
            lines.push("");
            lines.push(i18n("Latest update:"));
            lines.push(upd);
        }

        if (statusUrl !== "") {
            lines.push("");
            lines.push(i18n("Click to open status page"));
        }
        return lines.join("\n");
    }

    MouseArea {
        id: chipMA
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: statusChip.statusUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (statusChip.statusUrl !== "")
                Qt.openUrlExternally(statusChip.statusUrl);
        }
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
            id: dotRect
            width: 5
            height: 5
            radius: 2.5
            color: statusChip.statusColor
            visible: !statusChip.linkOnly

            SequentialAnimation on opacity {
                running: !statusChip.linkOnly && statusChip.indicator !== "none" && statusChip.indicator !== ""
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.35
                    duration: 700
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1.0
                    duration: 700
                    easing.type: Easing.InOutSine
                }
            }
        }

        PlasmaComponents.Label {
            id: chipLabel
            text: {
                if (statusChip.linkOnly)
                    return i18n("Status ↗");
                var ind = statusChip.indicator;
                if (ind === "critical")
                    return i18n("Major Outage");
                if (ind === "major")
                    return i18n("Partial Outage");
                if (ind === "minor")
                    return i18n("Minor Issues");
                return i18n("Operational");
            }
            font.pixelSize: 9
            font.bold: !statusChip.linkOnly && statusChip.indicator !== "none"
            color: statusChip.statusColor
        }
    }
}
