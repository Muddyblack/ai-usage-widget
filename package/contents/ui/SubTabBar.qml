import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The "Usage / Stats" switch above a provider's content. Three tabs draw it
// (Claude, OpenAI, Copilot), so it lives here rather than three times over:
//   SubTabBar { accent: ...; currentId: tab.subTab; onSelected: tab.subTab = id }
Rectangle {
    id: bar

    property color accent: Kirigami.Theme.highlightColor
    property string currentId: ""
    // [{ id, label }] — the pair every caller uses today, overridable.
    property var tabs: [
        {
            id: "usage",
            label: i18n("Usage")
        },
        {
            id: "stats",
            label: i18n("Stats")
        }
    ]

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

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    font.pixelSize: 11
                    font.bold: parent.active
                    color: parent.active ? bar.accent : Kirigami.Theme.textColor
                    opacity: parent.active ? 1.0 : 0.6
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.selected(parent.modelData.id)
                }
            }
        }
    }
}
