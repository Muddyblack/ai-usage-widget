import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Compact panel readout, mirroring the Plasma PanelSlot: layered tinted icon +
// animated % (or cost text) that rolls up/down when the value changes.
RowLayout {
    id: slot

    property real pct: 0
    property color iconColor: "#cc785c"
    property bool stale: false
    property string costText: ""    // when non-empty, shown instead of the %
    // The provider's brand logo, colorized to `iconColor` — as in the Plasma
    // compact representation, the panel reads severity from the icon's colour,
    // so the logo contributes its shape and the backend its colour.
    property string iconSource: ""

    readonly property color dangerColor: "#ff4d4d"
    readonly property color warningColor: "#ffa64d"

    property real displayPct: 0
    onPctChanged: displayPct = pct
    Component.onCompleted: displayPct = pct
    Behavior on displayPct {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    spacing: 5
    opacity: stale ? 0.55 : 1.0
    Behavior on opacity {
        NumberAnimation {
            duration: 300
        }
    }

    Item {
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        Layout.alignment: Qt.AlignVCenter

        Image {
            id: haloIcon
            anchors.centerIn: parent
            width: 16
            height: 16
            source: slot.iconSource
            sourceSize.width: 16
            sourceSize.height: 16
            visible: false
        }
        MultiEffect {
            anchors.fill: haloIcon
            source: haloIcon
            colorization: 1
            colorizationColor: slot.iconColor
            opacity: 0.22
        }

        Image {
            id: coreIcon
            anchors.centerIn: parent
            width: 12
            height: 12
            source: slot.iconSource
            sourceSize.width: 12
            sourceSize.height: 12
            visible: false
        }
        MultiEffect {
            anchors.fill: coreIcon
            source: coreIcon
            colorization: 1
            colorizationColor: slot.iconColor
        }
    }

    Text {
        text: slot.costText !== "" ? slot.costText : Math.round(slot.displayPct) + "%"
        font.pixelSize: 12
        font.bold: true
        color: slot.costText !== "" ? slot.iconColor : (slot.pct >= 90 ? slot.dangerColor : slot.pct >= 70 ? slot.warningColor : "#f8fafc")
        Layout.alignment: Qt.AlignVCenter
    }
}
