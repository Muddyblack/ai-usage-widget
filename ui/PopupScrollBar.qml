import QtQuick
import QtQuick.Controls.Basic as QC

// The popup's scrollbar: a thin, faint thumb that shows only while the body
// scrolls or the pointer is on it, and fades out after. Basic style on
// purpose, so no platform theme (Plasma's paints it in the accent colour,
// full height) draws a second, louder one over the content's edge.
QC.ScrollBar {
    id: bar

    policy: QC.ScrollBar.AsNeeded
    minimumSize: 0.08
    padding: 1

    contentItem: Rectangle {
        implicitWidth: bar.hovered || bar.pressed ? 6 : 3
        radius: width / 2
        color: Qt.rgba(1, 1, 1, bar.pressed ? 0.45 : bar.hovered ? 0.32 : 0.2)
        opacity: bar.active || bar.hovered ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 300
            }
        }
        Behavior on implicitWidth {
            NumberAnimation {
                duration: 120
            }
        }
    }
    background: null
}
