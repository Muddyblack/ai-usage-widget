import QtQuick
import QtQuick.Layouts
import "js/Tone.js" as Tone

// The Remote tab of a provider whose app can be driven from another device
// (Antigravity 2's Remote Control, Claude Code's /remote-control). The
// provider supplies the state, the wording and the address to open
// (see contract.remote_info), so this page carries none of it.
ColumnLayout {
    id: remotePage

    property var remote: ({})
    property color accent: "#4285f4"
    property var shell

    readonly property string state: (remote && remote.state) || "off"
    readonly property string url: (remote && remote.url) || ""
    readonly property var instances: (remote && remote.instances) || []
    readonly property color stateColor: state === "online" ? "#34a853" : (state === "offline" ? "#fbbc04" : "#94a3b8")

    Layout.fillWidth: true
    spacing: 12

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: stateRow.implicitHeight + 24
        radius: 8
        color: Tone.c(palette, Qt.rgba(1, 1, 1, 0.03))
        border.width: 1
        border.color: Tone.c(palette, Qt.rgba(1, 1, 1, 0.07))

        RowLayout {
            id: stateRow
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                radius: 5
                color: remotePage.stateColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: (remotePage.remote && remotePage.remote.title) || ""
                    font.pixelSize: 13
                    font.bold: true
                    color: Tone.c(palette, "#f8fafc")
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: (remotePage.remote && remotePage.remote.detail) || ""
                    font.pixelSize: 11
                    color: Tone.c(palette, "#94a3b8")
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Repeater {
        model: remotePage.instances

        Rectangle {
            id: row

            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 8
            color: Tone.c(palette, Qt.rgba(1, 1, 1, rowArea.containsMouse ? 0.06 : 0.03))
            border.width: 1
            border.color: Tone.c(palette, Qt.rgba(1, 1, 1, 0.07))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: row.modelData.state === "busy" ? "#fbbc04" : "#34a853"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.pixelSize: 12
                        font.bold: true
                        color: Tone.c(palette, "#f8fafc")
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: (row.modelData.detail || "") + (row.modelData.state === "busy" ? "  ·  " + remotePage.shell.i18n("working") : "")
                        font.pixelSize: 10
                        color: Tone.c(palette, "#94a3b8")
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: "↗"
                    font.pixelSize: 13
                    color: remotePage.accent
                }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(row.modelData.url)
            }
        }
    }

    Rectangle {
        visible: remotePage.url !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        radius: 6
        color: Qt.rgba(remotePage.accent.r, remotePage.accent.g, remotePage.accent.b, openArea.containsMouse ? 0.30 : 0.20)
        border.width: 1
        border.color: Qt.rgba(remotePage.accent.r, remotePage.accent.g, remotePage.accent.b, 0.35)

        Text {
            anchors.centerIn: parent
            text: (remotePage.remote && remotePage.remote.openLabel) || ""
            font.pixelSize: 11
            font.bold: true
            color: remotePage.accent
        }

        MouseArea {
            id: openArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(remotePage.url)
        }
    }

    Text {
        visible: text !== ""
        Layout.fillWidth: true
        text: (remotePage.remote && remotePage.remote.note) || ""
        font.pixelSize: 10
        color: Tone.c(palette, "#64748b")
        wrapMode: Text.WordWrap
    }
}
