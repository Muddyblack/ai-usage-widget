import QtQuick
import QtQuick.Layouts

// Service-status chip for the popup header: the Quickshell twin of the Plasma
// widget's StatusChip.qml, fed by the same details.status block. QQC2.ToolTip
// needs Kirigami, which Quickshell does not ship, so the hover card is drawn
// here — the header row sets a z above its siblings so it can overlap them.
Rectangle {
    id: chip

    // { indicator, description, components, incidents, latestUpdate, url }
    property var status: ({})
    property var shell

    // "none" | "minor" | "major" | "critical" | "" (no live feed)
    readonly property string indicator: (status && status.indicator) || ""
    readonly property string statusUrl: (status && status.url) || ""
    // A page without a machine-readable feed is still worth a link.
    readonly property bool linkOnly: indicator === "" && statusUrl !== ""

    visible: indicator !== "" || linkOnly
    implicitHeight: 20
    implicitWidth: chipRow.implicitWidth + 16
    radius: 5

    readonly property color statusColor: {
        if (linkOnly)
            return Qt.rgba(1, 1, 1, 0.5);
        if (indicator === "critical")
            return Qt.rgba(1.0, 0.3, 0.3, 0.95);
        if (indicator === "major")
            return Qt.rgba(1.0, 0.5, 0.1, 0.95);
        if (indicator === "minor")
            return Qt.rgba(1.0, 0.75, 0.2, 0.95);
        return Qt.rgba(0.2, 0.8, 0.4, 0.95);
    }

    color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, chipMouse.containsMouse ? 0.2 : (linkOnly ? 0.06 : 0.12))
    border.width: 1
    border.color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, linkOnly ? 0.18 : 0.32)

    readonly property string tooltipText: {
        var s = chip.status || {};
        var lines = [chip.shell.i18n("Status") + "  ·  " + (s.description || chip.shell.i18n("Unknown"))];
        var comps = s.components || [];
        if (comps.length > 0) {
            lines.push("", chip.shell.i18n("Affected:"));
            for (var c = 0; c < comps.length; c++)
                lines.push("  · " + comps[c]);
        }
        var inc = s.incidents || [];
        if (inc.length > 0) {
            lines.push("", chip.shell.i18np("Incident:", "Incidents:", inc.length));
            for (var i = 0; i < inc.length; i++)
                lines.push("  · " + inc[i]);
        }
        if (s.latestUpdate)
            lines.push("", chip.shell.i18n("Latest update:"), s.latestUpdate);
        if (chip.statusUrl !== "")
            lines.push("", chip.shell.i18n("Click to open status page"));
        return lines.join("\n");
    }

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5

        Rectangle {
            visible: !chip.linkOnly
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: chip.statusColor

            SequentialAnimation on opacity {
                running: chip.visible && !chip.linkOnly && chip.indicator !== "none"
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

        Text {
            text: {
                if (chip.linkOnly)
                    return chip.shell.i18n("Status ↗");
                if (chip.indicator === "critical")
                    return chip.shell.i18n("Major Outage");
                if (chip.indicator === "major")
                    return chip.shell.i18n("Partial Outage");
                if (chip.indicator === "minor")
                    return chip.shell.i18n("Minor Issues");
                return chip.shell.i18n("Operational");
            }
            font.pixelSize: 10
            font.bold: !chip.linkOnly && chip.indicator !== "none"
            color: chip.statusColor
        }
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: chip.statusUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (chip.statusUrl !== "")
                Qt.openUrlExternally(chip.statusUrl);
        }
    }

    Timer {
        id: tipDelay
        interval: 300
        onTriggered: tip.visible = chipMouse.containsMouse && !chip.linkOnly
    }
    Connections {
        target: chipMouse
        function onContainsMouseChanged() {
            if (chipMouse.containsMouse) {
                tipDelay.restart();
            } else {
                tipDelay.stop();
                tip.visible = false;
            }
        }
    }

    Rectangle {
        id: tip
        visible: false
        anchors.top: chip.bottom
        anchors.topMargin: 6
        anchors.right: chip.right
        width: 280
        height: tipText.implicitHeight + 16
        radius: 6
        color: Qt.rgba(0.04, 0.045, 0.06, 0.97)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
            id: tipText
            x: 10
            y: 8
            width: parent.width - 20
            text: chip.tooltipText
            color: "#e2e8f0"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
