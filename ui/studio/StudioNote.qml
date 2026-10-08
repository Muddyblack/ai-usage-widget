import QtQuick
import "Theme.js" as Theme

// Tinted aside (the studios' `.note`), also used for status messages.
Rectangle {
    id: note

    property string text: ""
    property color tone: Theme.noteText

    width: parent ? parent.width : implicitWidth
    implicitHeight: body.implicitHeight + 22
    height: implicitHeight
    radius: 10
    color: Theme.noteBg
    border.width: 1
    border.color: Theme.noteBorder

    Text {
        id: body
        x: 12
        y: 11
        width: parent.width - 24
        text: note.text
        color: note.tone
        font.pixelSize: 10
        lineHeight: 1.25
        wrapMode: Text.WordWrap
    }
}
