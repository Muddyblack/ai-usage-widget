import QtQuick
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// 36 x 21 pill switch with a springy knob. Emits `toggled(checked)` with the
// value it would take; the owner decides and sets `checked`.
Item {
    id: control

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 36
    implicitHeight: 21
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Tone.c(palette, Theme.switchOff)
        gradient: control.checked ? onGradient : null
        Gradient {
            id: onGradient
            GradientStop {
                position: 0
                color: Theme.brandTop
            }
            GradientStop {
                position: 1
                color: Theme.brandBottom
            }
        }
    }
    Rectangle {
        width: 15
        height: 15
        radius: 7.5
        y: 3
        x: control.checked ? 18 : 3
        color: control.checked ? Tone.c(palette, "#ffffff") : Tone.c(palette, Theme.knob)
        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: control.toggled(!control.checked)
    }
}
