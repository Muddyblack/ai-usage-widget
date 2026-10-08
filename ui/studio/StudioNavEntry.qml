import QtQuick
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// One tab of a StudioNav.
Rectangle {
    id: entry

    required property var modelData
    // The StudioNav that lists this entry.
    required property var owner
    readonly property bool on: owner.currentId === modelData.id

    height: owner.horizontal ? 34 : 36
    width: owner.horizontal ? label.implicitWidth + 44 : owner.width
    radius: 9
    color: on ? Tone.c(palette, Theme.navActive) : entryArea.containsMouse ? Tone.c(palette, Theme.hover) : "transparent"

    Rectangle {
        visible: entry.on && !entry.owner.horizontal
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 16
        radius: 1.5
        color: entry.owner.accent
    }
    Canvas {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        readonly property color tint: entry.on ? entry.owner.accent : Tone.c(palette, Theme.muted)
        onTintChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.scale(width / 24, height / 24);
            ctx.strokeStyle = tint;
            ctx.lineWidth = 1.8;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.path = entry.modelData.icon;
            ctx.stroke();
        }
    }
    Text {
        id: label
        x: 36
        anchors.verticalCenter: parent.verticalCenter
        width: entry.owner.horizontal ? implicitWidth : entry.width - 44
        text: entry.modelData.label
        color: entry.on ? Tone.c(palette, Theme.text) : Tone.c(palette, Theme.muted)
        font.pixelSize: 12
        font.weight: entry.on ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
    }
    MouseArea {
        id: entryArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: entry.owner.selected(entry.modelData.id)
    }
}
