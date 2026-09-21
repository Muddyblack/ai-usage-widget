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
    property int sessionsOffset: 0
    property int activeOffset: 0
    property double clockMs: Date.now()
    readonly property int totalPages: Math.max(1, Math.ceil(sessionsTotal / sessionsLimit))
    readonly property int currentPage: Math.min(totalPages, Math.max(1, Math.floor(sessionsOffset / sessionsLimit) + 1))

    function paginationItems(current, total) {
        if (total <= 1)
            return [];
        if (total <= 7) {
            var items = [];
            for (var i = 1; i <= total; i++)
                items.push(i);
            return items;
        }
        if (current <= 4)
            return [1, 2, 3, 4, 5, "…", total];
        if (current >= total - 3)
            return [1, "…", total - 4, total - 3, total - 2, total - 1, total];
        return [1, "…", current - 1, current, current + 1, "…", total];
    }

    function goToPage(pageNumber) {
        if (loading)
            return;
        var p = Math.max(1, Math.min(pageNumber, totalPages));
        var targetOffset = (p - 1) * sessionsLimit;
        if (targetOffset === sessionsOffset && sessions.length > 0)
            return;
        sessionsList.positionViewAtBeginning();
        queryOnly(targetOffset);
    }

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

    function sourceIcon(id) {
        if (!id)
            return Qt.resolvedUrl("../icons/org.muddyblack.aiUsageWidget.svg");
        var dir = Qt.resolvedUrl("../icons/");
        if (id === "codex")
            return dir + "codex.svg";
        if (id === "opencode")
            return dir + "opencode-color.svg";
        var icon = rootItem.tabIcon ? rootItem.tabIcon(id) : "";
        if (icon)
            return icon;
        var fileMap = {
            "claude": "claude-color.svg",
            "antigravity": "antigravity-color.svg",
            "openai": "codex.svg",
            "cline": "cline.svg",
            "muse": "muse-color.svg",
            "grok": "grok.svg",
            "cursor": "cursor.svg",
            "copilot": "githubcopilot.svg",
            "kimi": "kimi.svg",
            "kiro": "kiro.svg",
            "deepseek": "deepseek-color.svg",
            "mistral": "mistral-color.svg",
            "openrouter": "openrouter.svg",
            "zai": "zai.svg"
        };
        if (fileMap[id])
            return dir + fileMap[id];
        return "";
    }

    function sourceColor(id) {
        if (!id)
            return "#a78bfa";
        var p = rootItem.providerById ? rootItem.providerById(id) : null;
        if (p && p.accent)
            return p.accent;
        if (rootItem.tabColor) {
            var col = rootItem.tabColor(id);
            if (col && col !== "")
                return col;
        }
        var colorMap = {
            "claude": "#cc785c",
            "antigravity": "#4285f4",
            "openai": "#10a37f",
            "codex": "#10a37f",
            "cline": "#007acc",
            "muse": "#0064e0",
            "grok": "#ef4444",
            "opencode": "#B7B1B1",
            "cursor": "#e6e6e6",
            "copilot": "#8b5cf6",
            "kimi": "#1e3a8a",
            "kiro": "#8b5cf6",
            "deepseek": "#4f8cff",
            "mistral": "#ff7000",
            "openrouter": "#9333ea",
            "zai": "#126ef4"
        };
        return colorMap[id] || "#a78bfa";
    }

    onVisibleChanged: {
        if (visible)
            clockMs = Date.now();
    }

    onFilterTextChanged: {
        var query = searchQuery;
        if (query !== requestedQuery) {
            requestedQuery = query;
            requestSerial += 1;
            sessionsOffset = 0;
            sessionsTotal = 0;
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
        // Fires the moment the tab becomes visible, including the very first
        // time. onVisibleChanged cannot cover that: when the popup opens
        // straight onto Sessions the property is already true at creation, so
        // it never changes and the list sat empty until a manual refresh.
        triggeredOnStart: true
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
            Layout.preferredWidth: 124
            Layout.minimumWidth: 86
            Layout.maximumWidth: 145
            text: sessionsTab.sourceSummary + "  ▾"
            onClicked: sourcePopup.open()
            Accessible.name: i18n("Filter sessions by source")
            PlasmaComponents.ToolTip.text: i18n("Filter sessions by source")
            PlasmaComponents.ToolTip.visible: sourceSelectorButton.hovered

            QQC2.Popup {
                id: sourcePopup
                x: Math.max(-sourceSelectorButton.x, sourceSelectorButton.width - sourcePopup.width)
                y: sourceSelectorButton.height + 4
                width: 204
                height: Math.min(320, popupCol.implicitHeight + 16)
                padding: 6
                focus: true
                modal: false
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
                onOpened: sessionsTab.pendingSourceIds = sessionsTab.selectedSourceIds.slice(0)
                onClosed: sessionsTab.commitSourceSelection()

                background: Rectangle {
                    radius: 10
                    color: Qt.rgba(0.08, 0.09, 0.12, 0.98)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 1
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.12)
                        radius: 10
                    }
                }

                contentItem: QQC2.ScrollView {
                    clip: true
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                        width: 6
                        policy: QQC2.ScrollBar.AsNeeded
                    }

                    ColumnLayout {
                        id: popupCol
                        width: sourcePopup.availableWidth
                        spacing: 2

                        Repeater {
                            model: sessionsTab.sourceOptions

                            delegate: ColumnLayout {
                                id: itemCol
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0

                                Rectangle {
                                    id: itemRow
                                    Layout.fillWidth: true
                                    height: 30
                                    radius: 6
                                    color: itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                                    readonly property bool isChecked: modelData.isAll ? sessionsTab.pendingSourceSelectionIsAll : (sessionsTab.pendingSourceSelectionIsAll || sessionsTab.pendingSourceIds.indexOf(modelData.id) >= 0)
                                    readonly property color accent: sessionsTab.sourceColor(modelData.id)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 120
                                        }
                                    }

                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.isAll ? sessionsTab.stageSourceSelection([]) : sessionsTab.stageToggleSource(modelData.id, !itemRow.isChecked)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        // Custom styled checkbox
                                        Rectangle {
                                            Layout.preferredWidth: 16
                                            Layout.preferredHeight: 16
                                            radius: 4
                                            color: itemRow.isChecked ? Qt.rgba(itemRow.accent.r, itemRow.accent.g, itemRow.accent.b, 0.22) : "transparent"
                                            border.width: itemRow.isChecked ? 1.5 : 1
                                            border.color: itemRow.isChecked ? itemRow.accent : Qt.rgba(1, 1, 1, 0.25)

                                            Text {
                                                anchors.centerIn: parent
                                                visible: itemRow.isChecked
                                                text: "✓"
                                                font.pixelSize: 10
                                                font.bold: true
                                                color: itemRow.accent
                                            }
                                        }

                                        // Provider Icon
                                        Image {
                                            id: srcIcon
                                            Layout.preferredWidth: 14
                                            Layout.preferredHeight: 14
                                            sourceSize.width: 14
                                            sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            source: sessionsTab.sourceIcon(modelData.id)
                                            visible: source !== "" && status !== Image.Error
                                            opacity: itemRow.isChecked ? 1.0 : 0.55
                                        }

                                        // Fallback dot if no icon
                                        Rectangle {
                                            visible: !srcIcon.visible
                                            Layout.preferredWidth: 8
                                            Layout.preferredHeight: 8
                                            radius: 4
                                            color: itemRow.accent
                                            opacity: itemRow.isChecked ? 1.0 : 0.55
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.pixelSize: 11
                                            font.bold: modelData.isAll && itemRow.isChecked
                                            color: itemRow.isChecked ? Kirigami.Theme.textColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.65)
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                // Subtle divider below "All sources"
                                Rectangle {
                                    visible: modelData.isAll
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    Layout.bottomMargin: 4
                                    height: 1
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                }
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
    ListView {
        id: sessionsList
        Layout.fillWidth: true
        Layout.rightMargin: 8
        // Bound by contentHeight, never by the delegates' own layout, so the
        // popup cannot grow past the cap no matter how many rows a page holds.
        Layout.preferredHeight: Math.min(360, contentHeight)
        visible: sessionsTab.displayedSessions.length > 0
        clip: true
        spacing: 10
        model: sessionsTab.displayedSessions
        boundsBehavior: Flickable.StopAtBounds
        // A full page keeps the wheel here; a short one lets it through to the
        // popup instead of swallowing it against an unscrollable list.
        interactive: contentHeight > height
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            id: verticalScrollBar
            policy: QQC2.ScrollBar.AsNeeded
            width: 12
            contentItem: Rectangle {
                implicitWidth: 6
                implicitHeight: 32
                radius: 3
                color: Kirigami.Theme.textColor
                opacity: verticalScrollBar.pressed ? 0.6 : (verticalScrollBar.hovered ? 0.45 : 0.25)
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }
            background: Rectangle {
                implicitWidth: 12
                color: Kirigami.Theme.textColor
                opacity: verticalScrollBar.hovered ? 0.08 : 0.04
                radius: 6
            }
        }

        delegate: Rectangle {
            required property var modelData
            width: sessionsList.width - (verticalScrollBar.visible ? (verticalScrollBar.width + 4) : 0)
            height: body.implicitHeight + 14
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

    RowLayout {
        id: paginationRow
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: sessionsTab.totalPages > 1 && sessionsTab.displayedSessions.length > 0
        spacing: 4

        Item {
            Layout.fillWidth: true
        }

        Rectangle {
            id: prevBtn
            implicitWidth: 26
            implicitHeight: 26
            radius: 6
            readonly property bool enabled: !sessionsTab.loading && sessionsTab.currentPage > 1
            color: prevMouse.containsMouse && enabled ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            opacity: enabled ? 1.0 : 0.35

            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: "‹"
                font.pixelSize: 14
                font.bold: true
                color: Kirigami.Theme.textColor
            }

            MouseArea {
                id: prevMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: prevBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (prevBtn.enabled)
                        sessionsTab.goToPage(sessionsTab.currentPage - 1);
                }
            }
        }

        Repeater {
            model: sessionsTab.paginationItems(sessionsTab.currentPage, sessionsTab.totalPages)

            Rectangle {
                id: pageBtn
                required property var modelData
                readonly property bool isEllipsis: modelData === "…"
                readonly property bool isCurrent: !isEllipsis && Number(modelData) === sessionsTab.currentPage
                implicitWidth: isEllipsis ? 18 : 26
                implicitHeight: 26
                radius: 6
                color: isCurrent ? Kirigami.Theme.highlightColor : ((pageMouse.containsMouse && !isEllipsis && !sessionsTab.loading) ? Qt.rgba(1, 1, 1, 0.12) : (isEllipsis ? "transparent" : Qt.rgba(1, 1, 1, 0.04)))
                border.width: isEllipsis ? 0 : 1
                border.color: isCurrent ? "transparent" : Qt.rgba(1, 1, 1, 0.08)

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: pageBtn.modelData
                    font.bold: pageBtn.isCurrent
                    font.pixelSize: pageBtn.isEllipsis ? 12 : 11
                    color: pageBtn.isCurrent ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    opacity: pageBtn.isEllipsis ? 0.45 : (sessionsTab.loading ? 0.5 : 1.0)
                }

                MouseArea {
                    id: pageMouse
                    anchors.fill: parent
                    hoverEnabled: !pageBtn.isEllipsis
                    cursorShape: (!pageBtn.isEllipsis && !pageBtn.isCurrent && !sessionsTab.loading) ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!pageBtn.isEllipsis && !sessionsTab.loading)
                            sessionsTab.goToPage(Number(pageBtn.modelData));
                    }
                }
            }
        }

        Rectangle {
            id: nextBtn
            implicitWidth: 26
            implicitHeight: 26
            radius: 6
            readonly property bool enabled: !sessionsTab.loading && sessionsTab.currentPage < sessionsTab.totalPages
            color: nextMouse.containsMouse && enabled ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            opacity: enabled ? 1.0 : 0.35

            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: "›"
                font.pixelSize: 14
                font.bold: true
                color: Kirigami.Theme.textColor
            }

            MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: nextBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (nextBtn.enabled)
                        sessionsTab.goToPage(sessionsTab.currentPage + 1);
                }
            }
        }

        Item {
            Layout.fillWidth: true
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

    function sessionCostText(entry) {
        var info = FeatureTabs.sessionCostInfo(entry);
        if (!info.available)
            return i18n("Cost unavailable");
        if (info.cost === 0 && info.provenance === "estimated")
            return i18n("Free model");
        var cost = info.cost.toFixed(4);
        // A plan already paid for this work, so the figure is a comparison
        // against API pricing rather than something the user owes.
        if (info.billing === "subscription")
            return info.status === "exact" ? i18n("Covered by plan · $%1 on API", cost) : i18n("Covered by plan · ~$%1 on API", cost);
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
        if (info.billing === "subscription")
            return Kirigami.Theme.textColor;
        if (info.status === "partial" || info.provenance === "mixed")
            return "#f5a623";
        if (info.provenance === "estimated")
            return FeatureTabs.accent("spend");
        if (info.status === "exact")
            return rootItem.tabColor(entry.provider || "");
        return Kirigami.Theme.textColor;
    }

    function requestSessions(offset, refreshMode) {
        requestSerial += 1;
        requestedQuery = searchQuery;
        requestedSourceSignature = sourceSignature(selectedSourceIds);
        activeQuery = requestedQuery;
        activeSourceSignature = requestedSourceSignature;
        activeRequestSerial = requestSerial;
        activeOffset = offset;
        activeRefresh = refreshMode === true;
        if (offset === 0) {
            sessionsOffset = 0;
            sessionsTotal = 0;
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
        requestSessions(0, true);
    }

    function queryOnly(offset) {
        requestSessions(offset === undefined ? 0 : offset, false);
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
                    sessionsTab.requestSessions(0, false);
                    return;
                }
                sessionsTab.sourceResetSignature = "";
                sessionsTab.sessionsTotal = Number(payload.total) || 0;
                sessionsTab.sessionsOffset = Number(payload.offset) || sessionsTab.activeOffset;
                sessionsTab.sessions = page;
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
