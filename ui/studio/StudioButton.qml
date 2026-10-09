import QtQuick
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// Outlined button, or the brand-filled `primary` one.
Rectangle {
    id: control

    property string text: ""
    property bool primary: false
    signal clicked

    implicitWidth: label.implicitWidth + 26
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight
    radius: 8
    opacity: enabled ? 1 : 0.45
    color: primary ? (area.containsMouse ? Theme.brandTop : Theme.brand) : area.containsMouse ? Tone.c(palette, Theme.hover) : "transparent"
    border.width: primary ? 0 : 1
    border.color: Tone.c(palette, Theme.line2)

    Text {
        id: label
        anchors.centerIn: parent
        text: control.text
        color: control.primary ? Tone.c(palette, Theme.brandInk) : area.containsMouse ? Tone.c(palette, Theme.text) : Tone.c(palette, Theme.muted)
        font.pixelSize: 11
        font.weight: control.primary ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: control.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }
}
