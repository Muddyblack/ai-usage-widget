import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "js/PanelColor.js" as PanelColor
import "js/Tone.js" as Tone

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
    // The normal-level text colour; a host on a light panel passes its theme's.
    property color textColor: "#f8fafc"
    property color surfaceColor: "#10141c"
    readonly property color readableIcon: Tone.onSurface(iconColor, surfaceColor)
    readonly property bool lightSurface: surfaceColor.hslLightness > 0.5

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
            colorizationColor: slot.readableIcon
            opacity: 0.22
        }

        Image {
            id: coreIcon
            anchors.centerIn: parent
            width: 12
            height: 12
            source: slot.iconSource
            sourceSize.width: 24
            sourceSize.height: 24
            visible: false
        }
        MultiEffect {
            anchors.fill: coreIcon
            source: coreIcon
            colorization: 1
            colorizationColor: slot.readableIcon
        }
    }

    Text {
        text: slot.costText !== "" ? slot.costText : Math.round(slot.displayPct) + "%"
        font.pixelSize: 12
        font.bold: true
        color: {
            if (slot.lightSurface && slot.costText === "") {
                var level = PanelColor.level(slot.pct);
                if (level === "danger")
                    return "#c62828";
                if (level === "warning")
                    return "#c2410c";
            }
            return Tone.onSurface(slot.costText !== "" ? slot.iconColor : PanelColor.colorFor(slot.pct, slot.textColor), slot.surfaceColor);
        }
        Layout.alignment: Qt.AlignVCenter
    }
}
