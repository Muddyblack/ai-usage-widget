import QtQuick
import QtQuick.Layouts

// The panel item. Mirrors the Plasma compact representation: one PanelSlot per
// usage window (e.g. Claude 5h | 7d), separated by thin dividers, plus a
// blinking error dot. A translucent pill background stands in for the panel
// frame Plasma provides.
Rectangle {
    id: pill

    property string iconSource: ""
    // [{pct, color, text?, tooltip?}] from the backend's provider.slots
    property var slots: []
    property bool stale: false
    property bool hasError: false
    property bool active: false      // popup open → keep the hover tint

    signal clicked

    readonly property color dangerColor: "#ff4d4d"
    readonly property bool hovered: mouse.containsMouse
    // Combined slot tooltips; the shell shows these in a hover popup since the
    // QQC2 ToolTip style isn't available under Quickshell.
    readonly property string tooltipText: {
        var lines = [];
        for (var i = 0; i < pill.slots.length; i++) {
            var t = pill.slots[i].tooltip;
            if (t !== undefined && t !== "")
                lines.push(t);
        }
        return lines.join("\n");
    }

    // Stable floor + animated width so a provider/error swap (fewer slots →
    // narrower content) doesn't make the right-anchored pill jump sideways.
    implicitWidth: Math.max(96, row.implicitWidth + 20)
    implicitHeight: 30
    radius: 8

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
    color: mouse.containsMouse || active ? Qt.rgba(0.10, 0.11, 0.14, 0.92) : Qt.rgba(0.06, 0.07, 0.09, 0.86)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            visible: pill.hasError
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: pill.dangerColor
            Layout.alignment: Qt.AlignVCenter
            SequentialAnimation on opacity {
                running: pill.hasError
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.3
                    duration: 800
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1.0
                    duration: 800
                    easing.type: Easing.InOutSine
                }
            }
        }

        Repeater {
            model: pill.slots

            RowLayout {
                required property var modelData
                required property int index
                spacing: 8

                PanelSlot {
                    pct: modelData.pct !== undefined ? modelData.pct : 0
                    iconColor: modelData.color !== undefined ? modelData.color : "#cc785c"
                    costText: modelData.text !== undefined ? modelData.text : ""
                    stale: pill.stale
                    iconSource: pill.iconSource
                }

                Rectangle {
                    visible: index < pill.slots.length - 1
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 14
                    color: Qt.rgba(1, 1, 1, 0.16)
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
