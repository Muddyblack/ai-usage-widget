import QtQuick
import "Theme.js" as Theme

// One setting (the studios' `.row`): label and description on the left, the
// control on the right. A `full` row, or one too narrow for both, puts the
// control under the text instead. Whatever is declared inside is the control.
Item {
    id: row

    property string label: ""
    property string desc: ""
    // A colour dot before the label, e.g. a provider's accent.
    property color dot: "transparent"
    property bool full: false
    default property alias control: controlHolder.data

    readonly property bool stacked: full || width - controlHolder.childrenRect.width - 18 < 170

    width: parent ? parent.width : implicitWidth
    height: content.height + 24

    // The first row of a card has nothing above it to separate from.
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.line
        visible: row.y > 0
    }

    Item {
        id: content
        y: 12
        width: parent.width
        height: row.stacked ? head.height + (head.height > 0 ? 10 : 0) + controlHolder.childrenRect.height : Math.max(head.height, controlHolder.childrenRect.height)

        Row {
            id: head
            width: row.stacked ? parent.width : Math.max(0, parent.width - controlHolder.childrenRect.width - 18)
            height: row.label !== "" ? implicitHeight : 0
            y: row.stacked ? 0 : (parent.height - height) / 2
            spacing: 8
            visible: row.label !== ""

            Rectangle {
                visible: row.dot.a > 0
                width: 8
                height: 8
                radius: 4
                color: row.dot
                anchors.top: parent.top
                anchors.topMargin: 4
            }
            Column {
                width: parent.width - (row.dot.a > 0 ? 16 : 0)
                spacing: 2
                Text {
                    width: parent.width
                    text: row.label
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    visible: row.desc !== ""
                    text: row.desc
                    color: Theme.muted
                    font.pixelSize: 10
                    lineHeight: 1.2
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item {
            id: controlHolder
            x: row.stacked ? 0 : parent.width - childrenRect.width
            y: row.stacked ? head.height + (head.height > 0 ? 10 : 0) : (parent.height - childrenRect.height) / 2
            width: row.stacked ? parent.width : childrenRect.width
            height: childrenRect.height
        }
    }
}
