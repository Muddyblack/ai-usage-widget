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

function localSpendRows(localSpend) {
    var rows = [];
    var groups = [
        { key: "actual", id: "local-actual", label: "Actual provider cost" },
        { key: "estimated", id: "local-estimated", label: "Calculated estimate" }
    ];

    for (var i = 0; i < groups.length; i++) {
        var definition = groups[i];
        var group = localSpend && localSpend[definition.key];
        if (!group || (group.costStatus !== "exact" && group.costStatus !== "partial"))
            continue;
        if (typeof group.totalUSD !== "number" || !isFinite(group.totalUSD) || !(group.totalUSD > 0))
            continue;
        rows.push({
            id: definition.id,
            label: definition.label,
            cost: group.totalUSD,
            currency: "USD",
            note: "local CLI logs",
            local: true,
            provenance: definition.key,
            costStatus: group.costStatus
        });
    }

    if (rows.length === 0 && localSpend &&
            (localSpend.costStatus === "exact" || localSpend.costStatus === "partial") &&
            typeof localSpend.totalUSD === "number" && isFinite(localSpend.totalUSD) &&
            localSpend.totalUSD > 0) {
        rows.push({
            id: "local",
            label: "Local sessions",
            cost: localSpend.totalUSD,
            currency: "USD",
            note: "local CLI logs",
            local: true,
            legacy: true,
            costStatus: localSpend.costStatus
        });
    }
    return rows;
}

function sessionCostInfo(entry) {
    var status = entry && entry.costStatus;
    var cost = entry && entry.costUSD;
    if ((status !== "exact" && status !== "partial") ||
            typeof cost !== "number" || !isFinite(cost) || cost < 0)
        return { available: false, provenance: "", status: "unavailable", cost: 0 };

    var provenance = entry.costProvenance;
    if (provenance === undefined || provenance === null || provenance === "")
        provenance = "legacy";
    if (provenance !== "actual" && provenance !== "estimated" &&
            provenance !== "mixed" && provenance !== "legacy")
        return { available: false, provenance: "", status: "unavailable", cost: 0 };
    return { available: true, provenance: provenance, status: status, cost: cost };
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
            cost = (d.organizationUsage && d.organizationUsage.totalCostUSD)
                || (d.org && d.org.totalCostUSD) || d.totalCostUSD
                || (d.stats && d.stats.totalCostUSD) || 0;
            note = "30d API";
        } else if (id === "openai") {
            cost = (d.organizationUsage && d.organizationUsage.totalCostUSD)
                || (d.org && d.org.totalCostUSD) || d.totalCostUSD
                || (d.stats && d.stats.totalCostUSD) || 0;
            note = "30d API";
        } else if (id === "openrouter") {
            cost = d.usageUSD || d.usage || 0;
            note = "all-time";
        } else if (id === "mistral") {
            cost = (d.vibe && d.vibe.totalCost) || d.vibeTotalCost || d.totalCost || 0;
            note = "vibe CLI";
        } else if (id === "muse") {
            cost = (d.stats && d.stats.totalCostUSD) || d.totalCostUSD || 0;
            currency = (d.stats && d.stats.currency) || d.currency || "USD";
            note = "local est.";
        } else if (id === "cline") {
            cost = (d.stats && d.stats.totalCostUSD) || d.totalCostUSD || 0;
            note = "local";
        } else if (id === "cursor") {
            cost = d.onDemandUsed || d.onDemandSpendUSD || d.onDemand || 0;
            note = "on-demand";
        }

        if (typeof cost !== "number" || !isFinite(cost) || !(cost > 0))
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
        if (rows[i].local !== true && (rows[i].currency || "USD") === cur &&
                typeof rows[i].cost === "number" && isFinite(rows[i].cost))
            sum += rows[i].cost;
    }
    return sum;
}
