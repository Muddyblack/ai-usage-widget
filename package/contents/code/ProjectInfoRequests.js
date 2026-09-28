// One client per Info pane. The visible pane drives tick(); no background polling.
function create(project, makeRequest, now, publish) {
    var entries = [{id: "release", url: project.latestReleaseUrl}]
        .concat(project.statistics)
        .concat([{id: "contributors", url: project.contributorsUrl}])
        .map(function (entry) {
            return {id: entry.id, url: entry.url, attempts: 0, due: 0,
                done: false, request: null, started: 0, blockedUntil: 0};
        });
    var counts = {}, contributors = [], latestVersion = "";
    var releaseState = "Not checked", lastRefresh = null, disposed = false, previousState = "";

    function busy() {
        return entries.some(function (entry) { return entry.request !== null; });
    }
    function canRefresh() {
        return !disposed && !busy() && (lastRefresh === null || now() - lastRefresh >= 60000);
    }
    function update() {
        if (disposed) return;
        var state = {counts: Object.assign({}, counts), contributors: contributors,
            latestVersion: latestVersion, releaseState: releaseState, canRefresh: canRefresh()};
        var signature = JSON.stringify(state);
        if (signature !== previousState) {
            previousState = signature;
            publish(state);
        }
    }
    function finish(entry, success) {
        entry.request.onreadystatechange = null;
        entry.request = null;
        entry.done = success;
        entry.due = now() + (entry.attempts === 1 ? 15000 : 60000);
        if (entry.id === "release")
            releaseState = success ? "Checked" : "Could not check for updates";
        update();
    }
    function start(entry) {
        var request = makeRequest();
        entry.request = request;
        entry.started = now();
        entry.attempts++;
        if (entry.id === "release") releaseState = "Checking…";
        try {
            request.open("GET", entry.url);
            request.onreadystatechange = function () {
                if (disposed || entry.request !== request || request.readyState !== 4) return;
                var success = false;
                if (request.status === 200) {
                    if (entry.id === "release") {
                        var version = project.releaseVersion(request.responseText);
                        if (version) { latestVersion = version; success = true; }
                    } else if (entry.id === "contributors") {
                        try {
                            // An empty array is a valid successful response.
                            if (Array.isArray(JSON.parse(request.responseText))) {
                                contributors = project.contributors(request.responseText);
                                success = true;
                            }
                        } catch (error) {}
                    } else {
                        var value = project.count(request.responseText);
                        if (value) { counts[entry.id] = value; success = true; }
                    }
                }
                // Do not automatically retry HTTP client errors, including rate limits.
                if (request.status >= 400 && request.status < 500) {
                    entry.attempts = 3;
                    var retryAfter = request.getResponseHeader("Retry-After");
                    var delay = Number(retryAfter);
                    entry.blockedUntil = Math.max(now() + 60000,
                        retryAfter ? (Number.isFinite(delay) ? now() + delay * 1000 : Date.parse(retryAfter) || 0) : 0);
                }
                finish(entry, success);
            };
            request.send();
        } catch (error) {
            if (entry.request === request) {
                finish(entry, false);
                request.abort();
            }
        }
    }
    function tick() {
        if (disposed) return;
        if (lastRefresh === null) lastRefresh = now();
        entries.forEach(function (entry) {
            if (entry.request && now() - entry.started >= 8000) {
                var request = entry.request;
                finish(entry, false);
                request.abort();
            } else if (!entry.request && !entry.done && entry.attempts < 3
                       && now() >= entry.due && now() >= entry.blockedUntil) {
                start(entry);
            }
        });
        update();
    }
    function refresh() {
        if (!canRefresh()) return;
        lastRefresh = now();
        entries.forEach(function (entry) {
            entry.done = false;
            entry.attempts = 0;
            entry.due = now();
        });
        tick();
    }
    function pause() {
        entries.forEach(function (entry) {
            if (!entry.request) return;
            var request = entry.request;
            finish(entry, false);
            request.abort();
        });
    }
    return {tick: tick, refresh: refresh, pause: pause,
        dispose: function () { disposed = true; pause(); }};
}

if (typeof module !== "undefined" && module.exports)
    module.exports = {create: create};
