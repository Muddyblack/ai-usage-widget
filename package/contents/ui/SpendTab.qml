import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../code/FeatureTabs.js" as FeatureTabs

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

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents.Label {
            text: i18n("Usage & Spend")
            font.bold: true
            font.pixelSize: 14
            color: Kirigami.Theme.textColor
        }
        Item {
            Layout.fillWidth: true
        }
        PlasmaComponents.Label {
            visible: spendTab.totalUsd > 0
            text: i18n("Provider/API total") + " " + rootItem.formatMoney(spendTab.totalUsd, "USD")
            font.bold: true
            font.pixelSize: 13
            color: "#34d399"
        }
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
}
