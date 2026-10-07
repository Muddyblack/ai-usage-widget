.pragma library

// One-time carry-over of the old Plasma widget's KConfig settings (main.xml)
// into the settings JSON every host shares. Runs on each start, but only acts
// while the JSON has no `kdeMigrated` mark: what the JSON already holds wins,
// and the KConfig values fill in only what it lacks.

var PROVIDERS = ["claude", "antigravity", "openai", "kiro", "mistral", "openrouter", "ollama", "selfhosted", "grok", "zai", "copilot", "deepseek", "kimi", "cursor", "cline", "muse", "junie", "mimo", "opencode"];

// KConfig entry → keys{} name the backend reads (aiusage/config.py).
var KEYS = {
    claudeAdminApiKey: "claudeAdmin",
    openaiApiKey: "openai",
    mistralApiKey: "mistral",
    openrouterApiKey: "openrouter",
    ollamaApiKey: "ollama",
    selfhostedKey: "selfhosted",
    grokApiKey: "grok",
    zaiToken: "zai",
    githubToken: "github",
    museApiKey: "muse",
    deepseekApiKey: "deepseek",
    moonshotApiKey: "moonshot"
};

// KConfig entry → top-level settings field.
var FIELDS = {
    selfhostedEndpoint: "selfhostedEndpoint",
    selfhostedEngine: "selfhostedEngine",
    copilotQuota: "copilotQuota",
    museQuotaEnabled: "museQuota",
    overviewEnabled: "overviewEnabled",
    spendEnabled: "spendEnabled",
    sessionsEnabled: "sessionsEnabled",
    showUsageChart: "showChart",
    pollIntervalSec: "pollSec",
    pythonPath: "pythonPath",
    lastTab: "lastTab",
    antigravityChartFilter: "antigravityChartFilter",
    providerDefaultsApplied: "providerDefaultsApplied",
    panelRotationIntervalSec: "panelRotationSec",
    useThemeAccent: "useThemeAccent",
    popupBgOpacity: "popupBgOpacity"
};

function present(value) {
    return value !== undefined && value !== null && value !== "";
}

// `text` is the settings JSON as read; `kconfig` the plasmoid's configuration
// object (or a plain object in tests). Returns the JSON to use — the same
// string when there was nothing to do.
function migrate(text, kconfig) {
    var settings;
    try {
        settings = JSON.parse((text || "").trim() || "{}") || {};
    } catch (e) {
        settings = {};
    }
    if (settings.kdeMigrated === true || !kconfig)
        return text;
    var out = Object.assign({}, settings);
    out.providers = Object.assign({}, settings.providers || {});
    out.keys = Object.assign({}, settings.keys || {});
    for (var i = 0; i < PROVIDERS.length; i++) {
        var id = PROVIDERS[i];
        var enabled = kconfig[id + "Enabled"];
        if (out.providers[id] === undefined && typeof enabled === "boolean")
            out.providers[id] = enabled;
    }
    for (var entry in KEYS) {
        if (present(kconfig[entry]) && !present(out.keys[KEYS[entry]]))
            out.keys[KEYS[entry]] = String(kconfig[entry]);
    }
    for (var field in FIELDS) {
        if (present(kconfig[field]) && out[FIELDS[field]] === undefined)
            out[FIELDS[field]] = kconfig[field];
    }
    // The old widget kept its pins as one comma-separated string.
    if (present(kconfig.pinnedTab) && out.pinnedTabs === undefined)
        out.pinnedTabs = String(kconfig.pinnedTab).split(",").filter(function (p) {
            return p !== "";
        });
    out.kdeMigrated = true;
    return JSON.stringify(out);
}
