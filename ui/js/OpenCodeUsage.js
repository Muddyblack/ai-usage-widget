// Local token ledgers adapted to the existing usage-history chart. Shared by
// Plasma and Hyprland/Windows; no provider-specific drawing code.

function seriesForRange(range, series, now) {
    var dailyTotals = {};
    (series || []).forEach(function (point) {
        if (!point || !/^\d{4}-\d{2}-\d{2}$/.test(point.date || ""))
            return;
        var total = typeof point.total === "number" && isFinite(point.total) ? point.total : 0;
        dailyTotals[point.date] = (dailyTotals[point.date] || 0) + total;
    });
    var dates = Object.keys(dailyTotals).sort();
    if (dates.length === 0)
        return [];

    function dateFromParts(date) {
        return new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)));
    }
    function formatLocalDate(date) {
        var month = String(date.getMonth() + 1).padStart(2, "0");
        var day = String(date.getDate()).padStart(2, "0");
        return date.getFullYear() + "-" + month + "-" + day;
    }
    function utcDay(date) {
        return Date.UTC(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10))) / 86400000;
    }

    var lastDate = formatLocalDate(new Date(now));
    var firstDate = range === "all" ? dates[0] : lastDate;
    if (range !== "all") {
        var windowDays = range === "30d" ? 30 : 7;
        var cutoff = dateFromParts(lastDate);
        cutoff.setDate(cutoff.getDate() - windowDays + 1);
        firstDate = formatLocalDate(cutoff);
    }
    if (firstDate > lastDate)
        return [];

    var spanDays = utcDay(lastDate) - utcDay(firstDate) + 1;
    var maxAllPoints = 366;
    var bucketDays = range === "all" ? Math.max(1, Math.ceil(spanDays / maxAllPoints)) : 1;
    var pointCount = Math.ceil(spanDays / bucketDays);
    var start = dateFromParts(firstDate);
    var output = [];
    for (var i = 0; i < pointCount; i++) {
        var pointDate = new Date(start.getTime());
        pointDate.setDate(pointDate.getDate() + i * bucketDays);
        var endDate = new Date(start.getTime());
        endDate.setDate(endDate.getDate() + Math.min(spanDays - 1, (i + 1) * bucketDays - 1));
        output.push({
            date: formatLocalDate(pointDate),
            endDate: bucketDays > 1 ? formatLocalDate(endDate) : undefined,
            total: 0
        });
    }
    dates.forEach(function (date) {
        if (date < firstDate || date > lastDate)
            return;
        var pointIndex = Math.floor((utcDay(date) - utcDay(firstDate)) / bucketDays);
        if (pointIndex >= 0 && pointIndex < output.length)
            output[pointIndex].total += dailyTotals[date];
    });
    return output;
}

function periodForRange(range, periods) {
    var list = periods || [];
    for (var i = 0; i < list.length; i++) {
        if (list[i].key === range)
            return list[i];
    }
    return {};
}

function dayTimestamp(date) {
    return new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10))).getTime();
}

function history(series) {
    return (series || []).filter(function (point) {
        return point && /^\d{4}-\d{2}-\d{2}$/.test(point.date || "") && typeof point.total === "number" && isFinite(point.total) && point.total >= 0;
    }).map(function (point) {
        return {t: dayTimestamp(point.date), tokens: point.total};
    }).sort(function (a, b) { return a.t - b.t; });
}

function chartWindows(series, now) {
    var points = history(series);
    var allSize = points.length ? Math.max(86400000, now - points[0].t) : 7 * 86400000;
    return [
        {id: "7d", key: "tokens", label: "7D", size: 7 * 86400000, granularity: "7d", raw: true, unit: "tokens", resets: false},
        {id: "30d", key: "tokens", label: "30D", size: 30 * 86400000, granularity: "30d", raw: true, unit: "tokens", resets: false},
        {id: "all", key: "tokens", label: "All", size: allSize, granularity: "all", raw: true, unit: "tokens", resets: false}
    ];
}

// Daily totals use a linear token scale. Keep the original value and covered
// dates for tooltips, even when the all-time range groups a long history.
function chartSeries(range, series, now, offset) {
    var points = seriesForRange(range, series, now - (offset || 0));
    var max = points.reduce(function (value, point) { return Math.max(value, point.total); }, 0);
    return points.map(function (point) {
        return {t: dayTimestamp(point.date), v: max > 0 ? point.total / max * 100 : 0, raw: point.total, date: point.date, endDate: point.endDate};
    });
}

function compactTokens(value) {
    if (value >= 1000000)
        return (value / 1000000).toFixed(1) + "M";
    if (value >= 1000)
        return (value / 1000).toFixed(1) + "k";
    return String(Math.round(value));
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        seriesForRange: seriesForRange,
        periodForRange: periodForRange,
        history: history,
        dayTimestamp: dayTimestamp,
        chartWindows: chartWindows,
        chartSeries: chartSeries,
        compactTokens: compactTokens
    };
}
