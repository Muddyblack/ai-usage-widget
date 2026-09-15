import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QC

ColumnLayout {
    id: page

    property var shell
    spacing: 10

    readonly property var sessions: shell.sessions || []
    readonly property bool loading: shell.sessionsLoading === true
    readonly property string errorText: shell.sessionsError || ""
    readonly property string notice: shell.sessionsNotice || ""
    property string filterText: ""
    property double clockMs: Date.now()

    // Client-side only: filters the already-fetched list by title, session
    // name, detail or provider id. No backend round-trip.
    readonly property var filteredSessions: {
        var q = (filterText || "").toLowerCase().trim();
        if (q === "")
            return sessions;
        return sessions.filter(function (s) {
            var hay = [s.title, s.sessionName, s.detail, s.provider].join(" ").toLowerCase();
            return hay.indexOf(q) !== -1;
        });
    }

    onVisibleChanged: {
        if (visible) {
            clockMs = Date.now();
            if (typeof shell.refreshSessions === "function")
                shell.refreshSessions();
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: page.visible && page.sessions.length > 0
        onTriggered: page.clockMs = Date.now()
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: shell.i18n("Sessions")
            font.bold: true
            font.pixelSize: 14
            color: "#f8fafc"
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            text: page.loading ? shell.i18n("Refreshing…") : shell.i18np("%1 local session", "%1 local sessions", page.sessions.length)
            font.pixelSize: 10
            opacity: 0.5
            color: "#f8fafc"
        }
        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 26
            radius: 6
            color: refreshMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "⟳"
                color: "#e2e8f0"
                font.pixelSize: 14
                opacity: refreshMouse.containsMouse ? 1 : 0.6
            }
            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof shell.refreshSessions === "function")
                        shell.refreshSessions();
                }
            }
        }
    }

    Rectangle {
        visible: page.sessions.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: searchField.activeFocus ? Qt.rgba(0.31, 0.62, 0.87, 0.6) : Qt.rgba(1, 1, 1, 0.12)

        QC.TextField {
            id: searchField
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            text: page.filterText
            font.pixelSize: 11
            color: "#f8fafc"
            placeholderText: shell.i18n("Search sessions…")
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
            verticalAlignment: TextInput.AlignVCenter
            background: null
            selectByMouse: true
            onTextEdited: page.filterText = text
        }
    }

    Text {
        visible: page.errorText !== ""
        Layout.fillWidth: true
        text: page.errorText
        wrapMode: Text.WordWrap
        color: "#f87171"
        font.pixelSize: 11
    }

    Text {
        visible: page.notice !== ""
        Layout.fillWidth: true
        text: page.notice
        wrapMode: Text.WordWrap
        opacity: 0.7
        color: "#f8fafc"
        font.pixelSize: 11
    }

    Text {
        visible: !page.loading && page.sessions.length === 0 && page.errorText === ""
        Layout.fillWidth: true
        text: shell.i18n("No local agent sessions found. They appear after Claude Code, Codex, Muse, Cline or Grok CLI records activity.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: "#f8fafc"
        font.pixelSize: 11
    }

    Text {
        visible: page.sessions.length > 0 && page.filteredSessions.length === 0
        Layout.fillWidth: true
        text: shell.i18n("No sessions match your search.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: "#f8fafc"
        font.pixelSize: 11
    }

    // Bounded and independently scrollable: the header above (title, count,
    // search) stays put instead of scrolling away with a long list — the
    // popup as a whole only grows to fit this box, not every row in it.
    Flickable {
        id: listFlick
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(360, listColumn.implicitHeight)
        visible: page.filteredSessions.length > 0
        clip: true
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        QC.ScrollBar.vertical: QC.ScrollBar {
            policy: listFlick.interactive ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
            width: 6
        }

        ColumnLayout {
            id: listColumn
            width: listFlick.width
            spacing: 10

            Repeater {
                model: page.filteredSessions

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: body.implicitHeight + 14
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    readonly property bool activeSession: modelData.state === "active" || modelData.state === "running"
                    readonly property color accent: {
                        var p = shell.providerById ? shell.providerById(modelData.provider) : null;
                        return (p && p.accent) ? p.accent : "#a78bfa";
                    }
                    readonly property bool hasFullTitle: (modelData.fullTitle || "") !== ""
                    property bool expanded: false

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.provider) {
                                shell.activeId = modelData.provider;
                                if (typeof shell.refreshTab === "function")
                                    shell.refreshTab();
                            }
                        }
                    }

                    RowLayout {
                        id: body
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: accent
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 4
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: expanded && hasFullTitle ? modelData.fullTitle : (modelData.title || modelData.provider || shell.i18n("Session"))
                                font.bold: true
                                font.pixelSize: 12
                                color: "#f8fafc"
                                elide: expanded ? Text.ElideNone : Text.ElideRight
                                wrapMode: expanded ? Text.WordWrap : Text.NoWrap
                                Layout.fillWidth: true

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: hasFullTitle
                                    cursorShape: hasFullTitle ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: expanded = !expanded
                                }
                            }
                            Text {
                                visible: (modelData.sessionName || "") !== "" && modelData.sessionName !== modelData.title
                                text: modelData.sessionName || ""
                                font.pixelSize: 10
                                opacity: 0.55
                                color: "#f8fafc"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: (modelData.detail || "") !== ""
                                text: modelData.detail || ""
                                font.pixelSize: 10
                                opacity: 0.45
                                color: "#f8fafc"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignTop
                            Text {
                                text: activeSession ? shell.i18n("Active") : shell.i18n("Idle")
                                font.bold: true
                                font.pixelSize: 11
                                color: activeSession ? accent : "#f8fafc"
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                            }
                            Text {
                                text: page.ageText(modelData.lastActivityAt)
                                font.pixelSize: 10
                                opacity: 0.45
                                color: "#f8fafc"
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        Rectangle {
                            visible: (modelData.openKey || "") !== ""
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignTop
                            radius: 6
                            color: resumeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "❯_"
                                color: "#e2e8f0"
                                font.family: "monospace"
                                font.bold: true
                                font.pixelSize: 11
                                opacity: resumeMouse.containsMouse ? 1 : 0.6
                            }
                            MouseArea {
                                id: resumeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof shell.openSession === "function")
                                        shell.openSession(modelData.openKey);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function ageText(epochSec) {
        var sec = Number(epochSec) || 0;
        if (sec <= 0)
            return "";
        var age = Math.max(0, (clockMs / 1000) - sec);
        if (age < 60)
            return shell.i18n("just now");
        if (age < 3600)
            return shell.i18np("%1 min ago", "%1 min ago", Math.floor(age / 60));
        if (age < 86400)
            return shell.i18np("%1 h ago", "%1 h ago", Math.floor(age / 3600));
        return shell.i18np("%1 d ago", "%1 d ago", Math.floor(age / 86400));
    }
}
