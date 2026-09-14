import QtQuick
import QtQuick.Layouts

// The production quota rows shared by Hyprland and Windows. Kept separate
// from the popup chrome so fixture tests instantiate the actual delegates.
ColumnLayout {
    id: rows

    property var provider: null
    property string activeId: ""
    property color accent: "#10a37f"
    property var countdown: function (epoch) {
        return "";
    }
    readonly property int rowCount: repeater.count

    spacing: 12

    Repeater {
        id: repeater
        model: ((rows.provider && rows.provider.quotaWindows) || []).filter(function (window) {
            return window.available === true;
        })

        UsageRow {
            required property var modelData
            objectName: "quota-" + modelData.key
            label: modelData.label || ""
            value: modelData.pct || 0
            resetText: modelData.resetText || ""
            countdownText: rows.countdown(modelData.resetAt || 0)
            detail: modelData.detail || ""
            barColor: modelData.color || (rows.activeId === "antigravity" && (modelData.key === "external" || modelData.key === "rest" || (modelData.label && modelData.label.indexOf("Claude") !== -1)) ? "#34a853" : rows.accent)
            showMeter: modelData.showMeter !== false
        }
    }
}
