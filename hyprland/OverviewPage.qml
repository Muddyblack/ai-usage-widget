import QtQuick
import QtQuick.Layouts
import "../package/contents/code/FeatureTabs.js" as FeatureTabs

// Hyprland / Windows Overview — every enabled provider's headline meter.
ColumnLayout {
    id: page

    property var shell
    spacing: 10

    readonly property var rows: {
        var out = [];
        var list = shell.providers || [];
        for (var i = 0; i < list.length; i++)
            out.push(list[i]);
        return out;
    }

    Text {
        visible: page.rows.length === 0
        Layout.fillWidth: true
        text: shell.i18n("Enable a provider in Settings to see it here.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: "#f8fafc"
        font.pixelSize: 11
    }

    Repeater {
        model: page.rows

        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 16
            radius: 8
            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            readonly property real pct: {
                var s = modelData.summary || {};
                return s.pct !== undefined && s.pct !== null ? Number(s.pct) : -1;
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    shell.activeId = modelData.id;
                    if (typeof shell.refreshTab === "function")
                        shell.refreshTab();
                }
            }

            RowLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.06)
                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: shell.providerIcon(modelData)
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        visible: status !== Image.Error && source !== ""
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: modelData.accent || "#38bdf8"
                        visible: parent.children[0].status === Image.Error || shell.providerIcon(modelData) === ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: modelData.label || modelData.id
                            font.bold: true
                            font.pixelSize: 12
                            color: "#f8fafc"
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: pct >= 0
                            text: Math.round(pct) + "%"
                            font.bold: true
                            font.pixelSize: 12
                            color: modelData.accent || "#38bdf8"
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.08)
                        visible: pct >= 0
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, pct / 100))
                            height: parent.height
                            radius: parent.radius
                            color: modelData.accent || "#38bdf8"
                        }
                    }
                    Text {
                        visible: ((modelData.summary && modelData.summary.detail) || "") !== ""
                        text: (modelData.summary && modelData.summary.detail) || ""
                        font.pixelSize: 10
                        opacity: 0.5
                        color: "#f8fafc"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
