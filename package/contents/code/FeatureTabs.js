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

function localSourceKey(source) {
    if (typeof source !== "string")
        return "";
    return source.trim().toLowerCase().replace(/_/g, "-");
}

function localSourceLabel(source) {
    var key = localSourceKey(source);
    var labels = {
        opencode: "OpenCode",
        claude: "Claude Code",
        "claude-code": "Claude Code",
        openai: "Codex",
        codex: "Codex",
        cline: "Cline",
        grok: "Grok CLI",
        "grok-cli": "Grok CLI",
        muse: "Muse",
        antigravity: "Antigravity"
    };
    if (labels[key] !== undefined)
        return labels[key];
    var fallback = key.replace(/-+/g, " ").replace(/\s+/g, " ").trim();
    if (!fallback)
        return "Local source";
    return fallback.replace(/(^|\s)\S/g, function (letter) { return letter.toUpperCase(); });
}

function upstreamProviderLabel(provider) {
    var labels = {
        anthropic: "Anthropic",
        openai: "OpenAI",
        openrouter: "OpenRouter",
        "ollama-cloud": "Ollama Cloud",
        ollama: "Ollama",
        "github-copilot": "GitHub Copilot",
        google: "Google",
        zenmux: "ZenMux",
        opencode: "OpenCode Zen",
    };
    return labels[localSourceKey(provider)] || localSourceLabel(provider);
}

function localSpendNote(provenance, costStatus, source) {
    var prefix = source === "opencode" ? "via OpenCode" : "local CLI logs";
    var notes = {
        "legacy:exact": prefix + " · exact",
        "legacy:partial": prefix + " · partial",
        "actual:exact": prefix + " · actual · exact",
        "actual:partial": prefix + " · actual · partial",
        "estimated:exact": prefix + " · estimated · exact",
        "estimated:partial": prefix + " · estimated · partial",
        "mixed:exact": prefix + " · mixed · exact",
        "mixed:partial": prefix + " · mixed · partial"
    };
    return notes[provenance + ":" + costStatus] || prefix;
}

// Plan-covered work: the figure is what the API would have charged, not money
// owed, so its note has to say so rather than read like a bill.
function planSpendNote(costStatus, source) {
    var prefix = source === "opencode" ? "via OpenCode" : "covered by plan";
    return prefix + " · would cost on API" + (costStatus === "partial" ? " · partial" : "");
}

function localProviderCost(group, source) {
    if (!group || (group.costStatus !== "exact" && group.costStatus !== "partial"))
        return null;
    var providers = group.providers || {};
    var entry = null;
    var keys = Object.keys(providers);
    for (var i = 0; i < keys.length; i++) {
        if (localSourceKey(keys[i]) === source) {
            entry = providers[keys[i]];
            break;
        }
    }
    if (!entry || (entry.costStatus !== "exact" && entry.costStatus !== "partial") ||
            typeof entry.costUSD !== "number" || !isFinite(entry.costUSD) || !(entry.costUSD > 0))
        return null;
    return { cost: entry.costUSD, status: entry.costStatus, source: localSourceKey(entry.source) };
}

function localProviderKey(identity) {
    var key = localSourceKey(identity);
    var separator = key.lastIndexOf("::");
    return separator > 0 ? key.slice(0, separator) : key;
}

