import QtQuick
import QtQuick.Window
import QtTest
import "../../package/contents/ui" as PlasmaWidget
import "../../hyprland" as SharedWidget

TestCase {
    id: testCase
    name: "IdleWork"

    function init() {
        failOnWarning(/.*(TypeError|ReferenceError|Unable to assign).*/);
    }

    function i18n(text) {
        return text;
    }
    function i18nc(context, text) {
        return text;
    }
    function i18np(one, many, count) {
        return count === 1 ? one : many;
    }

    Window {
        id: popup
        width: 500
        height: 400
        visible: false
    }

    Item {
        id: mockShell
        property var enabledTabs: ["claude"]
        property int activeTab: 0
        property bool showSettings: false
        property bool showUsageChart: true
        property string errorMsg: ""
        property color resolvedCardBg: "transparent"
        property color activeAccent: "cyan"
        property color googleBlue: "blue"
        property color googleGreen: "green"
        property string deepseekPrimaryCurrency: "USD"
        property string antigravityChartFilter: "both"
        property string chartWindow: "s"
        property string chartGranularity: "hourly"
        property real chartTimeOffset: 0
        property var usageHistory: [
            {
                t: Date.now() - 3600000,
                s: 20
            },
            {
                t: Date.now(),
                s: 30
            }
        ]
        property var weeklyUsageHistory: usageHistory.map(function (point) {
            return {
                t: point.t,
                v: point.s
            };
        })
        property var windows: [
            {
                id: "s",
                key: "s",
                label: "5H",
                size: 18000000
            }
        ]
        function chartWindowsFor(tab) {
            return windows;
        }
        function currentChartWindow() {
            return windows[0];
        }
        function hasAnySeriesData() {
            return true;
        }
        function _historyKey() {
            return "s";
        }
        function usageSlopePerHour(key, lookback) {
            return 10;
        }
        function getChartWindowSize() {
            return 18000000;
        }
        function getChartRangeText() {
            return "5H";
        }
        function windowLabel(window) {
            return "5H";
        }
        function i18n(text) {
            return text;
        }
        function i18nc(context, text) {
            return text;
        }
        function i18np(one, many, count) {
            return count === 1 ? one : many;
        }
    }

    Component {
        id: plasmaStatus
        PlasmaWidget.StatusChip {
            status: ({
                    indicator: "minor"
                })
        }
    }
    Component {
        id: sharedStatus
        SharedWidget.StatusChip {
            shell: mockShell
            status: ({
                    indicator: "minor"
                })
        }
    }
    Component {
        id: plasmaChart
        PlasmaWidget.UsageChart {
            rootItem: mockShell
            width: 450
            height: 184
        }
    }
    Component {
        id: sharedChart
        SharedWidget.UsageChart {
            shell: mockShell
            usageHistory: mockShell.usageHistory
            windows: mockShell.windows
            chartWindow: "s"
            width: 450
            height: 184
        }
    }
    Component {
        id: plasmaInfo
        PlasmaWidget.ProjectInfoPane {
            rootItem: mockShell
            width: 450
        }
    }
    Component {
        id: sharedInfo
        SharedWidget.ProjectInfoPane {
            shell: mockShell
            width: 450
        }
    }

    function cleanup() {
        popup.visible = false;
    }

    function test_animationsFollowWindow_data() {
        return [
            {
                tag: "plasma-status",
                component: plasmaStatus,
                animation: "statusPulse"
            },
            {
                tag: "shared-status",
                component: sharedStatus,
                animation: "statusPulse"
            },
            {
                tag: "plasma-chart",
                component: plasmaChart,
                animation: "usagePulse"
            },
            {
                tag: "shared-chart",
                component: sharedChart,
                animation: "usagePulse"
            }
        ];
    }

    function test_animationsFollowWindow(data) {
        var item = createTemporaryObject(data.component, popup.contentItem);
        verify(item !== null);
        var animation = findChild(item, data.animation);
        verify(animation !== null);
        // Hiding a Window leaves its children's visible properties true.
        compare(item.visible, true);
        compare(animation.running, false);
        popup.visible = true;
        tryCompare(animation, "running", true);
        popup.visible = false;
        tryCompare(animation, "running", false);
        popup.visible = true;
        tryCompare(animation, "running", true);
        item.visible = false;
        tryCompare(animation, "running", false);
    }

    function test_infoStopsWhenWindowCloses_data() {
        return [
            {
                tag: "plasma",
                component: plasmaInfo
            },
            {
                tag: "shared",
                component: sharedInfo
            }
        ];
    }

    function test_infoStopsWhenWindowCloses(data) {
        var info = createTemporaryObject(data.component, popup.contentItem);
        verify(info !== null);
        // The window starts hidden, so the real client has issued no requests.
        info.client.dispose();
        var ticks = 0, pauses = 0;
        info.client = {
            tick: function () {
                ticks++;
            },
            pause: function () {
                pauses++;
            },
            dispose: function () {}
        };
        compare(info.foregroundVisible, false);
        popup.visible = true;
        tryCompare(info, "foregroundVisible", true);
        compare(ticks, 1);
        tryVerify(function () {
            return ticks >= 2;
        }, 2500);
        popup.visible = false;
        tryCompare(info, "foregroundVisible", false);
        compare(pauses, 1);
        var before = ticks;
        wait(1200);
        compare(ticks, before);
        popup.visible = true;
        tryCompare(info, "foregroundVisible", true);
        compare(ticks, before + 1);
    }
}
