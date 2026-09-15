.pragma library

// Optional popup views that sit ahead of provider tabs when enabled —
// Overview, Usage & Spend, and Sessions. Shared by every frontend so the
// toggles, labels and defaults stay in lockstep.

var FEATURE_TAB_IDS = ["overview", "spend", "sessions"];

// Defaults: Sessions on; Overview and Spend off until the user opts in.
function defaultEnabled(id) {
    return id === "sessions";
}

function settingKey(id) {
    return id + "Enabled";
}

function label(id, i18nFn) {
    if (id === "overview")
        return i18nFn ? i18nFn("Overview") : "Overview";
    if (id === "spend")
        return i18nFn ? i18nFn("Usage & Spend") : "Usage & Spend";
    if (id === "sessions")
        return i18nFn ? i18nFn("Sessions") : "Sessions";
    return id;
}

function isFeatureTab(id) {
    return FEATURE_TAB_IDS.indexOf(id) !== -1;
}

// Whether a feature tab is on, given a settings/config object that stores
// top-level booleans named overviewEnabled / spendEnabled / sessionsEnabled.
function enabled(settings, id) {
    if (!isFeatureTab(id))
        return false;
    var key = settingKey(id);
    if (settings && settings[key] !== undefined && settings[key] !== null)
        return settings[key] === true;
    return defaultEnabled(id);
}

// Plasma configuration uses the same key names as the shared JSON file.
function plasmoidEnabled(configuration, id) {
    if (!isFeatureTab(id))
        return false;
    var key = settingKey(id);
    if (configuration && configuration[key] !== undefined)
        return configuration[key] === true;
    return defaultEnabled(id);
}

function enabledFeatureTabs(settings) {
    var out = [];
    for (var i = 0; i < FEATURE_TAB_IDS.length; i++) {
        var id = FEATURE_TAB_IDS[i];
        if (enabled(settings, id))
            out.push(id);
    }
    return out;
}

function enabledFeatureTabsPlasmoid(configuration) {
    var out = [];
    for (var i = 0; i < FEATURE_TAB_IDS.length; i++) {
        var id = FEATURE_TAB_IDS[i];
        if (plasmoidEnabled(configuration, id))
            out.push(id);
    }
    return out;
}

// Accent used when a feature tab is active (theme highlight falls through
// on the caller when this returns "").
function accent(id) {
    if (id === "overview")
        return "#38bdf8";
    if (id === "spend")
        return "#34d399";
    if (id === "sessions")
        return "#a78bfa";
    return "";
}

// Build the per-provider cost rows the Spend tab shows from a provider list
// that already carries details. Only numbers the backend already exposed.
function spendProviderRows(providers) {
    var rows = [];
    var list = providers || [];
    for (var i = 0; i < list.length; i++) {
        var p = list[i] || {};
        var d = p.details || {};
        var cost = 0;
        var currency = "USD";
        var note = "";
        var id = p.id || "";

        if (id === "claude") {
            cost = Number((d.organizationUsage && d.organizationUsage.totalCostUSD)
                || (d.org && d.org.totalCostUSD) || d.totalCostUSD
                || (d.stats && d.stats.totalCostUSD) || 0);
            note = "30d API";
        } else if (id === "openai") {
            cost = Number((d.organizationUsage && d.organizationUsage.totalCostUSD)
                || (d.org && d.org.totalCostUSD) || d.totalCostUSD
                || (d.stats && d.stats.totalCostUSD) || 0);
            note = "30d API";
        } else if (id === "openrouter") {
            cost = Number(d.usageUSD || d.usage || 0);
            note = "all-time";
        } else if (id === "mistral") {
            cost = Number((d.vibe && d.vibe.totalCost) || d.vibeTotalCost || d.totalCost || 0);
            note = "vibe CLI";
        } else if (id === "muse") {
            cost = Number((d.stats && d.stats.totalCostUSD) || d.totalCostUSD || 0);
            currency = (d.stats && d.stats.currency) || d.currency || "USD";
            note = "local est.";
        } else if (id === "cline") {
            cost = Number((d.stats && d.stats.totalCostUSD) || d.totalCostUSD || 0);
            note = "local";
        } else if (id === "cursor") {
            cost = Number(d.onDemandUsed || d.onDemandSpendUSD || d.onDemand || 0);
            note = "on-demand";
        }

        if (!(cost > 0))
            continue;
        rows.push({
            id: id,
            label: p.label || id,
            accent: p.accent || accent("spend"),
            icon: p.icon || "",
            cost: cost,
            currency: currency,
            note: note
        });
    }
    rows.sort(function (a, b) {
        return b.cost - a.cost;
    });
    return rows;
}

function spendTotal(rows, currency) {
    var sum = 0;
    var cur = currency || "USD";
    for (var i = 0; i < (rows || []).length; i++) {
        if ((rows[i].currency || "USD") === cur)
            sum += Number(rows[i].cost) || 0;
    }
    return sum;
}
