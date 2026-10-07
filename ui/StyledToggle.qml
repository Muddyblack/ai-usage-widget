import QtQuick
import QtQuick.Controls.Basic as QC

// The accent-filled switch used across the settings page. Lived as an inline
// `component Toggle` in SettingsPage until the provider rows needed it too.
QC.Switch {
    id: sw

    implicitHeight: 22

    indicator: Rectangle {
        implicitWidth: 38
        implicitHeight: 20
        x: 0
        y: (sw.height - height) / 2
        radius: 10
        color: sw.checked ? "#4f9dde" : Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 2
            x: sw.checked ? parent.width - width - 2 : 2
            color: "#f8fafc"

            Behavior on x {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
