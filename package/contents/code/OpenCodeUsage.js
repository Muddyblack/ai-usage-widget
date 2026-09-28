// Daily OpenCode token usage for the 7D / 30D / All range pills, shared by
// the Plasma tab and the Hyprland/Windows popup so both draw the same series.

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

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        seriesForRange: seriesForRange,
        periodForRange: periodForRange
    };
}
