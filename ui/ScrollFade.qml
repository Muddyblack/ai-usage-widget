import QtQuick

// A soft fade over the bottom edge of a scrolling area while more content is
// below it, so a cut-off chart reads as "scroll for more" rather than as
// missing — the thin scrollbar (PopupScrollBar.qml) shows only while
// scrolling. Anchor it to the bottom of the Flickable it watches.
Rectangle {
    id: fade

    property Flickable flick: null
    // The colour the content fades into: the popup's own glass, roughly.
    property color base: Qt.rgba(0.05, 0.07, 0.13, 1)

    readonly property bool more: !!flick && flick.contentHeight - flick.contentY - flick.height > 2

    height: 28
    opacity: more ? 1 : 0
    visible: opacity > 0
    enabled: false
    gradient: Gradient {
        GradientStop {
            position: 0
            color: Qt.rgba(fade.base.r, fade.base.g, fade.base.b, 0)
        }
        GradientStop {
            position: 1
            color: Qt.rgba(fade.base.r, fade.base.g, fade.base.b, 0.55)
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 200
        }
    }
}
