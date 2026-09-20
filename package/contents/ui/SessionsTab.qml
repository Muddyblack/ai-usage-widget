import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/FeatureTabs.js" as FeatureTabs
import "../code/Shell.js" as Shell
import "../code/SessionSources.js" as SessionSources

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
    property bool activeRefresh: false
    readonly property int sessionsLimit: 60
    property int sessionsTotal: 0
    property bool sessionsHasMore: false
    property int sessionsOffset: 0
    property int activeOffset: 0
    property bool activeAppend: false
    property double clockMs: Date.now()

    readonly property var displayedSessions: sessions || []
    property var sessionSources: []
    property var selectedSourceIds: []
    property string requestedSourceSignature: ""
    property string activeSourceSignature: ""
    property string sourceResetSignature: ""
    readonly property bool sourceSelectionIsAll: sessionsTab.selectedSourceIds.length === 0
    property var pendingSourceIds: []
    readonly property bool pendingSourceSelectionIsAll: sessionsTab.pendingSourceIds.length === 0
    readonly property var sourceOptions: {
        var options = [];
        if (sessionsTab.sessionSources.length > 1)
            options.push({
                id: "",
                label: i18n("All sources"),
                isAll: true
            });
        for (var i = 0; i < sessionsTab.sessionSources.length; i++)
            options.push({
                id: sessionsTab.sessionSources[i].id,
                label: sessionsTab.sessionSources[i].label,
                isAll: false
            });
        return options;
    }
    readonly property string sourceSummary: {
        if (sessionsTab.sessionSources.length === 0 || sessionsTab.sourceSelectionIsAll) {
            if (sessionsTab.sessionSources.length === 1)
                return sessionsTab.sessionSources[0].label;
            return i18n("All sources");
        }
        if (sessionsTab.selectedSourceIds.length === 1) {
            for (var i = 0; i < sessionsTab.sessionSources.length; i++)
                if (sessionsTab.sessionSources[i].id === sessionsTab.selectedSourceIds[0])
                    return sessionsTab.sessionSources[i].label;
        }
        return i18np("%1 source selected", "%1 sources selected", sessionsTab.selectedSourceIds.length);
    }

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

    function normalizeSources(raw) {
        return SessionSources.normalizeDescriptors(raw);
    }

    function normalizedSourceIds(ids, available) {
        return SessionSources.normalizeIds(ids, available);
    }

    function sourceSignature(ids) {
        return SessionSources.signature(ids);
    }

    function sourceSelectionHasStaleIds(available) {
        return SessionSources.hasStaleIds(sessionsTab.selectedSourceIds, available);
    }

    function setSourceSelection(ids) {
        var normalized = sessionsTab.normalizedSourceIds(ids, sessionsTab.sessionSources);
        if (sessionsTab.sourceSignature(normalized) === sessionsTab.sourceSignature(sessionsTab.selectedSourceIds))
            return;
        sessionsTab.selectedSourceIds = normalized;
        sessionsTab.sessionsOffset = 0;
        sessionsTab.sessionsTotal = 0;
        sessionsTab.sessionsHasMore = false;
        sessionsTab.queryOnly();
    }

    function stageSourceSelection(ids) {
        sessionsTab.pendingSourceIds = sessionsTab.normalizedSourceIds(ids, sessionsTab.sessionSources);
    }

    function stageToggleSource(id, checked) {
        if (sessionsTab.sessionSources.length <= 1)
            return;
        sessionsTab.stageSourceSelection(SessionSources.toggled(sessionsTab.pendingSourceIds, id, checked, sessionsTab.sessionSources));
    }

    function commitSourceSelection() {
        sessionsTab.setSourceSelection(sessionsTab.pendingSourceIds);
    }

    function toggleSource(id, checked) {
        if (sessionsTab.sessionSources.length <= 1)
            return;
        sessionsTab.setSourceSelection(SessionSources.toggled(sessionsTab.selectedSourceIds, id, checked, sessionsTab.sessionSources));
    }

    Timer {
        id: searchTimer
        interval: 300
        repeat: false
        onTriggered: sessionsTab.queryOnly()
    }

    Timer {
        interval: Math.max(30, rootItem.pollIntervalSec || 300) * 1000
        repeat: true
        running: sessionsTab.visible
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

    RowLayout {
        Layout.fillWidth: true
        visible: sessionsTab.sessions.length > 0 || sessionsTab.searchQuery !== "" || searchTimer.running || sessionsTab.loading || sessionsTab.sessionSources.length > 0
        spacing: 6

        QQC2.TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: i18n("Search sessions…")
            text: sessionsTab.filterText
            onTextChanged: sessionsTab.filterText = searchField.text
            Accessible.name: i18n("Search sessions")
        }

        PlasmaComponents.Button {
            id: sourceSelectorButton
            visible: sessionsTab.sessionSources.length > 0
            Layout.preferredWidth: 112
            Layout.minimumWidth: 78
            Layout.maximumWidth: 132
            text: sessionsTab.sourceSummary
            onClicked: sourcePopup.open()
            Accessible.name: i18n("Filter sessions by source")
            PlasmaComponents.ToolTip.text: i18n("Filter sessions by source")
            PlasmaComponents.ToolTip.visible: sourceSelectorButton.hovered

            QQC2.Popup {
                id: sourcePopup
                x: Math.max(0, sourceSelectorButton.width - sourcePopup.width)
                y: sourceSelectorButton.height + 4
                width: Math.min(220, Math.max(150, sessionsTab.width))
                height: Math.min(320, Math.max(1, sessionsTab.height - sourceSelectorButton.height - 8))
                padding: 6
                focus: true
                modal: false
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
                onOpened: sessionsTab.pendingSourceIds = sessionsTab.selectedSourceIds.slice(0)
                onClosed: sessionsTab.commitSourceSelection()

                contentItem: QQC2.ScrollView {
                    clip: true
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: sourcePopup.availableWidth
                        spacing: 0
                        Repeater {
                            model: sessionsTab.sourceOptions
                            delegate: QQC2.CheckBox {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData.label
                                checked: modelData.isAll ? sessionsTab.pendingSourceSelectionIsAll : (sessionsTab.pendingSourceSelectionIsAll || sessionsTab.pendingSourceIds.indexOf(modelData.id) >= 0)
                                Accessible.name: modelData.label
                                onClicked: modelData.isAll ? sessionsTab.stageSourceSelection([]) : sessionsTab.stageToggleSource(modelData.id, checked)
                            }
                        }
                    }
                }
            }
        }
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
                            PlasmaComponents.Label {
                                text: sessionsTab.sessionCostText(modelData)
                                font.pixelSize: 9
                                opacity: (modelData.costStatus || "unavailable") === "unavailable" ? 0.4 : 0.7
                                color: sessionsTab.sessionCostColor(modelData)
                                Layout.fillWidth: true
                                elide: Text.ElideRight
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

    function sessionCostText(entry) {
        var info = FeatureTabs.sessionCostInfo(entry);
        if (!info.available)
            return i18n("Cost unavailable");
        var cost = info.cost.toFixed(4);
        if (info.provenance === "actual")
            return info.status === "exact" ? i18n("Actual provider cost: $%1 (exact)", cost) : i18n("Actual provider cost: $%1 (partial)", cost);
        if (info.provenance === "estimated")
            return info.status === "exact" ? i18n("Calculated estimate: $%1 (exact)", cost) : i18n("Calculated estimate: $%1 (partial)", cost);
        if (info.provenance === "mixed")
            return info.status === "exact" ? i18n("Mixed cost: $%1 (exact)", cost) : i18n("Mixed cost: $%1 (partial)", cost);
        return info.status === "exact" ? i18n("Cost: $%1 (exact)", cost) : i18n("Cost: $%1 (partial)", cost);
    }

    function sessionCostColor(entry) {
        var info = FeatureTabs.sessionCostInfo(entry);
        if (!info.available)
            return Kirigami.Theme.textColor;
        if (info.status === "partial" || info.provenance === "mixed")
            return "#f5a623";
        if (info.provenance === "estimated")
            return FeatureTabs.accent("spend");
        if (info.status === "exact")
            return rootItem.tabColor(entry.provider || "");
        return Kirigami.Theme.textColor;
    }

    function requestSessions(offset, append, refreshMode) {
        requestSerial += 1;
        requestedQuery = searchQuery;
        requestedSourceSignature = sourceSignature(selectedSourceIds);
        activeQuery = requestedQuery;
        activeSourceSignature = requestedSourceSignature;
        activeRequestSerial = requestSerial;
        activeOffset = offset;
        activeAppend = append;
        activeRefresh = refreshMode === true;
        if (!append) {
            sessionsOffset = 0;
            sessionsTotal = 0;
            sessionsHasMore = false;
        }
        loading = true;
        errorText = "";
        notice = "";
        var mode = activeRefresh ? "--refresh" : "--query-only";
        var cmd = "cd " + Shell.quote(rootItem.scriptDir) + " && ./get-ai-usage --sessions " + mode + " --query " + Shell.quote(activeQuery);
        cmd += " --limit " + sessionsLimit + " --offset " + activeOffset;
        if (selectedSourceIds.length > 0)
            cmd += " --source " + Shell.quote(selectedSourceIds.join(","));
        activeCommand = cmd;
        sessionsSource.disconnectSource(cmd);
        sessionsSource.connectSource(cmd);
    }

    function refresh() {
        if (loading)
            return;
        requestSessions(0, false, true);
    }

    function queryOnly(offset, append) {
        requestSessions(offset === undefined ? 0 : offset, append === true, false);
    }

    function loadMore() {
        if (loading || !sessionsHasMore)
            return;
        queryOnly(sessionsOffset + sessionsLimit, true);
    }

    Plasma5Support.DataSource {
        id: sessionsSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            sessionsSource.disconnectSource(sourceName);
            var current = sourceName === sessionsTab.activeCommand && sessionsTab.activeRequestSerial === sessionsTab.requestSerial && sessionsTab.activeQuery === sessionsTab.requestedQuery;
            current = current && sessionsTab.activeSourceSignature === sessionsTab.requestedSourceSignature;
            if (!current)
                return;
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
                var responseSources = sessionsTab.normalizeSources(payload.sources);
                var staleSelection = sessionsTab.sourceSelectionHasStaleIds(responseSources);
                sessionsTab.sessionSources = responseSources;
                if (staleSelection) {
                    var staleSignature = sessionsTab.activeSourceSignature;
                    if (sessionsTab.sourceResetSignature === staleSignature)
                        return;
                    sessionsTab.selectedSourceIds = [];
                    sessionsTab.sourceResetSignature = staleSignature;
                    sessionsTab.sessions = [];
                    sessionsTab.sessionsOffset = 0;
                    sessionsTab.sessionsTotal = 0;
                    sessionsTab.sessionsHasMore = false;
                    sessionsTab.requestSessions(0, false, false);
                    return;
                }
                sessionsTab.sourceResetSignature = "";
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
