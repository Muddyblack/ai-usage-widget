import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/Shell.js" as Shell

// Local agent sessions across Claude, Codex, Muse, Cline and Grok.
// Paths and transcripts never leave the backend.
ColumnLayout {
    id: sessionsTab
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "sessions" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 10

    property var sessions: []
    property bool loading: false
    property string errorText: ""
    property string notice: ""
    property string filterText: ""
    readonly property string searchQuery: (filterText || "").trim()
    property string requestedQuery: ""
    property string activeQuery: ""
    property string activeCommand: ""
    property int requestSerial: 0
    property int activeRequestSerial: 0
    readonly property int sessionsLimit: 60
    property int sessionsTotal: 0
    property bool sessionsHasMore: false
    property int sessionsOffset: 0
    property int activeOffset: 0
    property bool activeAppend: false
    property double clockMs: Date.now()

    readonly property var displayedSessions: sessions || []

    onVisibleChanged: {
        if (visible) {
            clockMs = Date.now();
            refresh();
        }
    }

    onFilterTextChanged: {
        var query = searchQuery;
        if (query !== requestedQuery) {
            requestedQuery = query;
            requestSerial += 1;
            sessionsOffset = 0;
            sessionsTotal = 0;
            sessionsHasMore = false;
        }
        searchTimer.restart();
    }

    Timer {
        id: searchTimer
        interval: 300
        repeat: false
        onTriggered: sessionsTab.refresh()
    }

    Timer {
        interval: 30000
        repeat: true
        running: sessionsTab.visible && sessionsTab.sessions.length > 0
        onTriggered: sessionsTab.clockMs = Date.now()
    }

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
            text: i18n("Sessions")
            font.bold: true
            font.pixelSize: 14
            color: Kirigami.Theme.textColor
        }
        Item {
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            text: sessionsTab.loading ? i18n("Refreshing…") : i18np("%1 local session", "%1 local sessions", sessionsTab.sessionsTotal)
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
        }
        PlasmaComponents.ToolButton {
            icon.name: "view-refresh"
            display: PlasmaComponents.AbstractButton.IconOnly
            onClicked: sessionsTab.refresh()
            enabled: !sessionsTab.loading
        }
    }

    QQC2.TextField {
        Layout.fillWidth: true
        visible: sessionsTab.sessions.length > 0 || sessionsTab.searchQuery !== "" || searchTimer.running || sessionsTab.loading
        placeholderText: i18n("Search sessions…")
        text: sessionsTab.filterText
        onTextChanged: sessionsTab.filterText = text
    }

    PlasmaComponents.Label {
        visible: sessionsTab.errorText !== ""
        Layout.fillWidth: true
        text: sessionsTab.errorText
        wrapMode: Text.WordWrap
        color: rootItem.dangerColor
        font.pixelSize: 11
    }

    PlasmaComponents.Label {
        visible: sessionsTab.notice !== ""
        Layout.fillWidth: true
        text: sessionsTab.notice
        wrapMode: Text.WordWrap
        opacity: 0.6
        color: Kirigami.Theme.textColor
        font.pixelSize: 11
    }

    PlasmaComponents.Label {
        visible: !sessionsTab.loading && !searchTimer.running && sessionsTab.searchQuery === "" && sessionsTab.sessions.length === 0 && sessionsTab.errorText === ""
        Layout.fillWidth: true
        text: i18n("No local agent sessions found. They appear after Claude Code, Codex, Muse, Cline or Grok CLI records activity.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: Kirigami.Theme.textColor
    }

    PlasmaComponents.Label {
        visible: !sessionsTab.loading && !searchTimer.running && sessionsTab.searchQuery !== "" && sessionsTab.sessions.length === 0 && sessionsTab.errorText === ""
        Layout.fillWidth: true
        text: i18n("No sessions match your search.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: Kirigami.Theme.textColor
    }

    // Bounded and independently scrollable: the header above (title, count,
    // search) stays put instead of scrolling away with a long list — the
    // popup as a whole only grows to fit this box, not every row in it.
    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(360, listColumn.implicitHeight)
        visible: sessionsTab.displayedSessions.length > 0
        clip: true
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: listColumn
            width: sessionsTab.width
            spacing: 10

            Repeater {
                model: sessionsTab.displayedSessions

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: body.implicitHeight + 14
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    readonly property bool activeSession: modelData.state === "active" || modelData.state === "running"
                    readonly property color accent: rootItem.tabColor(modelData.provider || "")

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
                            PlasmaComponents.Label {
                                text: modelData.title || modelData.provider || i18n("Session")
                                textFormat: Text.PlainText
                                font.bold: true
                                font.pixelSize: 12
                                color: Kirigami.Theme.textColor
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                Layout.fillWidth: true
                            }
                            PlasmaComponents.Label {
                                visible: (modelData.sessionName || "") !== "" && modelData.sessionName !== modelData.title
                                text: modelData.sessionName || ""
                                textFormat: Text.PlainText
                                font.pixelSize: 10
                                opacity: 0.55
                                color: Kirigami.Theme.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PlasmaComponents.Label {
                                visible: (modelData.detail || "") !== ""
                                text: modelData.detail || ""
                                textFormat: Text.PlainText
                                font.pixelSize: 10
                                opacity: 0.45
                                color: Kirigami.Theme.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignTop
                            PlasmaComponents.Label {
                                text: activeSession ? i18n("Active") : i18n("Idle")
                                font.bold: true
                                font.pixelSize: 11
                                color: activeSession ? accent : Kirigami.Theme.textColor
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                            }
                            PlasmaComponents.Label {
                                text: sessionsTab.ageText(modelData.lastActivityAt)
                                font.pixelSize: 10
                                opacity: 0.45
                                color: Kirigami.Theme.textColor
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        PlasmaComponents.ToolButton {
                            visible: (modelData.openKey || "") !== ""
                            icon.source: Qt.resolvedUrl("../icons/session-terminal.svg")
                            icon.color: Kirigami.Theme.textColor
                            icon.width: 18
                            icon.height: 18
                            Layout.alignment: Qt.AlignTop
                            display: PlasmaComponents.AbstractButton.IconOnly
                            text: i18n("Resume session")
                            PlasmaComponents.ToolTip.text: text
                            PlasmaComponents.ToolTip.visible: hovered
                            onClicked: sessionsTab.openSession(modelData.openKey)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.provider)
                                rootItem.selectTab(modelData.provider);
                        }
                    }
                }
            }
        }
    }

    PlasmaComponents.Button {
        visible: sessionsTab.sessionsHasMore
        Layout.fillWidth: true
        text: i18n("Load more")
        implicitHeight: 26
        font.pixelSize: 10
        enabled: !sessionsTab.loading
        onClicked: sessionsTab.loadMore()
    }

    function ageText(epochSec) {
        var sec = Number(epochSec) || 0;
        if (sec <= 0)
            return "";
        var age = Math.max(0, (clockMs / 1000) - sec);
        if (age < 60)
            return i18n("just now");
        if (age < 3600)
            return i18np("%1 min ago", "%1 min ago", Math.floor(age / 60));
        if (age < 86400)
            return i18np("%1 h ago", "%1 h ago", Math.floor(age / 3600));
        return i18np("%1 d ago", "%1 d ago", Math.floor(age / 86400));
    }

    function requestSessions(offset, append) {
        requestSerial += 1;
        requestedQuery = searchQuery;
        activeQuery = requestedQuery;
        activeRequestSerial = requestSerial;
        activeOffset = offset;
        activeAppend = append;
        if (!append) {
            sessionsOffset = 0;
            sessionsTotal = 0;
            sessionsHasMore = false;
        }
        loading = true;
        errorText = "";
        notice = "";
        var cmd = "cd " + Shell.quote(rootItem.scriptDir) + " && ./get-ai-usage --sessions --query " + Shell.quote(activeQuery);
        cmd += " --limit " + sessionsLimit + " --offset " + activeOffset;
        activeCommand = cmd;
        sessionsSource.disconnectSource(cmd);
        sessionsSource.connectSource(cmd);
    }

    function refresh() {
        if (loading)
            return;
        requestSessions(0, false);
    }

    function loadMore() {
        if (loading || !sessionsHasMore)
            return;
        requestSessions(sessionsOffset + sessionsLimit, true);
    }

    Plasma5Support.DataSource {
        id: sessionsSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            sessionsSource.disconnectSource(sourceName);
            var current = sourceName === sessionsTab.activeCommand && sessionsTab.activeRequestSerial === sessionsTab.requestSerial && sessionsTab.activeQuery === sessionsTab.requestedQuery;
            if (!current) {
                if (sessionsTab.activeRequestSerial < sessionsTab.requestSerial) {
                    sessionsTab.loading = false;
                    searchTimer.restart();
                }
                return;
            }
            sessionsTab.loading = false;
            var stdout = (data && data.stdout) ? data.stdout : "";
            // Plasma's executable DataSource reports the exit status under the
            // key "exit code" (with a space) — dot-access (data.exitCode)
            // silently returns undefined, which always failed this check.
            var exitCode = data ? Number(data["exit code"]) : 1;
            if (exitCode !== 0) {
                sessionsTab.errorText = i18n("Could not load sessions.");
                return;
            }
            try {
                var payload = JSON.parse(stdout);
                var page = payload.sessions || [];
                sessionsTab.sessionsTotal = Number(payload.total) || 0;
                sessionsTab.sessionsOffset = Number(payload.offset) || sessionsTab.activeOffset;
                sessionsTab.sessionsHasMore = payload.hasMore === true;
                sessionsTab.sessions = sessionsTab.activeAppend ? sessionsTab.sessions.concat(page) : page;
            } catch (e) {
                sessionsTab.errorText = i18n("Could not parse sessions.");
            }
        }
    }

    // Rows with an empty openKey (Muse) render no button at all.
    function openSession(key) {
        if (!key)
            return;
        notice = "";
        var cmd = "cd " + Shell.quote(rootItem.scriptDir) + " && ./get-ai-usage --open-session " + Shell.quote(key);
        openSessionSource.disconnectSource(cmd);
        openSessionSource.connectSource(cmd);
    }

    Plasma5Support.DataSource {
        id: openSessionSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            openSessionSource.disconnectSource(sourceName);
            var stdout = (data && data.stdout) ? data.stdout : "";
            try {
                var payload = JSON.parse(stdout);
                sessionsTab.notice = payload.message || "";
            } catch (e) {
                sessionsTab.notice = i18n("Could not resume session.");
            }
        }
    }
}
