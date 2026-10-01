.pragma library

// Every provider the settings page can switch on, in display order, with the
// settings key its API key is stored under. Shared by the two frontends that
// draw the settings page themselves — the Quickshell panel (AiUsageShell.qml)
// and the Windows tray app (windows/qml/Main.qml) — so adding a provider here
// is enough to make it configurable in both.

var providers = [
    {
        id: "claude",
        label: "Claude",
        accent: "#cc785c",
        keySetting: "claudeAdmin",
        keyPlaceholder: "sk-ant-api03-…"
    },
    {
        id: "antigravity",
        label: "Antigravity",
        accent: "#4285f4"
    },
    {
        id: "openai",
        label: "OpenAI",
        accent: "#10a37f",
        keySetting: "openai",
        keyPlaceholder: "sk-proj-…"
    },
    {
        id: "kiro",
        label: "Kiro",
        accent: "#8b5cf6"
    },
    {
        id: "mistral",
        label: "Mistral",
        accent: "#ff7000",
        keySetting: "mistral",
        keyPlaceholder: "or $MISTRAL_API_KEY"
    },
    {
        id: "openrouter",
        label: "OpenRouter",
        accent: "#9333ea",
        keySetting: "openrouter",
        keyPlaceholder: "or $OPENROUTER_API_KEY"
    },
    {
        id: "ollama",
        label: "Ollama Cloud",
        accent: "#f0f0f0",
        keySetting: "ollama",
        keyPlaceholder: "optional — OpenCode login or $OLLAMA_API_KEY"
    },
    {
        id: "selfhosted",
        label: "Local Models",
        accent: "#38bdf8",
        keySetting: "selfhosted",
        keyPlaceholder: "optional server token"
    },
    {
        id: "grok",
        label: "Grok",
        accent: "#e6e6e6",
        keySetting: "grok",
        keyPlaceholder: "optional; uses Grok CLI login"
    },
    {
        id: "zai",
        label: "Z.AI",
        accent: "#126ef4",
        keySetting: "zai",
        keyPlaceholder: "or $ZAI_TOKEN"
    },
    {
        id: "copilot",
        label: "Copilot",
        accent: "#8b5cf6",
        keySetting: "github",
        keyPlaceholder: "optional — gh/Copilot login is used"
    },
    {
        id: "deepseek",
        label: "DeepSeek",
        accent: "#4f8cff",
        keySetting: "deepseek",
        keyPlaceholder: "or $DEEPSEEK_API_KEY"
    },
    {
        id: "kimi",
        label: "Kimi",
        accent: "#1e3a8a",
        keySetting: "moonshot",
        keyPlaceholder: "optional — the kimi CLI login is used"
    },
    {
        id: "muse",
        label: "Muse",
        accent: "#0064e0",
        keySetting: "muse",
        keyPlaceholder: "optional — the CLI login is used"
    },
    {
        id: "cursor",
        label: "Cursor",
        accent: "#e6e6e6"
    },
    {
        id: "cline",
        label: "Cline",
        accent: "#e6e6e6"
    },
    {
        id: "mimo",
        label: "MiMo Code",
        accent: "#E8E8E8"
    },
    {
        id: "junie",
        label: "Junie",
        accent: "#48e054"
    },
    {
        id: "opencode",
        label: "OpenCode",
        accent: "#B7B1B1"
    }
];

// Mirrors OPT_IN_PROVIDERS in aiusage/config.py: what a missing toggle means
// until providerDefaultsApplied is set (or when applying the defaults failed).
var OPT_IN = ["zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "opencode", "mimo", "junie", "ollama", "selfhosted"];

function enabled(settings, id) {
    var toggles = (settings && settings.providers) || {};
    if (!settings || settings.providerDefaultsApplied !== true) {
        if (OPT_IN.indexOf(id) !== -1)
            return toggles[id] === true;
        return toggles[id] !== false;
    }
    return toggles[id] === true;
}

// Mirrors AUTO_DETECT_PROVIDERS in aiusage/detect.py: the providers detection
// can speak for. Every other provider is only ever switched by hand.
var AUTO_DETECT = ["claude", "antigravity", "openai", "kiro", "mistral", "grok", "muse", "cursor", "cline", "opencode", "mimo", "junie"];

// Re-run of detection from the settings page. Detection reports what is
// installed right now, so it syncs both ways: a detected provider that is off
// is switched on, and an auto-detectable provider whose program is gone is
// switched off (issue #60), unless an API key is configured for it, because
// that key keeps it usable without the local tool. Returns the new settings
// and the ids that were switched on and off.
function applyDetected(settings, detected) {
    var next = JSON.parse(JSON.stringify(settings || {}));
    next.providers = next.providers || {};
    var keys = next.keys || {};
    var found = detected || [];
    var added = [];
    var removed = [];
    found.forEach(function (id) {
        if (!enabled(next, id)) {
            next.providers[id] = true;
            added.push(id);
        }
    });
    providers.forEach(function (provider) {
        var id = provider.id;
        if (AUTO_DETECT.indexOf(id) === -1 || found.indexOf(id) !== -1 || !enabled(next, id))
            return;
        if (provider.keySetting && String(keys[provider.keySetting] || "") !== "")
            return;
        next.providers[id] = false;
        removed.push(id);
    });
    return {
        settings: next,
        added: added,
        removed: removed
    };
}

// Display names for a list of provider ids, for the detection status line.
function labels(ids) {
    return (ids || []).map(function (id) {
        for (var i = 0; i < providers.length; i++)
            if (providers[i].id === id)
                return providers[i].label || id;
        return id;
    }).join(", ");
}
