import QtQuick
import QtQuick.Controls.Basic as QC
import QtQuick.Layouts
import "../package/contents/code/FeatureTabs.js" as FeatureTabs

ColumnLayout {
    id: page

    property var shell
    spacing: 12

    readonly property var rows: {
        var out = FeatureTabs.spendProviderRows(shell.providers, shell.localSpend);
        var localRows = FeatureTabs.localSpendRows(shell.localSpend, out, shell.providers);
        for (var i = 0; i < localRows.length; i++) {
            localRows[i].label = shell.i18n(localRows[i].label);
            localRows[i].note = shell.i18n(localRows[i].note);
            out.push(localRows[i]);
        }
        out.sort(function (a, b) {
            return b.cost - a.cost;
        });
        return out;
    }
    readonly property real totalUsd: FeatureTabs.spendTotal(rows, "USD")
    readonly property real meteredTotalUsd: FeatureTabs.spendMeteredTotal(rows, "USD")
    readonly property real planTotalUsd: FeatureTabs.spendPlanTotal(rows, "USD")
    readonly property real allTotalUsd: FeatureTabs.spendAllTotal(rows, "USD")
    readonly property string summaryText: FeatureTabs.spendSummaryText(rows, "USD", shell.i18n)
    readonly property string summaryTooltip: FeatureTabs.spendSummaryTooltip(rows, "USD", shell.i18n)

    // Which provider rows are expanded, by row id — a plain object so
    // reassigning it (not mutating in place) fires the property-changed
    // signal QML needs to notice. Each expanded row gets its own trend
    // chart (see the Repeater below) rather than one merged chart across
    // every provider: providers report on wildly different ranges (30-day
    // API window vs. all-time local logs), so summing them into one line
    // produced a chart that was mostly flat with one misleading spike.
    property var expandedProviders: ({})
    property var expandedWindowDays: ({})

    function money(value, currency) {
        var amount = Number(value || 0).toFixed(2);
        if (currency === "CNY")
            return "¥" + amount;
        if (currency === "USD" || !currency)
            return "$" + amount;
        return amount + " " + currency;
    }

    // ── Model rate table ───────────────────────────────────────────────────
    // The shared pricing catalog the session costs are computed from, shown so
    // the numbers above can be checked against the rate that produced them.
    // Reads the cache only (--pricing-table never fetches), so opening this
    // cannot block on the network.
    property bool ratesOpen: false
    property var rateRows: []
    property int rateTotal: 0
    property string rateUnit: ""
    property int rateFetchedAt: 0
    property bool rateLoading: false
    property string rateError: ""
    property string rateFilter: ""
    readonly property int rateLimit: 40
    property int rateOffset: 0
    readonly property int ratePages: FeatureTabs.ratePageCount(page.rateTotal, page.rateLimit)
    readonly property int ratePage: FeatureTabs.ratePageNumber(page.rateOffset, page.rateLimit, page.rateTotal)

    function loadRates(offset) {
        if (page.rateLoading)
            return;
        page.rateLoading = true;
        page.rateError = "";
        page.rateOffset = offset === undefined ? 0 : offset;
        if (page.shell && typeof page.shell.queryRates === "function") {
            page.shell.queryRates((page.rateFilter || "").trim(), page.rateLimit, page.rateOffset, function (payload) {
                page.rateLoading = false;
                if (!payload) {
                    page.rateError = shell.i18n("Could not read model pricing.");
                    return;
                }
                page.rateRows = payload.rows || [];
                page.rateTotal = payload.total || 0;
                page.rateUnit = payload.unit || "";
                page.rateFetchedAt = payload.fetchedAt || 0;
                page.rateError = page.rateTotal === 0 ? (payload.error || shell.i18n("No cached model rates yet — refresh pricing in settings.")) : "";
            });
        } else {
            page.rateLoading = false;
        }
    }

    onRatesOpenChanged: {
        if (page.ratesOpen && page.rateRows.length === 0)
            page.loadRates(0);
    }

    onRateFilterChanged: rateSearchTimer.restart()

    Timer {
        id: rateSearchTimer
        interval: 300
        repeat: false
        onTriggered: page.loadRates(0)
    }

    Text {
        Layout.fillWidth: true
        text: shell.i18n("Totals come from each provider's own usage APIs and local CLI logs. Ranges differ (30-day, all-time, lifetime).")
        wrapMode: Text.WordWrap
        font.pixelSize: 10
        opacity: 0.45
        color: "#f8fafc"
    }

    Text {
        visible: page.rows.length === 0
        Layout.fillWidth: true
        text: shell.i18n("No cost figures yet. Enable providers that report spend, or use them until local logs appear.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: "#f8fafc"
        font.pixelSize: 11
    }

    Repeater {
        model: page.rows

        Rectangle {
            id: rowCard
            required property var modelData
            readonly property bool canExpand: !!((modelData.dailyCost && modelData.dailyCost.length > 1) || (modelData.dailyTokens && modelData.dailyTokens.length > 1))
            readonly property bool isExpanded: page.expandedProviders[modelData.id] === true
            readonly property int windowDays: page.expandedWindowDays[modelData.id] !== undefined ? page.expandedWindowDays[modelData.id] : 0

            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 14 + (canExpand && isExpanded ? detail.implicitHeight + 10 : 0)
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.bottomMargin: rowCard.canExpand && rowCard.isExpanded ? detail.implicitHeight + 10 : 0
                cursorShape: modelData.local === true && !rowCard.canExpand ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    if (rowCard.canExpand) {
                        var next = Object.assign({}, page.expandedProviders);
                        next[modelData.id] = !rowCard.isExpanded;
                        page.expandedProviders = next;
                        return;
                    }
                    if (modelData.local === true)
                        return;
                    shell.activeId = modelData.id;
                    if (typeof shell.refreshTab === "function")
                        shell.refreshTab();
                }
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 8

                RowLayout {
                    id: body
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: modelData.accent || "#34d399"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1
                        Text {
                            text: modelData.label
                            font.bold: true
                            font.pixelSize: 12
                            color: "#f8fafc"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        Text {
                            visible: modelData.note !== ""
                            text: shell.i18n(modelData.note)
                            font.pixelSize: 10
                            opacity: 0.45
                            color: "#f8fafc"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                    }

                    Text {
                        visible: rowCard.canExpand
                        text: rowCard.isExpanded ? "▾" : "▸"
                        font.pixelSize: 11
                        opacity: 0.5
                        color: "#f8fafc"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: page.money(modelData.cost, modelData.currency || "USD")
                        font.bold: true
                        // Fixed-width digits keep the two-decimal amounts in one
                        // column: every price ends in ".XX", so with equal digit
                        // advances the decimal points line up across rows.
                        font.family: "monospace"
                        font.pixelSize: 12
                        color: "#f8fafc"
                    }
                }

                SpendTimelineChart {
                    id: detail
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    visible: rowCard.canExpand && rowCard.isExpanded
                    shell: page.shell
                    points: FeatureTabs.spendTimeline(modelData.dailyCost, modelData.dailyTokens, rowCard.windowDays)
                    costColor: modelData.accent || "#34d399"
                    windowDays: rowCard.windowDays
                    onWindowDaysSelected: days => {
                        var next = Object.assign({}, page.expandedWindowDays);
                        next[modelData.id] = days;
                        page.expandedWindowDays = next;
                    }
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

    // The click target wraps the row rather than sitting inside it: a
    // MouseArea parented straight to a RowLayout becomes a layout item, and
    // Qt refuses anchors there.
    Item {
        Layout.fillWidth: true
        implicitHeight: ratesHeader.implicitHeight

        RowLayout {
            id: ratesHeader
            anchors.fill: parent
            spacing: 6

            Text {
                text: shell.i18n("Model rates")
                font.bold: true
                font.pixelSize: 12
                color: "#f8fafc"
            }

            Text {
                visible: page.rateTotal > 0
                text: page.rateUnit
                font.pixelSize: 9
                opacity: 0.45
                color: "#f8fafc"
            }

            Text {
                visible: text !== ""
                text: FeatureTabs.rateAge(page.rateFetchedAt, shell.i18n)
                font.pixelSize: 9
                opacity: 0.45
                color: "#f8fafc"
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: page.rateLoading ? shell.i18n("Loading\u2026") : (page.ratesOpen ? "\u25be" : "\u25b8")
                font.pixelSize: 11
                opacity: 0.6
                color: "#f8fafc"
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.ratesOpen = !page.ratesOpen
        }
    }

    RowLayout {
        visible: page.ratesOpen
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: rateFilterInput.activeFocus ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.08)

            TextInput {
                id: rateFilterInput
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: "#f8fafc"
                font.pixelSize: 11
                selectByMouse: true
                onTextChanged: page.rateFilter = text

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: rateFilterInput.text === ""
                    text: shell.i18n("Filter by provider or model\u2026")
                    font.pixelSize: 11
                    opacity: 0.35
                    color: "#f8fafc"
                }
            }
        }

        // Top pagination so the user doesn't need to scroll all the way to the bottom
        RowLayout {
            visible: page.ratePages > 1
            spacing: 4
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                readonly property int target: page.rateOffset - page.rateLimit
                readonly property bool usable: !page.rateLoading && target >= 0
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: prevAreaTop.containsMouse && usable ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                opacity: usable ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#f8fafc"
                }

                MouseArea {
                    id: prevAreaTop
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (parent.usable)
                            page.loadRates(parent.target);
                    }
                }
            }

            Text {
                text: page.ratePage + "/" + page.ratePages
                font.pixelSize: 10
                font.family: "monospace"
                opacity: 0.7
                color: "#f8fafc"
                Layout.leftMargin: 2
                Layout.rightMargin: 2
            }

            Rectangle {
                readonly property int target: page.rateOffset + page.rateLimit
                readonly property bool usable: !page.rateLoading && target < page.rateTotal
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: nextAreaTop.containsMouse && usable ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                opacity: usable ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#f8fafc"
                }

                MouseArea {
                    id: nextAreaTop
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (parent.usable)
                            page.loadRates(parent.target);
                    }
                }
            }
        }
    }

    Text {
        visible: page.ratesOpen && page.rateError !== ""
        Layout.fillWidth: true
        text: page.rateError
        font.pixelSize: 10
        wrapMode: Text.WordWrap
        opacity: 0.8
        color: "#f87171"
    }

    // Column header, so the three rate numbers are readable as a table.
    RowLayout {
        visible: page.ratesOpen && page.rateRows.length > 0
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: shell.i18n("Model")
            font.pixelSize: 9
            opacity: 0.45
            color: "#f8fafc"
        }
        Repeater {
            model: [shell.i18n("In"), shell.i18n("Out"), shell.i18n("Cached")]
            Text {
                required property var modelData
                Layout.preferredWidth: 54
                horizontalAlignment: Text.AlignRight
                text: modelData
                font.pixelSize: 9
                opacity: 0.45
                color: "#f8fafc"
            }
        }
    }

    ListView {
        id: rateList
        visible: page.ratesOpen && page.rateRows.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(240, contentHeight)
        clip: true
        spacing: 2
        model: page.rateRows
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        QC.ScrollBar.vertical: QC.ScrollBar {
            id: rateScrollBar
            policy: rateList.interactive ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff
            width: 8
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: "#f8fafc"
                opacity: rateScrollBar.pressed ? 0.6 : (rateScrollBar.hovered ? 0.4 : 0.22)
            }
            background: Rectangle {
                implicitWidth: 8
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.04)
            }
        }

        delegate: RowLayout {
            required property var modelData
            width: rateList.width - (rateScrollBar.visible ? (rateScrollBar.width + 4) : 0)
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: modelData.model || ""
                    font.pixelSize: 11
                    color: "#f8fafc"
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: modelData.provider || ""
                    font.pixelSize: 9
                    opacity: 0.45
                    color: "#f8fafc"
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }

            Repeater {
                model: [modelData.input, modelData.output, modelData.cached]
                Text {
                    required property var modelData
                    Layout.preferredWidth: 54
                    horizontalAlignment: Text.AlignRight
                    text: FeatureTabs.rateText(modelData)
                    font.family: "monospace"
                    font.pixelSize: 10
                    opacity: typeof modelData === "number" ? 0.9 : 0.3
                    color: "#f8fafc"
                }
            }
        }
    }

    RowLayout {
        visible: page.ratesOpen && page.ratePages > 1
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 12
        spacing: 6

        Text {
            text: shell.i18n("%1 of %2", page.ratePage, page.ratePages)
            font.pixelSize: 10
            opacity: 0.5
            color: "#f8fafc"
        }

        Item {
            Layout.fillWidth: true
        }

        Repeater {
            model: [
                {
                    label: shell.i18n("Previous"),
                    step: -1
                },
                {
                    label: shell.i18n("Next"),
                    step: 1
                }
            ]

            Rectangle {
                required property var modelData
                readonly property int target: page.rateOffset + modelData.step * page.rateLimit
                readonly property bool usable: !page.rateLoading && target >= 0 && target < page.rateTotal

                implicitWidth: pagerLabel.implicitWidth + 16
                implicitHeight: 22
                radius: 6
                color: pagerArea.containsMouse && usable ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                opacity: usable ? 1 : 0.35

                Text {
                    id: pagerLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: 10
                    color: "#f8fafc"
                }

                MouseArea {
                    id: pagerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (parent.usable)
                            page.loadRates(parent.target);
                    }
                }
            }
        }
    }
}
