import QtQuick
import "Theme.js" as Theme

// Round colour swatches. Any #rrggbb can be typed in a StudioField beside it.
Flow {
    id: control

    property var swatches: []
    property string value: ""
    signal activated(string value)

    spacing: 8

    Repeater {
        model: control.swatches
        Item {
            id: swatch
            required property var modelData
            readonly property bool chosen: String(control.value).toLowerCase() === String(modelData).toLowerCase()
            width: 20
            height: 20
            Rectangle {
                anchors.centerIn: parent
                width: 28
                height: 28
                radius: 14
                visible: swatch.chosen
                color: "transparent"
                border.width: 2
                border.color: Theme.text
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: swatch.modelData
                border.width: 1
                border.color: "#33ffffff"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: control.activated(swatch.modelData)
            }
        }
    }
}
