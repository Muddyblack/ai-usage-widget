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
    }
];

// Mirrors OPT_IN_PROVIDERS in aiusage/config.py: these stay off until switched
// on, the rest stay on until switched off.
var OPT_IN = ["zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "ollama"];

function enabled(settings, id) {
    var toggles = (settings && settings.providers) || {};
    if (OPT_IN.indexOf(id) !== -1)
        return toggles[id] === true;
    return toggles[id] !== false;
}
