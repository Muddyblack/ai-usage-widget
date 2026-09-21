import QtQuick
import QtQuick.Layouts

// Dual-line spend-over-time chart: daily cost on a linear axis, daily token
// volume on a log axis (tokens swing by orders of magnitude; cost rarely
// does). Self-contained Canvas, no charting library — mirrors the plain
// hand-drawn style already used by UsageChart.qml.
ColumnLayout {
    id: chart

    property var shell
    // [{date, usd, total}], sorted ascending by date — see
    // FeatureTabs.spendTimeline(). Empty/short series hide the chart.
    property var points: []
    property color costColor: "#34d399"
    property color tokenColor: "#7dd3fc"
    property color textColor: "#f8fafc"
    property int windowDays: 0

    signal windowDaysSelected(int days)

    spacing: 6

    readonly property var scrubIndex: canvas.scrubIndex

    // A series with nothing in it is left undrawn rather than stroked along
    // the baseline: a flat line at zero reads as "this provider spent zero",
    // when it actually means "this provider does not report that number".
    readonly property bool hasCost: {
        for (var i = 0; i < chart.points.length; i++)
            if ((chart.points[i].usd || 0) > 0)
                return true;
        return false;
    }
    readonly property bool hasTokens: {
        for (var i = 0; i < chart.points.length; i++)
            if ((chart.points[i].total || 0) > 0)
                return true;
        return false;
    }

    // Clicking a legend entry hides that series, so one line can be read on
    // its own without the other rescaling the eye.
    property bool showCost: true
    property bool showTokens: true
    readonly property bool drawCost: chart.hasCost && chart.showCost
    readonly property bool drawTokens: chart.hasTokens && chart.showTokens

    visible: chart.points.length > 1 && (chart.hasCost || chart.hasTokens)

    // "2026-09-14" -> "Sep 14". Axis ticks name the range without the reader
    // having to hover, so the chart says *when* on its own.
    function axisDate(date) {
        if (typeof date !== "string" || date.length < 10)
            return "";
        var parsed = new Date(date + "T00:00:00Z");
        if (isNaN(parsed.getTime()))
            return "";
        return parsed.toLocaleDateString(Qt.locale(), "MMM d");
    }

    // Up to four evenly spaced ticks across the series, always including the
    // first and last day.
    readonly property var axisTicks: {
        var n = chart.points.length;
        if (n < 2)
            return [];
        var wanted = Math.min(4, n);
        var out = [];
        for (var i = 0; i < wanted; i++) {
            var index = Math.round(i * (n - 1) / (wanted - 1));
            var label = chart.axisDate(chart.points[index].date);
            if (label !== "" && out.indexOf(label) === -1)
                out.push(label);
        }
        return out;
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RowLayout {
            spacing: 4

            // Cost legend / toggle
            Rectangle {
                visible: chart.hasCost
                implicitWidth: costLegend.implicitWidth + 18
                implicitHeight: 18
                radius: 5
                color: costLegendArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                RowLayout {
                    id: costLegend
                    anchors.centerIn: parent
                    spacing: 4
                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: chart.costColor
                        opacity: chart.showCost ? 1.0 : 0.3
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: shell.i18n("Cost")
                        font.pixelSize: 10
                        opacity: chart.showCost ? 0.65 : 0.3
                        color: chart.textColor
                    }
                }

                MouseArea {
                    id: costLegendArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Never let both series be hidden at once.
                    onClicked: {
                        if (chart.showCost && !chart.drawTokens)
                            return;
                        chart.showCost = !chart.showCost;
                    }
                }
            }

            // Tokens legend / toggle
            Rectangle {
                visible: chart.hasTokens
                implicitWidth: tokenLegend.implicitWidth + 18
                implicitHeight: 18
                radius: 5
                color: tokenLegendArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                RowLayout {
                    id: tokenLegend
                    anchors.centerIn: parent
                    spacing: 4
                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: chart.tokenColor
                        opacity: chart.showTokens ? 1.0 : 0.3
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: shell.i18n("Tokens (log)")
                        font.pixelSize: 10
                        opacity: chart.showTokens ? 0.65 : 0.3
                        color: chart.textColor
                    }
                }

                MouseArea {
                    id: tokenLegendArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (chart.showTokens && !chart.drawCost)
                            return;
                        chart.showTokens = !chart.showTokens;
                    }
                }
            }

            Text {
                visible: !chart.hasCost || !chart.hasTokens
                text: chart.hasCost ? shell.i18n("· no token history") : shell.i18n("· no cost history")
                font.pixelSize: 9
                opacity: 0.35
                color: chart.textColor
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Repeater {
            model: [
                {
                    label: shell.i18n("30d"),
                    days: 30
                },
                {
                    label: shell.i18n("90d"),
                    days: 90
                },
                {
                    label: shell.i18n("All"),
                    days: 0
                }
            ]
            Rectangle {
                required property var modelData
                implicitWidth: pillLabel.implicitWidth + 14
                implicitHeight: 20
                radius: 6
                color: chart.windowDays === modelData.days ? Qt.rgba(1, 1, 1, 0.14) : (pillArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)

                Text {
                    id: pillLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: 9
                    font.bold: chart.windowDays === modelData.days
                    color: chart.textColor
                    opacity: chart.windowDays === modelData.days ? 1.0 : 0.6
                }

                MouseArea {
                    id: pillArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chart.windowDaysSelected(modelData.days)
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 120

        Canvas {
            id: canvas
            anchors.fill: parent

            property var points: chart.points
            property color costColor: chart.costColor
            property color tokenColor: chart.tokenColor
            property int scrubIndex: -1

            readonly property real padTop: 6
            readonly property real padBottom: 16
            readonly property real padLeft: 2
            readonly property real padRight: 2
            readonly property real plotH: height - padTop - padBottom
            readonly property real plotW: width - padLeft - padRight

            readonly property real maxCost: {
                var m = 0;
                for (var i = 0; i < points.length; i++)
                    m = Math.max(m, points[i].usd || 0);
                return m > 0 ? m : 1;
            }
            readonly property real maxTokens: {
                var m = 0;
                for (var i = 0; i < points.length; i++)
                    m = Math.max(m, points[i].total || 0);
                return m > 1 ? m : 10;
            }
            // Real elapsed time, not array index: two points nine months
            // apart and two points a day apart both used to stretch across
            // the full chart width identically, drawing a smooth "trend"
            // through gaps where nothing was actually recorded.
            readonly property real minT: points.length ? dayEpoch(points[0].date) : 0
            readonly property real maxT: points.length ? dayEpoch(points[points.length - 1].date) : 1
            readonly property real tRange: Math.max(86400000, maxT - minT)
            // A handful of widely-spaced points is not a trend line yet —
            // drawn dashed so it reads as "sparse", not as a smooth climb.
            readonly property bool sparse: points.length > 0 && points.length < 5

            function dayEpoch(dateStr) {
                var t = Date.parse(dateStr + "T00:00:00Z");
                return isNaN(t) ? 0 : t;
            }
            function xFor(i) {
                if (points.length < 2)
                    return padLeft + plotW / 2;
                return padLeft + ((dayEpoch(points[i].date) - minT) / tRange) * plotW;
            }
            function yForCost(v) {
                return padTop + plotH * (1 - Math.max(0, v) / maxCost);
            }
            function yForTokens(v) {
                if (v <= 0)
                    return padTop + plotH;
                var logMax = Math.log(maxTokens);
                var logV = Math.log(Math.max(1, v));
                return padTop + plotH * (1 - Math.max(0, logV) / Math.max(1, logMax));
            }

            onPointsChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onScrubIndexChanged: requestPaint()

            readonly property bool drawCost: chart.drawCost
            readonly property bool drawTokens: chart.drawTokens
            onDrawCostChanged: requestPaint()
            onDrawTokensChanged: requestPaint()

            function buildPath(ctx, yFor, key) {
                ctx.moveTo(xFor(0), yFor(points[0][key] || 0));
                for (var i = 0; i < points.length - 1; i++) {
                    var x0 = xFor(i), y0 = yFor(points[i][key] || 0);
                    var x1 = xFor(i + 1), y1 = yFor(points[i + 1][key] || 0);
                    var cpx = x0 + (x1 - x0) * 0.5;
                    ctx.bezierCurveTo(cpx, y0, cpx, y1, x1, y1);
                }
            }

            // Glow pass — a few wide, faint strokes behind the crisp line,
            // matching UsageChart.qml's line style so every trend chart in
            // the app reads the same way.
            function strokePath(ctx, yFor, key, r, g, b) {
                if (points.length < 2)
                    return;
                function rgba(a) {
                    return "rgba(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + "," + a + ")";
                }
                ctx.save();
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                if (sparse)
                    ctx.setLineDash([5, 4]);
                [[0.10, 10], [0.22, 5], [1.0, 2]].forEach(function (pass) {
                    ctx.beginPath();
                    buildPath(ctx, yFor, key);
                    ctx.strokeStyle = rgba(pass[0]);
                    ctx.lineWidth = pass[1];
                    ctx.stroke();
                });
                ctx.restore();
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (points.length < 2)
                    return;

                // dashed baseline
                ctx.save();
                ctx.setLineDash([3, 5]);
                ctx.strokeStyle = "rgba(255,255,255,0.08)";
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(padLeft, padTop + plotH);
                ctx.lineTo(padLeft + plotW, padTop + plotH);
                ctx.stroke();
                ctx.restore();

                if (chart.drawTokens)
                    strokePath(ctx, yForTokens, "total", tokenColor.r, tokenColor.g, tokenColor.b);
                if (chart.drawCost)
                    strokePath(ctx, yForCost, "usd", costColor.r, costColor.g, costColor.b);

                if (scrubIndex >= 0 && scrubIndex < points.length) {
                    var sx = xFor(scrubIndex);
                    ctx.save();
                    ctx.strokeStyle = "rgba(255,255,255,0.18)";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(sx, padTop);
                    ctx.lineTo(sx, padTop + plotH);
                    ctx.stroke();
                    ctx.restore();
                    var dots = [];
                    if (chart.drawCost)
                        dots.push({
                            y: yForCost(points[scrubIndex].usd || 0),
                            color: costColor
                        });
                    if (chart.drawTokens)
                        dots.push({
                            y: yForTokens(points[scrubIndex].total || 0),
                            color: tokenColor
                        });
                    dots.forEach(function (dot) {
                        ctx.beginPath();
                        ctx.arc(sx, dot.y, 3, 0, Math.PI * 2);
                        ctx.fillStyle = dot.color;
                        ctx.fill();
                    });
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: mouse => {
                    if (canvas.points.length < 2)
                        return;
                    // Nearest point by actual x position, not by a uniform
                    // fraction-of-count guess — points are not evenly spaced
                    // in time.
                    var best = 0, bestDist = Infinity;
                    for (var i = 0; i < canvas.points.length; i++) {
                        var d = Math.abs(canvas.xFor(i) - mouse.x);
                        if (d < bestDist) {
                            bestDist = d;
                            best = i;
                        }
                    }
                    canvas.scrubIndex = best;
                }
                onExited: canvas.scrubIndex = -1
            }
        }
    }

    // ── Date axis ──
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: -2
        spacing: 0

        Repeater {
            model: chart.axisTicks
            Text {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                horizontalAlignment: index === 0 ? Text.AlignLeft : (index === chart.axisTicks.length - 1 ? Text.AlignRight : Text.AlignHCenter)
                text: modelData
                font.pixelSize: 9
                opacity: 0.35
                color: chart.textColor
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: chart.scrubIndex >= 0 && chart.scrubIndex < chart.points.length
        text: {
            if (chart.scrubIndex < 0 || chart.scrubIndex >= chart.points.length)
                return "";
            var p = chart.points[chart.scrubIndex];
            var parts = [p.date];
            if (chart.drawCost)
                parts.push("$" + Number(p.usd || 0).toFixed(2));
            if (chart.drawTokens)
                parts.push(Number(p.total || 0).toLocaleString(Qt.locale(), "f", 0) + " tok");
            return parts.join("  ·  ");
        }
        font.pixelSize: 10
        font.family: "monospace"
        opacity: 0.7
        color: chart.textColor
    }

    Text {
        Layout.fillWidth: true
        visible: !(chart.scrubIndex >= 0 && chart.scrubIndex < chart.points.length) && chart.points.length > 0 && chart.points.length < 5
        text: shell.i18n("Limited history (%1 days recorded) — dashed line, not a smoothed trend.", chart.points.length)
        font.pixelSize: 9
        opacity: 0.4
        color: chart.textColor
    }
}
