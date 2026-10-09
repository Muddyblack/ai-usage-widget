.pragma library

var RECONCILE_INTERVAL_MS = 600000;
var RESUME_GAP_MS = 90000;

function cacheExpired(ageSeconds) {
    return ageSeconds === null || ageSeconds === undefined || Number(ageSeconds) * 1000 >= RECONCILE_INTERVAL_MS;
}

function refreshDelayMs(ageSeconds, refreshStatus) {
    if (refreshStatus === "failed" || refreshStatus === "incomplete")
        return RECONCILE_INTERVAL_MS;
    if (ageSeconds === null || ageSeconds === undefined)
        return RECONCILE_INTERVAL_MS;
    if (Number(ageSeconds) * 1000 >= RECONCILE_INTERVAL_MS)
        return RECONCILE_INTERVAL_MS;
    return Math.max(1000, RECONCILE_INTERVAL_MS - Number(ageSeconds) * 1000);
}

function resumed(previousMs, nowMs) {
    return Number(previousMs) > 0 && Number(nowMs) - Number(previousMs) > RESUME_GAP_MS;
}
