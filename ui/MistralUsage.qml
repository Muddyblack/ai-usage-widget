pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    property var shell
    property var vibe: ({})
    readonly property color accent: "#ff7000"
    spacing: 12

    function tokens(value) {
        var n = Number(value) || 0;
        return n >= 1000000 ? (n / 1000000).toFixed(2) + "M" : n >= 1000 ? (n / 1000).toFixed(1) + "K" : String(n);
    }
    function cost(value) {
        return "$" + (Number(value) || 0).toFixed(4);
    }
    function age(start) {
        var stamp = Date.parse(start || "");
        if (!isFinite(stamp))
            return "";
        var hours = Math.max(0, Math.floor((Date.now() - stamp) / 3600000));
        return hours >= 24 ? shell.i18n("%1d ago", Math.floor(hours / 24)) : shell.i18n("%1h ago", hours);
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: spendBody.implicitHeight + 24
        radius: 10
        color: Qt.rgba(1, 0.44, 0, 0.10)
        border.color: Qt.rgba(1, 0.44, 0, 0.28)
        RowLayout {
            id: spendBody
            anchors.fill: parent
            anchors.margins: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: page.shell.i18n("TOTAL SPEND · VIBE CLI")
                    color: "#94a3b8"
                    font.pixelSize: 9
                    font.bold: true
                }
                Text {
                    text: page.cost(page.vibe.totalCost)
                    color: page.accent
                    font.pixelSize: 30
                    font.bold: true
                }
            }
            Text {
                Layout.alignment: Qt.AlignBottom
                text: page.shell.i18np("%1 session", "%1 sessions", page.vibe.sessionCount || 0) + "\n" + page.shell.i18n("%1 tokens", page.tokens(page.vibe.totalTokens))
                horizontalAlignment: Text.AlignRight
                color: "#b8c2d0"
                font.pixelSize: 11
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
            model: [
                {
                    label: page.shell.i18n("Input"),
                    value: page.tokens(page.vibe.promptTokens)
                },
                {
                    label: page.shell.i18n("Output"),
                    value: page.tokens(page.vibe.completionTokens)
                },
                {
                    label: page.shell.i18n("Steps"),
                    value: String(page.vibe.totalSteps || 0)
                },
                {
                    label: page.shell.i18n("Tool calls"),
                    value: String((page.vibe.toolOk || 0) + (page.vibe.toolFail || 0)),
                    failed: page.vibe.toolFail || 0
                }
            ]
            Rectangle {
                id: metric
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 44
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.04)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 2
                    Text {
                        text: metric.modelData.label
                        color: "#94a3b8"
                        font.pixelSize: 9
                    }
                    RowLayout {
                        Text {
                            text: metric.modelData.value
                            color: "#f8fafc"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        Text {
                            visible: (metric.modelData.failed || 0) > 0
                            text: page.shell.i18n("· %1 failed", metric.modelData.failed || 0)
                            color: "#f87171"
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Rectangle {
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: page.accent
        }
        Text {
            text: page.shell.i18n("RECENT SESSIONS")
            color: "#94a3b8"
            font.pixelSize: 9
            font.bold: true
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: page.shell.i18n("%1 of %2", (page.vibe.recent || []).length, page.vibe.sessionCount || 0)
            color: "#64748b"
            font.pixelSize: 9
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: recentColumn.implicitHeight + 8
        visible: (page.vibe.recent || []).length > 0
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        ColumnLayout {
            id: recentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 0
            Repeater {
                model: page.vibe.recent || []
                ColumnLayout {
                    id: session
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        visible: session.index > 0
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: page.shell.tr(session.modelData, "title")
                                elide: Text.ElideRight
                                color: "#e2e8f0"
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (session.modelData.project || "") + (session.modelData.branch ? "  ⎇ " + session.modelData.branch : "")
                                elide: Text.ElideRight
                                color: "#64748b"
                                font.pixelSize: 9
                            }
                        }
                        ColumnLayout {
                            spacing: 3
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: page.cost(session.modelData.cost)
                                color: page.accent
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: page.age(session.modelData.start)
                                color: "#64748b"
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: page.shell.i18n("Mistral has no billing API — figures come from local vibe CLI logs.")
        color: "#64748b"
        font.pixelSize: 9
        wrapMode: Text.WordWrap
    }
}
