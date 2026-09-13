import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// "Where did the sessions go" — the busiest few repositories (Copilot) or
// workspaces (Muse). Same rows either way, so the caller supplies the heading
// and the accent:
//   StatsTopList { label: "Top repositories"; entries: …; accent: … }
ColumnLayout {
    id: topList

    // [{ name, sessions }], already sorted by the backend.
    property var entries: []
    property string label: ""
    property color accent: Kirigami.Theme.highlightColor

    Layout.fillWidth: true
    spacing: 3
    visible: entries.length > 0

    PlasmaComponents.Label {
        text: topList.label
        font.pixelSize: 9
        opacity: 0.45
        color: Kirigami.Theme.textColor
    }

    Repeater {
        model: topList.entries

        RowLayout {
            required property var modelData

            Layout.fillWidth: true
            spacing: 8

            PlasmaComponents.Label {
                text: parent.modelData.name
                font.pixelSize: 10
                opacity: 0.75
                color: Kirigami.Theme.textColor
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: i18np("1 session", "%1 sessions", Math.round(parent.modelData.sessions))
                font.pixelSize: 10
                color: topList.accent
            }
        }
    }
}