function localSpendRows(localSpend) {
    var rows = [];
    var sources = {};
    var groups = ["actual", "estimated"];
    for (var i = 0; i < groups.length; i++) {
        var group = localSpend && localSpend[groups[i]];
        var providers = group && group.providers;
        if (!providers)
            continue;
        var sourceIds = Object.keys(providers);
        for (var j = 0; j < sourceIds.length; j++) {
            var sourceKey = localSourceKey(sourceIds[j]);
            if (sourceKey)
                sources[sourceKey] = true;
        }
    }

    var sourceIds = Object.keys(sources);
    for (var k = 0; k < sourceIds.length; k++) {
        var sourceKey = sourceIds[k];
        var actual = localProviderCost(localSpend && localSpend.actual, sourceKey);
        var estimated = localProviderCost(localSpend && localSpend.estimated, sourceKey);
        if (!actual && !estimated)
            continue;

        var actualUSD = actual ? actual.cost : 0;
        var estimatedUSD = estimated ? estimated.cost : 0;
        var source = actual && actual.source || estimated && estimated.source || "";
        var providerKey = localProviderKey(sourceKey);
        var hasActual = actualUSD > 0;
        var hasEstimated = estimatedUSD > 0;
        var provenance = hasActual && hasEstimated ? "mixed" : hasActual ? "actual" : "estimated";
        var costStatus = (actual && actual.status === "partial") ||
                (estimated && estimated.status === "partial") ? "partial" : "exact";
        rows.push({
            id: "local-" + (source ? source + "-" : "") + providerKey,
            label: source === "opencode" ? upstreamProviderLabel(providerKey) : localSourceLabel(providerKey),
            cost: actualUSD + estimatedUSD,
            currency: "USD",
            note: localSpendNote(provenance, costStatus, source),
            local: true,
            source: source || providerKey,
            provenance: provenance,
            costStatus: costStatus,
            costBreakdown: { actualUSD: actualUSD, estimatedUSD: estimatedUSD }
        });
    }

    // Subscription usage, kept as its own rows so it is never summed with, or
    // mistaken for, the metered totals above.
    var planSources = {};
    var planGroups = ["subscription", "subscriptionActual"];
    for (var g = 0; g < planGroups.length; g++) {
        var planGroup = localSpend && localSpend[planGroups[g]];
        var planProviders = planGroup && planGroup.providers;
        if (!planProviders)
            continue;
        var planKeys = Object.keys(planProviders);
        for (var n = 0; n < planKeys.length; n++) {
            var planKey = localSourceKey(planKeys[n]);
            if (planKey)
                planSources[planKey] = true;
        }
    }
    var planIds = Object.keys(planSources);
    for (var q = 0; q < planIds.length; q++) {
        var planSourceKey = planIds[q];
        var planEstimated = localProviderCost(localSpend && localSpend.subscription, planSourceKey);
        var planActual = localProviderCost(localSpend && localSpend.subscriptionActual, planSourceKey);
        var planCost = (planEstimated ? planEstimated.cost : 0) + (planActual ? planActual.cost : 0);
        if (!(planCost > 0))
            continue;
        var planSource = (planEstimated && planEstimated.source) || (planActual && planActual.source) || "";
        var planProviderKey = localProviderKey(planSourceKey);
        var planStatus = (planEstimated && planEstimated.status === "partial") ||
                (planActual && planActual.status === "partial") ? "partial" : "exact";
        rows.push({
            id: "plan-" + (planSource ? planSource + "-" : "") + planProviderKey,
            label: planSource === "opencode" ? upstreamProviderLabel(planProviderKey) : localSourceLabel(planProviderKey),
            cost: planCost,
            currency: "USD",
            note: planSpendNote(planStatus, planSource),
            local: true,
            billing: "subscription",
            source: planSource || planProviderKey,
            provenance: "estimated",
            costStatus: planStatus
        });
    }

    if (rows.length === 0 && localSpend && !localSpend.actual && !localSpend.estimated &&
            (localSpend.costStatus === "exact" || localSpend.costStatus === "partial") &&
            typeof localSpend.totalUSD === "number" && isFinite(localSpend.totalUSD) &&
            localSpend.totalUSD > 0) {
        rows.push({
            id: "local",
            label: "Local sessions",
            cost: localSpend.totalUSD,
            currency: "USD",
            note: localSpendNote("legacy", localSpend.costStatus, ""),
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
        return { available: false, provenance: "", status: "unavailable", cost: 0, billing: "api" };

    var provenance = entry.costProvenance;
    if (provenance === undefined || provenance === null || provenance === "")
        provenance = "legacy";
    if (provenance !== "actual" && provenance !== "estimated" &&
            provenance !== "mixed" && provenance !== "legacy")
        return { available: false, provenance: "", status: "unavailable", cost: 0 };
    var billing = entry.costBilling === "subscription" ? "subscription" : "api";
    return { available: true, provenance: provenance, status: status, cost: cost, billing: billing };
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

// ── Model rate table ───────────────────────────────────────────────────────
// Shared by every QML frontend's Spend view. The widgets differ (Plasma
// components vs. plain QtQuick) and so does the process plumbing (Plasma5Support
// DataSource vs. Quickshell Process), but the formatting, paging arithmetic and
// payload parsing are identical — so they live here rather than in each copy.

function rateText(value) {
    if (typeof value !== "number" || !isFinite(value))
        return "\u2014";
    if (value === 0)
        return "free";
    return "$" + (value < 1 ? value.toFixed(3) : value.toFixed(2));
}

// The catalog is cached for a week, so "is this current?" is the first question
// the table has to answer. nowMs is injectable so tests need no clock stubbing.
function rateAge(seconds, i18nFn, nowMs) {
    function t(text, arg) {
        if (!i18nFn)
            return text.replace("%1", arg);
        return arg === undefined ? i18nFn(text) : i18nFn(text, arg);
    }
    if (typeof seconds !== "number" || !isFinite(seconds) || !(seconds > 0))
        return "";
    var now = (typeof nowMs === "number" && isFinite(nowMs)) ? nowMs : new Date().getTime();
    var s = Math.max(0, (now / 1000) - seconds);
    if (s < 3600)
        return t("updated just now");
    if (s < 86400)
        return t("updated %1h ago", Math.floor(s / 3600));
    if (s < 604800)
        return t("updated %1d ago", Math.floor(s / 86400));
    return t("updated %1w ago", Math.floor(s / 604800));
}

function ratePageCount(total, limit) {
    var size = Math.max(1, Number(limit) || 1);
    return Math.max(1, Math.ceil((Number(total) || 0) / size));
}

function ratePageNumber(offset, limit, total) {
    var size = Math.max(1, Number(limit) || 1);
    var at = Math.max(0, Number(offset) || 0);
    return Math.min(ratePageCount(total, size), Math.floor(at / size) + 1);
}

// Parses --pricing-table stdout. Returns null when the output is unusable, so
// each frontend can show its own "could not read" string.
function parseRateTable(text) {
    var out = (text || "").trim();
    if (out === "")
        return null;
    var payload;
    try {
        payload = JSON.parse(out);
    } catch (e) {
        return null;
    }
    if (!payload || typeof payload !== "object")
        return null;
    return {
        rows: Array.isArray(payload.rows) ? payload.rows : [],
        total: Number(payload.total) || 0,
        unit: payload.unit || "",
        fetchedAt: Number(payload.fetchedAt) || 0,
        error: payload.error || ""
    };
}
