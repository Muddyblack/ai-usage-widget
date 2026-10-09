import QtQuick
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// A short run of mutually exclusive choices over [[value, label], …].
Rectangle {
    id: control

    property var options: []
    property var value
    property color accent: Theme.brand
    signal chosen(var value)

    implicitWidth: row.implicitWidth + 6
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight
    radius: 8
    color: Tone.c(palette, Theme.sunk)
    border.width: 1
    border.color: Tone.c(palette, Theme.line2)

    Row {
        id: row
        x: 3
        y: 3
        spacing: 2
        Repeater {
            model: control.options
            Rectangle {
                id: seg
                required property var modelData
                readonly property bool on: String(control.value) === String(modelData[0])
                height: 24
                width: label.implicitWidth + 20
                radius: 6
                color: on ? Qt.rgba(control.accent.r, control.accent.g, control.accent.b, 0.28) : segArea.containsMouse ? Tone.c(palette, Theme.hover) : "transparent"
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: seg.modelData[1]
                    color: seg.on ? Tone.c(palette, Theme.text) : Tone.c(palette, Theme.muted)
                    font.pixelSize: 11
                    font.weight: seg.on ? Font.DemiBold : Font.Normal
                }
                MouseArea {
                    id: segArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: control.chosen(seg.modelData[0])
                }
            }
        }
    }
}
