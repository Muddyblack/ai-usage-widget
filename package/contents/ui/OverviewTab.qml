import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// All enabled providers at a glance. Click a row to open that provider's tab.
ColumnLayout {
    id: overviewTab
    property Item rootItem

    visible: rootItem.enabledTabs[rootItem.activeTab] === "overview" && !rootItem.showSettings
    Layout.fillWidth: true
    spacing: 10

    readonly property var rows: {
        var out = [];
        var tabs = rootItem.enabledTabs || [];
        for (var i = 0; i < tabs.length; i++) {
            var id = tabs[i];
            if (id === "overview" || id === "spend" || id === "sessions")
                continue;
            out.push(id);
        }
        return out;
    }

    PlasmaComponents.Label {
        visible: overviewTab.rows.length === 0
        Layout.fillWidth: true
        text: i18n("Enable a provider in Settings to see it here.")
        wrapMode: Text.WordWrap
        opacity: 0.55
        color: Kirigami.Theme.textColor
    }

    Repeater {
        model: overviewTab.rows

        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: rowBody.implicitHeight + 16
            radius: 8
            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            readonly property string providerId: modelData
            readonly property color accent: rootItem.tabColor(providerId)
            readonly property real pct: overviewTab.providerPct(providerId)
            readonly property string detail: overviewTab.providerDetail(providerId)

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rootItem.selectTab(providerId)
            }

            RowLayout {
                id: rowBody
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 6
                    color: Qt.rgba(accent.r, accent.g, accent.b, 0.15)
                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: rootItem.tabIcon(providerId)
                        sourceSize.width: 16
                        sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        visible: status !== Image.Error && source !== ""
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: accent
                        visible: parent.children[0].status === Image.Error || rootItem.tabIcon(providerId) === ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            text: rootItem.tabName(providerId)
                            font.bold: true
                            font.pixelSize: 12
                            color: Kirigami.Theme.textColor
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            visible: pct >= 0
                            text: Math.round(pct) + "%"
                            font.bold: true
                            font.pixelSize: 12
                            color: accent
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.08)
                        visible: pct >= 0
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, pct / 100))
                            height: parent.height
                            radius: parent.radius
                            color: accent
                        }
                    }
                    PlasmaComponents.Label {
                        visible: detail !== ""
                        text: detail
                        font.pixelSize: 10
                        opacity: 0.5
                        color: Kirigami.Theme.textColor
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    function providerPct(id) {
        // Prefer live properties the Plasma root already keeps for each service.
        if (id === "claude")
            return rootItem.weeklyAvailable ? rootItem.weeklyPct : (rootItem.sessionAvailable ? rootItem.sessionPct : -1);
        if (id === "antigravity")
            return rootItem.antigravityPct;
        if (id === "openai") {
            if (rootItem.codexWeeklyAvailable)
                return rootItem.codexWeeklyPct;
            if (rootItem.codexSessionAvailable)
                return rootItem.codexSessionPct;
            return -1;
        }
        if (id === "kiro")
            return rootItem.kiroPct;
        if (id === "openrouter") {
            if (rootItem.openrouterLimitUSD !== null && rootItem.openrouterLimitUSD > 0)
                return Math.min(100, (rootItem.openrouterUsageUSD / rootItem.openrouterLimitUSD) * 100);
            return -1;
        }
        if (id === "ollama")
            return rootItem.ollamaWindows.length > 0 ? rootItem.ollamaPct : -1;
        if (id === "grok")
            return rootItem.grokPct;
        if (id === "zai")
            return rootItem.zaiTokenPct;
        if (id === "copilot")
            return rootItem.copilotPct;
        if (id === "kimi")
            return rootItem.kimiPlanPct > 0 ? rootItem.kimiPlanPct : -1;
        if (id === "muse")
            return rootItem.museCurrentPct > 0 ? rootItem.museCurrentPct : (rootItem.museWeeklyPct > 0 ? rootItem.museWeeklyPct : -1);
        if (id === "cursor")
            return rootItem.cursorTotalPct;
        return -1;
    }

    function providerDetail(id) {
        if (id === "claude" && rootItem.claudeSubscriptionType)
            return rootItem.claudeSubscriptionType;
        if (id === "openai" && rootItem.openaiPlanType)
            return rootItem.openaiPlanType;
        if (id === "openrouter" && rootItem.openrouterUsageUSD > 0)
            return rootItem.formatMoney(rootItem.openrouterUsageUSD, "USD");
        if (id === "ollama" && rootItem.ollamaWindows.length > 0)
            return rootItem.ollamaWindows[0].label;
        if (id === "deepseek" && rootItem.deepseekPrimaryTotal > 0)
            return rootItem.formatMoney(rootItem.deepseekPrimaryTotal, rootItem.deepseekCurrency || "USD");
        if (id === "mistral" && rootItem.mistralVibeTotalCost > 0)
            return rootItem.formatMoney(rootItem.mistralVibeTotalCost, "USD");
        if (id === "cursor" && rootItem.cursorPlanName)
            return rootItem.cursorPlanName;
        if (id === "copilot" && rootItem.copilotPlan)
            return rootItem.copilotPlan;
        return "";
    }
}
