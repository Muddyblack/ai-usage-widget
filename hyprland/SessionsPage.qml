import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QC
import "../package/contents/code/SessionSources.js" as SessionSources

ColumnLayout {
    id: page

    property var shell
    spacing: 10

    readonly property var sessions: shell.sessions || []
    readonly property bool loading: shell.sessionsLoading === true
    readonly property string errorText: shell.sessionsError || ""
    readonly property string notice: shell.sessionsNotice || ""
    property string filterText: ""
    readonly property string searchQuery: (filterText || "").trim()
    readonly property int sessionsTotal: shell.sessionsTotal || 0
    property double clockMs: Date.now()
    readonly property var sessionSources: shell.sessionsSources || []
    readonly property var selectedSourceIds: shell.sessionsSourceIds || []
    readonly property bool sourceSelectionIsAll: selectedSourceIds.length === 0
    readonly property var sourceOptions: {
        var options = [];
        if (page.sessionSources.length > 1)
            options.push({
                id: "",
                label: shell.i18n("All sources"),
                isAll: true
            });
        for (var i = 0; i < page.sessionSources.length; i++)
            options.push({
                id: page.sessionSources[i].id,
                label: page.sessionSources[i].label,
                isAll: false
            });
        return options;
    }
    readonly property string sourceSummary: {
        if (page.sessionSources.length === 0 || page.sourceSelectionIsAll) {
            if (page.sessionSources.length === 1)
                return page.sessionSources[0].label;
            return shell.i18n("All sources");
        }
        if (page.selectedSourceIds.length === 1) {
            for (var i = 0; i < page.sessionSources.length; i++)
                if (page.sessionSources[i].id === page.selectedSourceIds[0])
                    return page.sessionSources[i].label;
        }
        return page.shell.i18np("%1 source selected", "%1 sources selected", page.selectedSourceIds.length);
    }

    readonly property var displayedSessions: sessions

    function setSourceSelection(ids) {
        if (typeof shell.setSessionsSourceIds === "function")
            shell.setSessionsSourceIds(ids);
        if (typeof shell.querySessions === "function")
            shell.querySessions(page.searchQuery);
    }

    function toggleSource(id, checked) {
        if (page.sessionSources.length <= 1)
            return;
        page.setSourceSelection(SessionSources.toggled(page.selectedSourceIds, id, checked, page.sessionSources));
    }

    function reconcileDisplayedSessions() {
        if (typeof shell.reconcileSessions === "function")
            shell.reconcileSessions(page.searchQuery, page.selectedSourceIds);
        else if (typeof shell.refreshSessions === "function")
            shell.refreshSessions(page.searchQuery, undefined, false, page.selectedSourceIds);
    }

    function refreshDisplayedSessionsOnVisibility() {
        if (typeof shell.reconcileSessions === "function") {
            if (shell.sessionsViewVisible === true && shell.sessionsLoading !== true)
                shell.reconcileSessions(page.searchQuery, page.selectedSourceIds);
        } else if (typeof shell.refreshSessions === "function") {
            shell.refreshSessions(page.searchQuery, undefined, false, page.selectedSourceIds);
        }
    }

    onVisibleChanged: {
        if (visible) {
            clockMs = Date.now();
            page.refreshDisplayedSessionsOnVisibility();
        }
    }

    Timer {
        id: searchTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (typeof page.shell.querySessions === "function")
                page.shell.querySessions(page.searchQuery, undefined, false, page.selectedSourceIds);
            else if (typeof page.shell.refreshSessions === "function")
                page.shell.refreshSessions(page.searchQuery, undefined, false, page.selectedSourceIds);
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
            text: page.loading ? shell.i18n("Refreshing…") : shell.i18np("%1 local session", "%1 local sessions", page.sessionsTotal)
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
                    page.reconcileDisplayedSessions();
                }
            }
        }
    }

    RowLayout {
        visible: page.sessions.length > 0 || page.searchQuery !== "" || searchTimer.running || page.loading || page.sessionSources.length > 0
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
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
                placeholderText: page.shell.i18n("Search sessions…")
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.35)
                verticalAlignment: TextInput.AlignVCenter
                background: null
                selectByMouse: true
                Accessible.name: page.shell.i18n("Search sessions")
                onTextEdited: {
                    page.filterText = searchField.text;
                    if (typeof page.shell.setSessionsQuery === "function")
                        page.shell.setSessionsQuery(page.searchQuery);
                    searchTimer.restart();
                }
            }
        }

        SettingsButton {
            id: sourceSelectorButton
            visible: page.sessionSources.length > 0
            Layout.preferredWidth: 112
            Layout.minimumWidth: 78
            Layout.maximumWidth: 132
            text: page.sourceSummary
            Accessible.name: page.shell.i18n("Filter sessions by source")
            onClicked: sourcePopup.open()

            QC.Popup {
                id: sourcePopup
                x: Math.max(0, sourceSelectorButton.width - sourcePopup.width)
                y: sourceSelectorButton.height + 4
                width: Math.min(220, Math.max(150, page.width))
                padding: 6
                focus: true
                modal: false
                closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutside

                contentItem: ColumnLayout {
                    spacing: 0
                    Repeater {
                        model: page.sourceOptions
                        delegate: QC.CheckBox {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.label
                            checked: modelData.isAll ? page.sourceSelectionIsAll : (page.sourceSelectionIsAll || page.selectedSourceIds.indexOf(modelData.id) >= 0)
                            Accessible.name: modelData.label
                            onClicked: modelData.isAll ? page.setSourceSelection([]) : page.toggleSource(modelData.id, checked)
                        }
                    }
                }
            }
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
        visible: !page.loading && !searchTimer.running && page.searchQuery === "" && page.sessions.length === 0 && page.errorText === ""
        Layout.fillWidth: true
        text: shell.i18n("No local agent sessions found. They appear after Claude Code, Codex, Muse, Cline or Grok CLI records activity.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: "#f8fafc"
        font.pixelSize: 11
    }

    Text {
        visible: !page.loading && !searchTimer.running && page.searchQuery !== "" && page.sessions.length === 0 && page.errorText === ""
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
        visible: page.displayedSessions.length > 0
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
                model: page.displayedSessions

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
                                text: modelData.title || modelData.provider || shell.i18n("Session")
                                textFormat: Text.PlainText
                                font.bold: true
                                font.pixelSize: 12
                                color: "#f8fafc"
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: (modelData.sessionName || "") !== "" && modelData.sessionName !== modelData.title
                                text: modelData.sessionName || ""
                                textFormat: Text.PlainText
                                font.pixelSize: 10
                                opacity: 0.55
                                color: "#f8fafc"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: (modelData.detail || "") !== ""
                                text: modelData.detail || ""
                                textFormat: Text.PlainText
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
                            Image {
                                anchors.centerIn: parent
                                source: Qt.resolvedUrl("../package/contents/icons/session-terminal.svg")
                                sourceSize.width: 18
                                sourceSize.height: 18
                                width: 18
                                height: 18
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

    SettingsButton {
        visible: shell.sessionsHasMore === true
        Layout.fillWidth: true
        text: shell.i18n("Load more")
        enabled: !page.loading
        onClicked: {
            if (typeof shell.loadMoreSessions === "function")
                shell.loadMoreSessions();
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
