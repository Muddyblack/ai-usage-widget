import QtQuick
import QtQuick.Controls.Basic as QC
import "js/Tone.js" as Tone

QC.Button {
    id: btn
    implicitHeight: 26
    padding: 8

    contentItem: Text {
        text: btn.text
        font.pixelSize: 10
        color: Tone.c(palette, "#f8fafc")
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 5
        color: btn.hovered ? Tone.c(palette, Qt.rgba(1, 1, 1, 0.12)) : Tone.c(palette, Qt.rgba(1, 1, 1, 0.06))
        border.width: 1
        border.color: Tone.c(palette, Qt.rgba(1, 1, 1, 0.14))
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }
}
