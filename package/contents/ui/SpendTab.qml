import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/FeatureTabs.js" as FeatureTabs
import "../code/Shell.js" as Shell

// Cross-provider cost snapshot. Daily history is still per-quota in the chart;
// this tab surfaces the spend figures each provider already reports.
ColumnLayout {
    id: spendTab
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "spend" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 12

    readonly property var rows: spendTab.buildRows()
    readonly property real totalUsd: FeatureTabs.spendTotal(rows, "USD")

    // ── Model rate table ───────────────────────────────────────────────────
    // The shared pricing catalog the session costs are computed from, shown so
    // the numbers above can be checked against the rate that produced them.
    property bool ratesOpen: false
    property var rateRows: []
    property int rateTotal: 0
    property string rateUnit: ""
    property int rateFetchedAt: 0
    property bool rateLoading: false
    property string rateError: ""
    property string rateFilter: ""
    property string rateCommand: ""
    readonly property int rateLimit: 40
    property int rateOffset: 0
    readonly property int ratePages: FeatureTabs.ratePageCount(spendTab.rateTotal, spendTab.rateLimit)
    readonly property int ratePage: FeatureTabs.ratePageNumber(spendTab.rateOffset, spendTab.rateLimit, spendTab.rateTotal)

    function loadRates(offset) {
        if (spendTab.rateLoading)
            return;
        spendTab.rateLoading = true;
        spendTab.rateError = "";
        spendTab.rateOffset = offset === undefined ? 0 : offset;
        var cmd = "cd " + Shell.quote(rootItem.scriptDir) + " && ./get-ai-usage --pricing-table";
        cmd += " --query " + Shell.quote((spendTab.rateFilter || "").trim());
        cmd += " --limit " + spendTab.rateLimit + " --offset " + spendTab.rateOffset;
        spendTab.rateCommand = cmd;
        rateSource.disconnectSource(cmd);
        rateSource.connectSource(cmd);
    }

    onRatesOpenChanged: {
        if (spendTab.ratesOpen && spendTab.rateRows.length === 0)
            spendTab.loadRates(0);
    }

    Timer {
        id: rateSearchTimer
        interval: 300
        repeat: false
        onTriggered: spendTab.loadRates(0)
    }

    onRateFilterChanged: rateSearchTimer.restart()

    Plasma5Support.DataSource {
        id: rateSource
        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
            if (src !== spendTab.rateCommand)
                return;
            spendTab.rateLoading = false;
            var payload = FeatureTabs.parseRateTable((data && data.stdout) ? data.stdout : "");
            if (payload === null) {
                spendTab.rateError = i18n("Could not read model pricing.");
                return;
            }
            spendTab.rateRows = payload.rows;
            spendTab.rateTotal = payload.total;
            spendTab.rateUnit = payload.unit;
            spendTab.rateFetchedAt = payload.fetchedAt;
            if (payload.total === 0)
                spendTab.rateError = payload.error || i18n("No cached model rates yet — refresh pricing in settings.");
        }
    }

    function buildRows() {
        // Plasma keeps costs on root properties rather than a provider list.
        var out = [];
        function push(id, label, cost, note, currency) {
            if (typeof cost !== "number" || !isFinite(cost) || !(cost > 0))
                return;
            out.push({
                id: id,
                label: label,
                cost: cost,
                note: note || "",
                currency: currency || "USD",
                accent: rootItem.tabColor(id)
            });
        }
        push("claude", "Claude", rootItem.claudeTotalCostUSD || rootItem.claudeStatsTotalCostUSD || 0, i18n("30d API"));
        push("openai", "OpenAI", rootItem.openaiTotalCostUSD || rootItem.codexStatsTotalCostUSD || 0, i18n("30d API"));
        push("openrouter", "OpenRouter", rootItem.openrouterUsageUSD, i18n("all-time"));
        push("mistral", "Mistral", rootItem.mistralVibeTotalCost, i18n("vibe CLI"));
        push("muse", "Muse", rootItem.museCostUSD, i18n("local est."), rootItem.museCurrency || "USD");
        push("cline", "Cline", (rootItem.clineStats && rootItem.clineStats.totalCostUSD) || 0, i18n("local"));
        push("cursor", "Cursor", rootItem.cursorOnDemandUsed, i18n("on-demand"));
        var localRows = FeatureTabs.localSpendRows(rootItem.localSpend);
        for (var i = 0; i < localRows.length; i++) {
            localRows[i].accent = FeatureTabs.accent("spend");
            localRows[i].label = i18n(localRows[i].label);
            localRows[i].note = i18n(localRows[i].note);
            out.push(localRows[i]);
        }
        out.sort(function (a, b) {
            return b.cost - a.cost;
        });
        return out;
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: i18n("Totals come from each provider's own usage APIs and local CLI logs. Ranges differ (30-day, all-time, lifetime).")
        wrapMode: Text.WordWrap
        font.pixelSize: 10
        opacity: 0.45
        color: Kirigami.Theme.textColor
    }

    PlasmaComponents.Label {
        visible: spendTab.rows.length === 0
        Layout.fillWidth: true
        text: i18n("No cost figures yet. Enable providers that report spend, or use them until local logs appear.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: Kirigami.Theme.textColor
    }

    Repeater {
        model: spendTab.rows

        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 16
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            RowLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: modelData.accent
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1
                    PlasmaComponents.Label {
                        text: modelData.label
                        font.bold: true
                        font.pixelSize: 12
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                    PlasmaComponents.Label {
                        visible: modelData.note !== ""
                        text: modelData.note
                        font.pixelSize: 10
                        opacity: 0.45
                        color: Kirigami.Theme.textColor
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }

                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignVCenter
                    text: rootItem.formatMoney(modelData.cost, modelData.currency)
                    font.bold: true
                    // Fixed-width digits keep the two-decimal amounts in one
                    // column: every price ends in ".XX", so with equal digit
                    // advances the decimal points line up across rows.
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: Kirigami.Theme.textColor
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: modelData.local === true ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    if (modelData.local !== true)
                        rootItem.selectTab(modelData.id);
                }
            }
        }
    }

    // ── Model rates ────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 1
        color: Qt.rgba(1, 1, 1, 0.08)
    }

    // The click target has to wrap the row, not sit inside it: a MouseArea
    // parented straight to a RowLayout becomes a layout item, and Qt refuses
    // anchors there — which left this header with nothing to click.
    Item {
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: ratesHeader.implicitHeight

        RowLayout {
            id: ratesHeader
            anchors.fill: parent
            spacing: 6

            PlasmaComponents.Label {
                text: i18n("Model rates")
                font.bold: true
                font.pixelSize: 12
                color: Kirigami.Theme.textColor
            }

            PlasmaComponents.Label {
                visible: spendTab.rateTotal > 0
                text: spendTab.rateUnit
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
            }

            PlasmaComponents.Label {
                visible: text !== ""
                text: FeatureTabs.rateAge(spendTab.rateFetchedAt, i18n)
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents.Label {
                text: spendTab.rateLoading ? i18n("Loading…") : (spendTab.ratesOpen ? "▾" : "▸")
                font.pixelSize: 11
                opacity: 0.6
                color: Kirigami.Theme.textColor
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: spendTab.ratesOpen = !spendTab.ratesOpen
        }
    }

    RowLayout {
        visible: spendTab.ratesOpen
        Layout.fillWidth: true
        spacing: 8

        PlasmaComponents.TextField {
            Layout.fillWidth: true
            placeholderText: i18n("Filter by provider or model…")
            text: spendTab.rateFilter
            onTextChanged: spendTab.rateFilter = text
        }

        RowLayout {
            visible: spendTab.ratePages > 1
            spacing: 4
            Layout.alignment: Qt.AlignVCenter

            PlasmaComponents.Button {
                implicitWidth: 28
                implicitHeight: 28
                text: "‹"
                enabled: !spendTab.rateLoading && spendTab.rateOffset > 0
                onClicked: spendTab.loadRates(Math.max(0, spendTab.rateOffset - spendTab.rateLimit))
            }

            PlasmaComponents.Label {
                text: spendTab.ratePage + "/" + spendTab.ratePages
                font.pixelSize: 10
                font.family: "monospace"
                opacity: 0.7
                color: Kirigami.Theme.textColor
                Layout.leftMargin: 2
                Layout.rightMargin: 2
            }

            PlasmaComponents.Button {
                implicitWidth: 28
                implicitHeight: 28
                text: "›"
                enabled: !spendTab.rateLoading && (spendTab.rateOffset + spendTab.rateLimit) < spendTab.rateTotal
                onClicked: spendTab.loadRates(spendTab.rateOffset + spendTab.rateLimit)
            }
        }
    }

    PlasmaComponents.Label {
        visible: spendTab.ratesOpen && spendTab.rateError !== ""
        Layout.fillWidth: true
        text: spendTab.rateError
        font.pixelSize: 10
        wrapMode: Text.WordWrap
        opacity: 0.7
        color: Kirigami.Theme.negativeTextColor
    }

    // Column header, so the three rate numbers are readable as a table.
    RowLayout {
        visible: spendTab.ratesOpen && spendTab.rateRows.length > 0
        Layout.fillWidth: true
        spacing: 8

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("Model")
            font.pixelSize: 9
            opacity: 0.45
            color: Kirigami.Theme.textColor
        }
        Repeater {
            model: [i18n("In"), i18n("Out"), i18n("Cached")]
            PlasmaComponents.Label {
                required property var modelData
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
                text: modelData
                font.pixelSize: 9
                opacity: 0.45
                color: Kirigami.Theme.textColor
            }
        }
    }

    ListView {
        id: rateList
        visible: spendTab.ratesOpen && spendTab.rateRows.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(240, contentHeight)
        clip: true
        spacing: 2
        model: spendTab.rateRows
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            id: rateScrollBar
            policy: QQC2.ScrollBar.AsNeeded
            width: 8
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: Kirigami.Theme.textColor
                opacity: rateScrollBar.pressed ? 0.6 : (rateScrollBar.hovered ? 0.4 : 0.22)
            }
            background: Rectangle {
                implicitWidth: 8
                radius: 4
                color: Kirigami.Theme.textColor
                opacity: 0.04
            }
        }

        delegate: RowLayout {
            required property var modelData
            width: rateList.width - (rateScrollBar.visible ? (rateScrollBar.width + 4) : 0)
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: modelData.model || ""
                    textFormat: Text.PlainText
                    font.pixelSize: 11
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: modelData.provider || ""
                    textFormat: Text.PlainText
                    font.pixelSize: 9
                    opacity: 0.45
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }

            Repeater {
                model: [modelData.input, modelData.output, modelData.cached]
                PlasmaComponents.Label {
                    required property var modelData
                    Layout.preferredWidth: 54
                    horizontalAlignment: Text.AlignRight
                    text: FeatureTabs.rateText(modelData)
                    font.family: "monospace"
                    font.pixelSize: 10
                    opacity: typeof modelData === "number" ? 0.9 : 0.3
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    RowLayout {
        visible: spendTab.ratesOpen && spendTab.ratePages > 1
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 12
        spacing: 6

        PlasmaComponents.Label {
            text: i18n("%1 of %2", spendTab.ratePage, spendTab.ratePages)
            font.pixelSize: 10
            opacity: 0.5
            color: Kirigami.Theme.textColor
        }

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents.Button {
            text: i18n("Previous")
            enabled: !spendTab.rateLoading && spendTab.rateOffset > 0
            onClicked: spendTab.loadRates(Math.max(0, spendTab.rateOffset - spendTab.rateLimit))
        }

        PlasmaComponents.Button {
            text: i18n("Next")
            enabled: !spendTab.rateLoading && (spendTab.rateOffset + spendTab.rateLimit) < spendTab.rateTotal
            onClicked: spendTab.loadRates(spendTab.rateOffset + spendTab.rateLimit)
        }
    }
}
