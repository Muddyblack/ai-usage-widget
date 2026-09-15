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
            refresh();
        }
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
            text: sessionsTab.loading ? i18n("Refreshing…") : i18np("%1 local session", "%1 local sessions", sessionsTab.sessions.length)
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
        visible: sessionsTab.sessions.length > 0
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
        visible: !sessionsTab.loading && sessionsTab.sessions.length === 0 && sessionsTab.errorText === ""
        Layout.fillWidth: true
        text: i18n("No local agent sessions found. They appear after Claude Code, Codex, Muse, Cline or Grok CLI records activity.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: Kirigami.Theme.textColor
    }

    PlasmaComponents.Label {
        visible: sessionsTab.sessions.length > 0 && sessionsTab.filteredSessions.length === 0
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
        visible: sessionsTab.filteredSessions.length > 0
        clip: true
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: listColumn
            width: sessionsTab.width
            spacing: 10

            Repeater {
                model: sessionsTab.filteredSessions

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
                    readonly property bool hasFullTitle: (modelData.fullTitle || "") !== ""
                    property bool expanded: false

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
                                text: expanded && hasFullTitle ? modelData.fullTitle : (modelData.title || modelData.provider || i18n("Session"))
                                font.bold: true
                                font.pixelSize: 12
                                color: Kirigami.Theme.textColor
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
                            PlasmaComponents.Label {
                                visible: (modelData.sessionName || "") !== "" && modelData.sessionName !== modelData.title
                                text: modelData.sessionName || ""
                                font.pixelSize: 10
                                opacity: 0.55
                                color: Kirigami.Theme.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PlasmaComponents.Label {
                                visible: (modelData.detail || "") !== ""
                                text: modelData.detail || ""
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
                            icon.name: "utilities-terminal"
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

    function refresh() {
        if (loading)
            return;
        loading = true;
        errorText = "";
        notice = "";
        var cmd = "cd " + Shell.quote(rootItem.scriptDir) + " && ./get-ai-usage --sessions";
        sessionsSource.disconnectSource(cmd);
        sessionsSource.connectSource(cmd);
    }

    Plasma5Support.DataSource {
        id: sessionsSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            sessionsTab.loading = false;
            sessionsSource.disconnectSource(sourceName);
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
                sessionsTab.sessions = payload.sessions || [];
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
