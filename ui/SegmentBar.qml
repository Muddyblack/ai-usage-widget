import QtQuick
import QtQuick.Layouts

// A pill of mutually exclusive segments, drawn like the popup's Usage/Stats
// switch. Used for the settings sections and for Muse's Off/Local/Live choice,
// so both read as "pick one of these" rather than as a row of toggles.
Rectangle {
    id: bar

    property color accent: "#4f9dde"
    property string currentId: ""
    // [{ id, label }]
    property var tabs: []

    signal selected(string id)

    Layout.fillWidth: true
    Layout.preferredHeight: 26
    radius: 6
    color: Qt.rgba(1, 1, 1, 0.04)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.07)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 2

        Repeater {
            model: bar.tabs

            Rectangle {
                required property var modelData
                readonly property bool active: bar.currentId === modelData.id

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 5
                color: active ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.20) : "transparent"
                border.width: active ? 1 : 0
                border.color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.35)

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    text: parent.modelData.label
                    font.pixelSize: 10
                    font.bold: parent.active
                    color: parent.active ? bar.accent : "#f8fafc"
                    opacity: parent.active ? 1.0 : 0.6
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.selected(parent.modelData.id)
                }
            }
        }
    }
}
