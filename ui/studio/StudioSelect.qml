import QtQuick
import QtQuick.Controls.Basic as Controls
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// Dropdown over [[value, label], …]; `chosen(value)` fires on a user pick.
Controls.ComboBox {
    id: control

    property var options: []
    property var value
    signal chosen(var value)

    model: options
    currentIndex: Math.max(0, options.findIndex(o => String(o[0]) === String(value)))
    displayText: options.length ? (options[currentIndex] ?? options[0])[1] : ""
    implicitWidth: 160
    implicitHeight: 30
    font.pixelSize: 11
    onActivated: index => control.chosen(options[index][0])

    background: Rectangle {
        radius: 8
        color: Tone.c(palette, Theme.sunk)
        border.width: 1
        border.color: control.hovered || control.popup.visible ? Tone.c(palette, "#40ffffff") : Tone.c(palette, Theme.line2)
    }
    contentItem: Text {
        leftPadding: 10
        rightPadding: 24
        text: control.displayText
        color: Tone.c(palette, Theme.text)
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 10
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        color: Tone.c(palette, Theme.muted)
        font.pixelSize: 11
    }
    delegate: Controls.ItemDelegate {
        id: item
        required property var modelData
        required property int index
        width: control.width
        height: 28
        contentItem: Text {
            text: item.modelData[1]
            color: item.index === control.currentIndex ? Theme.brandTop : Tone.c(palette, Theme.text)
            font: control.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 6
            color: item.hovered ? Tone.c(palette, "#1affffff") : "transparent"
        }
    }
    popup: Controls.Popup {
        // A popup starts a palette of its own; carry the popup's light or dark in.
        palette.window: control.palette.window
        y: control.height + 4
        width: control.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 300)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
        }
        background: Rectangle {
            radius: 10
            color: Tone.c(palette, "#15181d")
            border.width: 1
            border.color: Tone.c(palette, Theme.line2)
        }
    }
}
