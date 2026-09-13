import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: usageChartContainer
    property Item rootItem

    readonly property bool isAntigravity: (rootItem.enabledTabs[rootItem.activeTab] || "") === "antigravity"
    readonly property bool hasModelFilter: isAntigravity && (rootItem.antigravityGooglePct !== undefined || rootItem.antigravityExternalPct !== undefined)
    readonly property bool isBoth: isAntigravity && rootItem.antigravityChartFilter === "both"

    readonly property var geminiHistory: isAntigravity ? rootItem.seriesForHistoryKey("agg", "ag") : []
    readonly property var restHistory: isAntigravity ? rootItem.seriesForHistoryKey("age", null) : []

    // The backend decides which providers have a chartable series, so the chart
    // simply shows whenever the active one reported a range and has data.
    visible: !rootItem.showSettings && rootItem.showUsageChart && rootItem.errorMsg === "" && rootItem.hasAnySeriesData() && rootItem.chartWindowsFor(rootItem.enabledTabs[rootItem.activeTab] || "").length > 0
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    implicitHeight: hasModelFilter ? 208 : 184
    radius: 10
    color: rootItem.resolvedCardBg
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    clip: true

    // subtle inner top highlight
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.rgba(1, 1, 1, 0.10)
        radius: 10
    }

    // ── Chart navigation (top-left) ──
    RowLayout {
        id: chartNavRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 7
        anchors.leftMargin: 12
        spacing: 6

        // Left arrow button
        Rectangle {
            radius: 4
            implicitHeight: 16
            implicitWidth: 16
            color: leftNavMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
            opacity: enabled ? 1.0 : 0.3
            enabled: {
                var key = rootItem._historyKey();
                var oldestT = 0;
                for (var i = 0; i < rootItem.usageHistory.length; i++) {
                    var p = rootItem.usageHistory[i];
                    if (p[key] !== undefined && p[key] !== null) {
                        oldestT = p.t;
                        break;
                    }
                }
                if (oldestT === 0)
                    return false;
                var now_ms = new Date().getTime();
                var winSize = rootItem.getChartWindowSize();
                var maxT = now_ms - rootItem.chartTimeOffset;
                var minT = maxT - winSize;
                return minT > oldestT;
            }
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: "<"
                font.pixelSize: 9
                font.bold: true
                color: Kirigami.Theme.textColor
            }
            MouseArea {
                id: leftNavMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    rootItem.chartTimeOffset += rootItem.getChartWindowSize();
                }
            }
        }

        // Center label showing current range
        PlasmaComponents.Label {
            text: rootItem.getChartRangeText()
            font.pixelSize: 9
            font.bold: true
            opacity: 0.6
            color: Kirigami.Theme.textColor
        }

        // Right arrow button
        Rectangle {
            radius: 4
            implicitHeight: 16
            implicitWidth: 16
            color: rightNavMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
            opacity: enabled ? 1.0 : 0.3
            enabled: rootItem.chartTimeOffset > 0
            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: ">"
                font.pixelSize: 9
                font.bold: true
                color: Kirigami.Theme.textColor
            }
            MouseArea {
                id: rightNavMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    var winSize = rootItem.getChartWindowSize();
                    rootItem.chartTimeOffset = Math.max(0, rootItem.chartTimeOffset - winSize);
                }
            }
        }
    }

    // ── Window toggle — Claude: 5H/7D, Codex: 5H/7D (single-series tabs: hidden) ──
    RowLayout {
        id: chartWindowToggle
        readonly property var choices: rootItem.chartWindowsFor(rootItem.enabledTabs[rootItem.activeTab] || "")
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 7
        anchors.rightMargin: 8
        spacing: 4
        visible: choices.length > 1
        Repeater {
            model: chartWindowToggle.choices
            Rectangle {
                radius: 4
                implicitHeight: 16
                implicitWidth: winLabel.implicitWidth + 12
                color: rootItem.chartWindow === modelData.id ? rootItem.activeAccent : Qt.rgba(1, 1, 1, 0.06)
                opacity: rootItem.chartWindow === modelData.id ? 0.9 : 1.0
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                PlasmaComponents.Label {
                    id: winLabel
                    anchors.centerIn: parent
                    text: rootItem.windowLabel(modelData.label)
                    font.pixelSize: 9
                    font.bold: rootItem.chartWindow === modelData.id
                    // Near-white accents (Grok, Cursor) would swallow white text.
                    color: rootItem.chartWindow === modelData.id ? ((0.299 * rootItem.activeAccent.r + 0.587 * rootItem.activeAccent.g + 0.114 * rootItem.activeAccent.b) > 0.6 ? "#1a1a1a" : "#ffffff") : Kirigami.Theme.textColor
                    opacity: rootItem.chartWindow === modelData.id ? 1.0 : 0.6
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        rootItem.chartWindow = modelData.id;
                        Plasmoid.configuration.chartWindow = modelData.id;
                        // Remember the granularity so it carries to other tabs
                        var gran = modelData.granularity;
                        if (gran !== "") {
                            rootItem.chartGranularity = gran;
                            Plasmoid.configuration.chartGranularity = gran;
                        }
                    }
                }
            }
        }
    }

    // ── Antigravity model filter (Both / Combined / Gemini / Rest) ──
    RowLayout {
        id: modelFilterRow
        visible: usageChartContainer.hasModelFilter
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 29
        anchors.leftMargin: 36
        spacing: 4

        readonly property var options: [
            {
                id: "both",
                label: i18n("Both"),
                dotColor: ""
            },
            {
                id: "combined",
                label: i18n("Combined"),
                dotColor: ""
            },
            {
                id: "gemini",
                label: "Gemini",
                dotColor: rootItem.googleBlue
            },
            {
                id: "rest",
                label: i18nc("quota model", "Rest"),
                dotColor: rootItem.googleGreen
            }
        ]

        Repeater {
            model: modelFilterRow.options
            Rectangle {
                required property var modelData
                radius: 4
                implicitHeight: 16
                implicitWidth: filterPillContent.implicitWidth + 12
                color: rootItem.antigravityChartFilter === modelData.id ? rootItem.activeAccent : Qt.rgba(1, 1, 1, 0.06)
                opacity: rootItem.antigravityChartFilter === modelData.id ? 0.9 : 1.0
                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
                RowLayout {
                    id: filterPillContent
                    anchors.centerIn: parent
                    spacing: 4
                    Rectangle {
                        visible: modelData.dotColor !== ""
                        width: 5
                        height: 5
                        radius: 2.5
                        color: modelData.dotColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                    PlasmaComponents.Label {
                        text: rootItem.windowLabel(modelData.label)
                        font.pixelSize: 9
                        font.bold: rootItem.antigravityChartFilter === modelData.id
                        color: rootItem.antigravityChartFilter === modelData.id ? "#ffffff" : Kirigami.Theme.textColor
                        opacity: rootItem.antigravityChartFilter === modelData.id ? 1.0 : 0.65
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        rootItem.antigravityChartFilter = modelData.id;
                        Plasmoid.configuration.antigravityChartFilter = modelData.id;
                    }
                }
            }
        }
    }

    // Y-axis labels. For most windows the axis is a 0-100% scale; for the mistral
    // (cost) window it's auto-scaled to the window's max spend, so labels show $.
    readonly property real chartMaxRaw: {
        var win = rootItem.currentChartWindow();
        if (!win || !win.raw)
            return 0;
        var pts = rootItem.weeklyUsageHistory;
        var m = 0;
        for (var i = 0; i < pts.length; i++)
            if (pts[i].raw !== undefined && pts[i].raw > m)
                m = pts[i].raw;
        return m;
    }
    function chartYLabel(fraction) {
        var win = rootItem.currentChartWindow();
        if (win && win.raw) {
            if (win.key === "mv" || rootItem.chartWindow.indexOf("mistral") === 0)
                return chartMaxRaw > 0 ? "$" + (chartMaxRaw * fraction).toFixed(2) : "";
            if (win.key === "ds" || rootItem.chartWindow.indexOf("deepseek") === 0)
                return chartMaxRaw > 0 ? rootItem.formatMoney(chartMaxRaw * fraction, rootItem.deepseekPrimaryCurrency) : "";
        }
        return Math.round(fraction * 100) + "%";
    }

    // Timestamps where a reset happened inside the visible window
    readonly property bool windowHasResets: {
        var win = rootItem.currentChartWindow();
        return win ? win.resets === true : false;
    }
    readonly property var resetTimestamps: {
        if (!windowHasResets)
            return [];
        var pts = rootItem.weeklyUsageHistory;
        var out = [];
        for (var i = 1; i < pts.length; i++)
            if (pts[i - 1].v - pts[i].v > 6)
                out.push(pts[i].t);
        return out;
    }
    PlasmaComponents.Label {
        anchors.right: chartCanvas.left
        anchors.rightMargin: 4
        y: chartCanvas.y + 2
        text: usageChartContainer.chartYLabel(1.0)
        font.pixelSize: 9
        opacity: 0.35
        color: Kirigami.Theme.textColor
    }
    PlasmaComponents.Label {
        anchors.right: chartCanvas.left
        anchors.rightMargin: 4
        y: chartCanvas.y + chartCanvas.height / 2 - 6
        text: usageChartContainer.chartYLabel(0.5)
        font.pixelSize: 9
        opacity: 0.35
        color: Kirigami.Theme.textColor
    }
    PlasmaComponents.Label {
        anchors.right: chartCanvas.left
        anchors.rightMargin: 4
        y: chartCanvas.y + chartCanvas.height - 14
        text: usageChartContainer.chartYLabel(0.0)
        font.pixelSize: 9
        opacity: 0.35
        color: Kirigami.Theme.textColor
    }

    Canvas {
        id: chartCanvas
        anchors.top: parent.top
        anchors.bottom: xAxisRow.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 36
        anchors.rightMargin: 8
        anchors.topMargin: usageChartContainer.hasModelFilter ? 52 : 28
        anchors.bottomMargin: 2

        property var history: rootItem.weeklyUsageHistory
        property var geminiHistory: usageChartContainer.geminiHistory
        property var restHistory: usageChartContainer.restHistory
        property bool isBoth: usageChartContainer.isBoth
        property color accentColor: rootItem.activeAccent
        // pulse phase 0..1, driven while usage is climbing fast; scales the latest dot's halo
        property real pulse: 0
        // hover-scrub index into history (-1 = none)
        property int scrubIndex: -1
        property var scrubGeminiPt: null
        property var scrubRestPt: null
        property real scrubTimestamp: 0

        onHistoryChanged: requestPaint()
        onGeminiHistoryChanged: requestPaint()
        onRestHistoryChanged: requestPaint()
        onIsBothChanged: requestPaint()
        onAccentColorChanged: requestPaint()
        onPulseChanged: requestPaint()
        onScrubIndexChanged: requestPaint()
        // Both mode keeps scrubIndex at 0 while the selected points move.
        onScrubGeminiPtChanged: requestPaint()
        onScrubRestPtChanged: requestPaint()
        onScrubTimestampChanged: requestPaint()
        onVisibleChanged: if (visible)
            requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        // Pulse when the selected window is climbing >2%/h
        readonly property bool climbingFast: {
            var key = rootItem._historyKey();
            var slope = rootItem.usageSlopePerHour(key, 2 * 3600000);
            return slope !== null && slope > 2;
        }
        SequentialAnimation on pulse {
            running: chartCanvas.climbingFast && chartCanvas.visible
            loops: Animation.Infinite
            NumberAnimation {
                from: 0
                to: 1
                duration: 900
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                from: 1
                to: 0
                duration: 900
                easing.type: Easing.InOutSine
            }
        }
        onClimbingFastChanged: if (!climbingFast)
            pulse = 0

        PlasmaComponents.Label {
            anchors.centerIn: parent
            visible: (!chartCanvas.isBoth && (!chartCanvas.history || chartCanvas.history.length === 0)) || (chartCanvas.isBoth && (!chartCanvas.geminiHistory || chartCanvas.geminiHistory.length === 0) && (!chartCanvas.restHistory || chartCanvas.restHistory.length === 0))
            text: i18n("No data in this range")
            font.pixelSize: 11
            opacity: 0.5
            color: Kirigami.Theme.textColor
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var w = width, h = height;
            var now_ms = new Date().getTime();
            var maxT = now_ms - rootItem.chartTimeOffset;
            var minT = maxT - rootItem.getChartWindowSize();
            var tRange = rootItem.getChartWindowSize();

            // dashed grid lines at 25 / 50 / 75 / 100%
            ctx.save();
            ctx.setLineDash([3, 5]);
            ctx.strokeStyle = "rgba(255,255,255,0.08)";
            ctx.lineWidth = 1;
            [25, 50, 75, 100].forEach(function (pct) {
                var y = h - (pct / 100) * h * 0.88 - h * 0.04;
                ctx.beginPath();
                ctx.moveTo(0, y);
                ctx.lineTo(w, y);
                ctx.stroke();
            });
            ctx.restore();

            function drawCurve(seriesPts, strokeColor, showFill) {
                if (!seriesPts || seriesPts.length < 1)
                    return;

                function spx(i) {
                    return ((seriesPts[i].t - minT) / tRange) * w;
                }
                function spy(v) {
                    return h - (v / 100) * h * 0.88 - h * 0.04;
                }

                var rR = Math.round(strokeColor.r * 255);
                var rG = Math.round(strokeColor.g * 255);
                var rB = Math.round(strokeColor.b * 255);
                function sRgba(a) {
                    return "rgba(" + rR + "," + rG + "," + rB + "," + a + ")";
                }

                if (seriesPts.length === 1) {
                    var sx = w / 2, sy = spy(seriesPts[0].v);
                    ctx.beginPath();
                    ctx.arc(sx, sy, 7, 0, Math.PI * 2);
                    ctx.fillStyle = sRgba(0.18);
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(sx, sy, 4, 0, Math.PI * 2);
                    ctx.fillStyle = sRgba(1.0);
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(sx, sy, 1.8, 0, Math.PI * 2);
                    ctx.fillStyle = "rgba(255,255,255,0.9)";
                    ctx.fill();
                    return;
                }

                function sBuildPath() {
                    ctx.moveTo(spx(0), spy(seriesPts[0].v));
                    for (var i = 0; i < seriesPts.length - 1; i++) {
                        var x0 = spx(i), y0 = spy(seriesPts[i].v);
                        var x1 = spx(i + 1), y1 = spy(seriesPts[i + 1].v);
                        var cpx = x0 + (x1 - x0) * 0.5;
                        ctx.bezierCurveTo(cpx, y0, cpx, y1, x1, y1);
                    }
                }

                // glow pass
                ctx.save();
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.beginPath();
                sBuildPath();
                ctx.strokeStyle = sRgba(0.08);
                ctx.lineWidth = 14;
                ctx.stroke();
                ctx.beginPath();
                sBuildPath();
                ctx.strokeStyle = sRgba(0.18);
                ctx.lineWidth = 8;
                ctx.stroke();
                ctx.beginPath();
                sBuildPath();
                ctx.strokeStyle = sRgba(0.40);
                ctx.lineWidth = 4;
                ctx.stroke();
                ctx.restore();

                // filled gradient area
                if (showFill) {
                    var grad = ctx.createLinearGradient(0, 0, 0, h);
                    grad.addColorStop(0, sRgba(0.24));
                    grad.addColorStop(0.6, sRgba(0.06));
                    grad.addColorStop(1, sRgba(0.0));
                    ctx.beginPath();
                    sBuildPath();
                    ctx.lineTo(spx(seriesPts.length - 1), h);
                    ctx.lineTo(spx(0), h);
                    ctx.closePath();
                    ctx.fillStyle = grad;
                    ctx.fill();
                }

                // crisp line on top
                ctx.beginPath();
                sBuildPath();
                ctx.strokeStyle = sRgba(1.0);
                ctx.lineWidth = 2;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.stroke();

                // latest point dot
                var lx = spx(seriesPts.length - 1);
                var ly = spy(seriesPts[seriesPts.length - 1].v);
                var haloR = 7 + pulse * 8;
                var haloA = 0.18 + (1 - pulse) * 0.10;
                ctx.beginPath();
                ctx.arc(lx, ly, haloR, 0, Math.PI * 2);
                ctx.fillStyle = sRgba(pulse > 0 ? haloA * (1 - pulse) + 0.06 : 0.18);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(lx, ly, 4, 0, Math.PI * 2);
                ctx.fillStyle = sRgba(1.0);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(lx, ly, 1.8, 0, Math.PI * 2);
                ctx.fillStyle = "rgba(255,255,255,0.9)";
                ctx.fill();
            }

            if (chartCanvas.isBoth) {
                drawCurve(chartCanvas.geminiHistory, rootItem.googleBlue, true);
                drawCurve(chartCanvas.restHistory, rootItem.googleGreen, false);
            } else {
                drawCurve(chartCanvas.history, accentColor, true);
            }

            // ── Reset-boundary markers ───────────────────────────
            function drawResetLine(resetMs, label, drawLabel) {
                var rx = ((resetMs - minT) / tRange) * w;
                ctx.save();
                ctx.setLineDash([2, 4]);
                ctx.strokeStyle = "rgba(255,255,255,0.22)";
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(rx, 12);
                ctx.lineTo(rx, h);
                ctx.stroke();
                ctx.restore();
                if (drawLabel) {
                    ctx.save();
                    ctx.font = "9px sans-serif";
                    ctx.fillStyle = "rgba(255,255,255,0.45)";
                    var tw = ctx.measureText(label).width;
                    var tx = Math.min(Math.max(rx + 3, 0), w - tw);
                    ctx.fillText(label, tx, 9);
                    ctx.restore();
                }
                ctx.save();
                ctx.beginPath();
                ctx.arc(rx, h, 2, 0, Math.PI * 2);
                var acR = Math.round(accentColor.r * 255);
                var acG = Math.round(accentColor.g * 255);
                var acB = Math.round(accentColor.b * 255);
                ctx.fillStyle = "rgba(" + acR + "," + acG + "," + acB + ",0.85)";
                ctx.fill();
                ctx.restore();
            }
            var resets = usageChartContainer.resetTimestamps;
            var resetLabel = rootItem.chartWindow === "weekly" || rootItem.chartWindow === "codex_weekly" ? i18nc("chart reset window", "week reset") : i18nc("chart reset window", "5h reset");
            var labelDrawn = false;
            for (var ri = resets.length - 1; ri >= 0; ri--) {
                var rt = resets[ri];
                if (rt > minT && rt < maxT) {
                    drawResetLine(rt, resetLabel, !labelDrawn);
                    labelDrawn = true;
                }
            }

            // hover scrub: vertical guide + highlighted point(s)
            if (scrubIndex >= 0) {
                function drawScrubDot(pt, color) {
                    var hx = ((pt.t - minT) / tRange) * w;
                    var hy = h - (pt.v / 100) * h * 0.88 - h * 0.04;
                    var cR = Math.round(color.r * 255);
                    var cG = Math.round(color.g * 255);
                    var cB = Math.round(color.b * 255);
                    ctx.beginPath();
                    ctx.arc(hx, hy, 5, 0, Math.PI * 2);
                    ctx.fillStyle = "rgba(" + cR + "," + cG + "," + cB + ",1.0)";
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(hx, hy, 2, 0, Math.PI * 2);
                    ctx.fillStyle = "#ffffff";
                    ctx.fill();
                }

                var scrubT = chartCanvas.scrubTimestamp;
                if (scrubT > 0) {
                    var hx = ((scrubT - minT) / tRange) * w;
                    ctx.save();
                    ctx.setLineDash([2, 3]);
                    var acR = Math.round(accentColor.r * 255);
                    var acG = Math.round(accentColor.g * 255);
                    var acB = Math.round(accentColor.b * 255);
                    ctx.strokeStyle = chartCanvas.isBoth ? "rgba(255,255,255,0.4)" : "rgba(" + acR + "," + acG + "," + acB + ",0.5)";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(hx, 0);
                    ctx.lineTo(hx, h);
                    ctx.stroke();
                    ctx.restore();

                    if (chartCanvas.isBoth) {
                        if (chartCanvas.scrubGeminiPt)
                            drawScrubDot(chartCanvas.scrubGeminiPt, rootItem.googleBlue);
                        if (chartCanvas.scrubRestPt)
                            drawScrubDot(chartCanvas.scrubRestPt, rootItem.googleGreen);
                    } else if (chartCanvas.history && scrubIndex < chartCanvas.history.length) {
                        drawScrubDot(chartCanvas.history[scrubIndex], accentColor);
                    }
                }
            }
        }

        // ── Hover scrub ──────────────────────────────────────
        MouseArea {
            id: scrubArea
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: function (mouse) {
                var now_ms = new Date().getTime();
                var maxT = now_ms - rootItem.chartTimeOffset;
                var tRange = rootItem.getChartWindowSize();
                var minT = maxT - tRange;
                var mouseT = minT + (mouse.x / chartCanvas.width) * tRange;

                if (chartCanvas.isBoth) {
                    var gPts = chartCanvas.geminiHistory;
                    var rPts = chartCanvas.restHistory;
                    if ((!gPts || gPts.length === 0) && (!rPts || rPts.length === 0)) {
                        chartCanvas.scrubIndex = -1;
                        return;
                    }
                    function findClosest(pts) {
                        if (!pts || pts.length === 0)
                            return null;
                        var b = 0, bd = Math.abs(pts[0].t - mouseT);
                        for (var i = 1; i < pts.length; i++) {
                            var d = Math.abs(pts[i].t - mouseT);
                            if (d < bd) {
                                bd = d;
                                b = i;
                            }
                        }
                        return pts[b];
                    }
                    chartCanvas.scrubGeminiPt = findClosest(gPts);
                    chartCanvas.scrubRestPt = findClosest(rPts);
                    chartCanvas.scrubTimestamp = chartCanvas.scrubGeminiPt ? chartCanvas.scrubGeminiPt.t : (chartCanvas.scrubRestPt ? chartCanvas.scrubRestPt.t : 0);
                    chartCanvas.scrubIndex = 0;
                } else {
                    var pts = chartCanvas.history;
                    if (!pts || pts.length < 1) {
                        chartCanvas.scrubIndex = -1;
                        return;
                    }
                    var best = 0, bestDist = Math.abs(pts[0].t - mouseT);
                    for (var i = 1; i < pts.length; i++) {
                        var d = Math.abs(pts[i].t - mouseT);
                        if (d < bestDist) {
                            bestDist = d;
                            best = i;
                        }
                    }
                    chartCanvas.scrubIndex = best;
                    chartCanvas.scrubTimestamp = pts[best].t;
                }
            }
            onExited: {
                chartCanvas.scrubIndex = -1;
                chartCanvas.scrubGeminiPt = null;
                chartCanvas.scrubRestPt = null;
                chartCanvas.scrubTimestamp = 0;
            }

            // Custom tooltip positioned near the scrub dot
            Rectangle {
                id: scrubTooltip
                visible: chartCanvas.scrubIndex >= 0
                color: Qt.rgba(0, 0, 0, 0.72)
                border.color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                radius: 6
                width: (chartCanvas.isBoth ? bothTooltipRow.implicitWidth : tooltipRow.implicitWidth) + 14
                height: (chartCanvas.isBoth ? bothTooltipRow.implicitHeight : tooltipRow.implicitHeight) + 8

                property real dotX: {
                    var now_ms = new Date().getTime();
                    var maxT = now_ms - rootItem.chartTimeOffset;
                    var tRange = rootItem.getChartWindowSize();
                    var minT = maxT - tRange;
                    var t = chartCanvas.scrubTimestamp;
                    if (!t)
                        return 0;
                    return ((t - minT) / tRange) * chartCanvas.width;
                }
                property real dotY: {
                    if (chartCanvas.isBoth) {
                        var gPt = chartCanvas.scrubGeminiPt;
                        var rPt = chartCanvas.scrubRestPt;
                        var v = gPt ? gPt.v : (rPt ? rPt.v : 50);
                        var h = chartCanvas.height;
                        return h - (v / 100) * h * 0.88 - h * 0.04;
                    }
                    var pts = chartCanvas.history;
                    if (chartCanvas.scrubIndex < 0 || !pts || chartCanvas.scrubIndex >= pts.length)
                        return 0;
                    var v = pts[chartCanvas.scrubIndex].v;
                    var h = chartCanvas.height;
                    return h - (v / 100) * h * 0.88 - h * 0.04;
                }

                x: Math.max(0, Math.min(dotX - width / 2, chartCanvas.width - width - 4))
                y: Math.max(4, dotY - height - 8)

                Row {
                    id: tooltipRow
                    visible: !chartCanvas.isBoth
                    anchors.centerIn: parent
                    spacing: 0

                    PlasmaComponents.Label {
                        text: {
                            var pts = chartCanvas.history;
                            if (chartCanvas.scrubIndex < 0 || !pts || chartCanvas.scrubIndex >= pts.length)
                                return "";
                            var pt = pts[chartCanvas.scrubIndex];
                            var win = rootItem.currentChartWindow();
                            if (win && win.raw) {
                                if (win.key === "mv" || rootItem.chartWindow.indexOf("mistral") === 0)
                                    return "$" + (pt.raw !== undefined ? pt.raw : 0).toFixed(4);
                                if (win.key === "ds" || rootItem.chartWindow.indexOf("deepseek") === 0)
                                    return rootItem.formatMoney(pt.raw !== undefined ? pt.raw : 0, rootItem.deepseekPrimaryCurrency);
                            }
                            return Math.round(pt.v) + "%";
                        }
                        font.pixelSize: 11
                        font.bold: true
                        color: rootItem.activeAccent
                    }
                    PlasmaComponents.Label {
                        text: {
                            var pts = chartCanvas.history;
                            if (chartCanvas.scrubIndex < 0 || !pts || chartCanvas.scrubIndex >= pts.length)
                                return "";
                            return "  ·  " + Qt.formatDateTime(new Date(pts[chartCanvas.scrubIndex].t), "MMM d, hh:mm");
                        }
                        font.pixelSize: 11
                        color: Kirigami.Theme.textColor
                        opacity: 0.75
                    }
                }

                RowLayout {
                    id: bothTooltipRow
                    visible: chartCanvas.isBoth
                    anchors.centerIn: parent
                    spacing: 4

                    RowLayout {
                        spacing: 3
                        visible: chartCanvas.scrubGeminiPt !== null
                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            color: rootItem.googleBlue
                            Layout.alignment: Qt.AlignVCenter
                        }
                        PlasmaComponents.Label {
                            text: chartCanvas.scrubGeminiPt ? i18n("Gemini: %1%", Math.round(chartCanvas.scrubGeminiPt.v)) : ""
                            font.pixelSize: 11
                            font.bold: true
                            color: rootItem.googleBlue
                        }
                    }

                    PlasmaComponents.Label {
                        visible: chartCanvas.scrubGeminiPt !== null && chartCanvas.scrubRestPt !== null
                        text: "·"
                        font.pixelSize: 11
                        color: Kirigami.Theme.textColor
                        opacity: 0.4
                    }

                    RowLayout {
                        spacing: 3
                        visible: chartCanvas.scrubRestPt !== null
                        Rectangle {
                            width: 5
                            height: 5
                            radius: 2.5
                            color: rootItem.googleGreen
                            Layout.alignment: Qt.AlignVCenter
                        }
                        PlasmaComponents.Label {
                            text: chartCanvas.scrubRestPt ? i18n("Rest: %1%", Math.round(chartCanvas.scrubRestPt.v)) : ""
                            font.pixelSize: 11
                            font.bold: true
                            color: rootItem.googleGreen
                        }
                    }

                    PlasmaComponents.Label {
                        text: "  ·  " + Qt.formatDateTime(new Date(chartCanvas.scrubTimestamp), "MMM d, hh:mm")
                        font.pixelSize: 11
                        color: Kirigami.Theme.textColor
                        opacity: 0.75
                    }
                }
            }
        }
    }

    // X-axis date labels — evenly spaced ticks across the window.
    RowLayout {
        id: xAxisRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.rightMargin: 8
        anchors.bottomMargin: 5
        spacing: 0

        // Only the two window endpoints are fixed labels; the reset-time labels
        // drawn on the canvas carry the detail, so interior ticks would just
        // collide with them. Keeps the axis clean.
        readonly property int tickCount: 2

        // Hourly windows show time; wide (multi-day) windows show date + time so
        // a label like "Jun 2" isn't ambiguous about which part of the day it is.
        readonly property bool hourlyWindow: rootItem.chartWindow === "session" || rootItem.chartWindow === "codex_primary" || rootItem.chartWindow === "day" || rootItem.chartWindow === "codex_day"

        function formatLabel(timestamp) {
            var d = new Date(timestamp);
            if (hourlyWindow)
                return Qt.formatTime(d, "hh:mm");
            // wide window: stack date over time so labels stay narrow
            return Qt.formatDate(d, "MMM d") + "\n" + Qt.formatTime(d, "hh:mm");
        }

        // True when a reset label sits within ~10% of this endpoint's position,
        // so the endpoint hides and the (more meaningful) reset time wins.
        function endpointCrowded(endpointFrac) {
            var resets = usageChartContainer.resetTimestamps;
            var now_ms = new Date().getTime();
            var winSize = rootItem.getChartWindowSize();
            var minT = (now_ms - rootItem.chartTimeOffset) - winSize;
            for (var i = 0; i < resets.length; i++) {
                var f = (resets[i] - minT) / winSize;
                if (f > 0 && f < 1 && Math.abs(f - endpointFrac) < 0.1)
                    return true;
            }
            return false;
        }

        Repeater {
            model: xAxisRow.tickCount
            delegate: RowLayout {
                readonly property real frac: index / (xAxisRow.tickCount - 1)
                Layout.fillWidth: index > 0
                spacing: 0
                // spacer pushes each label to its proportional position
                Item {
                    Layout.fillWidth: index > 0
                }
                PlasmaComponents.Label {
                    visible: !xAxisRow.endpointCrowded(parent.frac)
                    text: {
                        var now_ms = new Date().getTime();
                        var maxT = now_ms - rootItem.chartTimeOffset;
                        var winSize = rootItem.getChartWindowSize();
                        var minT = maxT - winSize;
                        return xAxisRow.formatLabel(minT + winSize * parent.frac);
                    }
                    font.pixelSize: 9
                    opacity: 0.40
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 0.9
                    color: Kirigami.Theme.textColor
                }
            }
        }
    }

    // Reset-time labels — sit on the same baseline as the endpoint labels, each
    // centered under its reset line on the chart. Accent-colored so they read as
    // the meaningful markers rather than the dim endpoint times.
    Item {
        id: resetLabelsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.rightMargin: 8
        anchors.bottomMargin: 5
        height: xAxisRow.height

        Repeater {
            model: usageChartContainer.resetTimestamps
            delegate: PlasmaComponents.Label {
                readonly property real frac: {
                    var now_ms = new Date().getTime();
                    var winSize = rootItem.getChartWindowSize();
                    var maxT = now_ms - rootItem.chartTimeOffset;
                    var minT = maxT - winSize;
                    return (modelData - minT) / winSize;
                }
                visible: frac > 0 && frac < 1
                text: rootItem.chartWindow === "weekly" || rootItem.chartWindow === "codex_weekly" ? Qt.formatDate(new Date(modelData), "MMM d") : Qt.formatTime(new Date(modelData), "hh:mm")
                font.pixelSize: 9
                color: rootItem.activeAccent
                opacity: 0.85
                // center under the reset line, clamped inside the row
                x: Math.max(0, Math.min(frac * resetLabelsRow.width - implicitWidth / 2, resetLabelsRow.width - implicitWidth))
            }
        }
    }
}
