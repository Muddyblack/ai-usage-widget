import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Compact panel readout: icon + optional spark-line + animated % / cost text.
RowLayout {
    id: slot

    property real pct: 0
    property color iconColor: "#cc785c"
    property bool stale: false
    property string tooltipText: ""
    property bool showCost: false
    property string costText: ""
    property string iconSource: ""
    property string iconText: "AI"
    // When set to a visible colour the brand logo is flattened to it, so the
    // session and weekly slots of one provider can be told apart at a glance.
    property color iconTint: "transparent"
    readonly property bool tinted: slot.iconTint.a > 0
    // Optional mini-trend series ({t,v}) drawn as a spark-line behind the readout
    property var spark: []
    // usage-level thresholds (kept local so this component is self-contained)
    readonly property color dangerColor: "#ff4d4d"
    readonly property color warningColor: "#ffa64d"
    // Animated value that eases toward `pct` so the readout rolls up/down
    property real displayPct: 0

    onPctChanged: displayPct = pct
    Component.onCompleted: displayPct = pct
    spacing: 5
    opacity: stale ? 0.55 : 1

    MouseArea {
        id: slotHover

        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true

        // Plasma's tooltip rather than QQC2's: it is anchored above the item and
        // sizes its wrapped label itself, so a multi-line tooltip next to a
        // panel edge is no longer clipped at the bottom. QQC2's popped up at the
        // cursor and let the panel cover its last lines.
        PlasmaComponents.ToolTip {
            visible: slotHover.containsMouse && slot.tooltipText !== ""
            text: slot.tooltipText
            delay: 500
            timeout: -1
        }
    }

    Item {
        width: 18
        height: 18
        Layout.alignment: Qt.AlignVCenter

        Image {
            id: providerIcon

            anchors.centerIn: parent
            width: 17
            height: 17
            source: slot.iconSource
            sourceSize.width: 34
            sourceSize.height: 34
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: slot.iconSource !== "" && status !== Image.Error && !slot.tinted
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 17
            height: 17
            source: slot.iconSource
            isMask: true
            color: slot.iconTint
            visible: slot.iconSource !== "" && slot.tinted
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(17, fallbackLabel.implicitWidth + 7)
            height: 16
            radius: 4
            color: Qt.rgba(slot.iconColor.r, slot.iconColor.g, slot.iconColor.b, 0.18)
            border.width: 1
            border.color: Qt.rgba(slot.iconColor.r, slot.iconColor.g, slot.iconColor.b, 0.55)
            visible: slot.iconSource === "" || providerIcon.status === Image.Error

            PlasmaComponents.Label {
                id: fallbackLabel

                anchors.centerIn: parent
                text: slot.iconText
                font.pixelSize: slot.iconText.length > 2 ? 8 : 9
                font.bold: true
                color: slot.iconColor
            }
        }
    }

    PlasmaComponents.Label {
        text: slot.showCost ? slot.costText : Math.round(slot.displayPct) + "%"
        font.pixelSize: 12
        font.bold: true
        color: slot.showCost ? slot.iconColor : (slot.pct >= 90 ? slot.dangerColor : slot.pct >= 70 ? slot.warningColor : Kirigami.Theme.textColor)
        Layout.alignment: Qt.AlignVCenter
    }

    Behavior on displayPct {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 300
        }
    }
}
