import QtQuick
import QtQuick.Layouts
import "../package/contents/code/FeatureTabs.js" as FeatureTabs

ColumnLayout {
    id: page

    property var shell
    spacing: 12

    readonly property var rows: {
        var out = FeatureTabs.spendProviderRows(shell.providers);
        var localRows = FeatureTabs.localSpendRows(shell.localSpend);
        for (var i = 0; i < localRows.length; i++) {
            localRows[i].accent = FeatureTabs.accent("spend");
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

    function money(value, currency) {
        var amount = Number(value || 0).toFixed(2);
        if (currency === "CNY")
            return "¥" + amount;
        if (currency === "USD" || !currency)
            return "$" + amount;
        return amount + " " + currency;
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: shell.i18n("Usage & Spend")
            font.bold: true
            font.pixelSize: 14
            color: "#f8fafc"
        }
        Item {
            Layout.fillWidth: true
        }
        Text {
            visible: page.totalUsd > 0
            text: shell.i18n("Provider/API total") + " " + page.money(page.totalUsd, "USD")
            font.bold: true
            font.pixelSize: 13
            color: "#34d399"
        }
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
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 14
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            MouseArea {
                anchors.fill: parent
                cursorShape: modelData.local === true ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: {
                    if (modelData.local === true)
                        return;
                    shell.activeId = modelData.id;
                    if (typeof shell.refreshTab === "function")
                        shell.refreshTab();
                }
            }

            RowLayout {
                id: body
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
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
        }
    }
}
