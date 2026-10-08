import QtQuick
import "Theme.js" as Theme

// A titled group of rows (the studios' `.sec`): small uppercase title, then a
// rounded card holding the rows, separated by hairlines.
Column {
    id: group

    property string title: ""
    property string caption: ""
    default property alias rows: body.data

    width: parent ? parent.width : implicitWidth
    spacing: 8

    Text {
        visible: group.title !== ""
        width: parent.width
        text: group.title.toUpperCase()
        color: Theme.sectionTitle
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        leftPadding: 2
    }

    Rectangle {
        width: parent.width
        height: body.height + 4
        radius: 12
        color: Theme.card
        border.width: 1
        border.color: Theme.line

        Column {
            id: body
            x: 14
            y: 2
            width: parent.width - 28
        }
    }

    Text {
        visible: group.caption !== ""
        width: parent.width
        text: group.caption
        color: Theme.dim
        font.pixelSize: 10
        wrapMode: Text.WordWrap
        leftPadding: 2
        lineHeight: 1.2
    }
}
