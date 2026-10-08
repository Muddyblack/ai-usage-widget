import QtQuick
import "Theme.js" as Theme
import "../js/Tone.js" as Tone

// A percentage of any value: drag the slider or type a number. `value` is a
// fraction (0.35 is 35 %); `chosen(fraction)` fires when a drag is released or
// a typed number is accepted, not on every pixel, so the setting is saved once.
Item {
    id: control

    property real value: 0
    // Bounds as fractions.
    property real from: 0
    property real to: 1

    signal chosen(real value)

    implicitWidth: 196
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight

    // What the slider shows: the drag position while held, else the setting.
    readonly property real shown: dragArea.pressed ? dragValue : value
    property real dragValue: value

    function clamp(v) {
        return Math.max(control.from, Math.min(control.to, v));
    }
    function fraction() {
        return control.to > control.from ? (control.shown - control.from) / (control.to - control.from) : 0;
    }

    Item {
        id: track
        x: 0
        width: 118
        height: parent.height

        Rectangle {
            id: rail
            width: parent.width
            height: 4
            radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: Tone.c(palette, "#1affffff")
            Rectangle {
                width: parent.width * control.fraction()
                height: parent.height
                radius: 2
                color: Theme.brand
            }
        }
        Rectangle {
            x: (track.width - width) * control.fraction()
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: Tone.c(palette, "#f4f6f6")
            border.width: dragArea.pressed ? 4 : 0
            border.color: "#554f9dde"
        }
        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function at(mouseX) {
                var f = Math.max(0, Math.min(1, (mouseX - 7) / (track.width - 14)));
                control.dragValue = Math.round(control.clamp(control.from + f * (control.to - control.from)) * 100) / 100;
            }
            onPressed: mouse => at(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    at(mouse.x);
            }
            onReleased: control.chosen(control.dragValue)
        }
    }

    // The number, editable: Enter or leaving the field accepts it.
    Rectangle {
        x: track.width + 12
        width: 66
        height: parent.height
        radius: 8
        color: Tone.c(palette, Theme.sunk)
        border.width: 1
        border.color: input.activeFocus ? Qt.rgba(0.31, 0.62, 0.87, 0.8) : Tone.c(palette, Theme.line2)

        TextInput {
            id: input
            x: 10
            width: parent.width - 30
            anchors.verticalCenter: parent.verticalCenter
            color: Tone.c(palette, Theme.text)
            selectionColor: Qt.rgba(0.31, 0.62, 0.87, 0.45)
            font.pixelSize: 11
            horizontalAlignment: TextInput.AlignRight
            selectByMouse: true
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator {
                bottom: 0
                top: 100
            }
            // Not a binding: typing would break it. Follows the setting and
            // the drag whenever the field is not being edited.
            Component.onCompleted: text = String(Math.round(control.shown * 100))
            Connections {
                target: control
                function onShownChanged() {
                    if (!input.activeFocus)
                        input.text = String(Math.round(control.shown * 100));
                }
            }
            function accept() {
                var n = parseInt(text, 10);
                if (isNaN(n)) {
                    text = String(Math.round(control.value * 100));
                    return;
                }
                var v = control.clamp(n / 100);
                text = String(Math.round(v * 100));
                if (Math.abs(v - control.value) > 0.0001)
                    control.chosen(v);
            }
            onAccepted: accept()
            onActiveFocusChanged: if (!activeFocus)
                accept()
            Keys.onEscapePressed: {
                text = String(Math.round(control.value * 100));
                focus = false;
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: "%"
            color: Tone.c(palette, Theme.muted)
            font.pixelSize: 11
        }
    }
}
