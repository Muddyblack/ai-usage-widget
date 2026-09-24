import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "../code/FeatureTabs.js" as FeatureTabs
import "../code/Format.js" as Format
import "../code/PanelRotation.js" as PanelRotation
import "../code/Shell.js" as Shell
import "../code/UsageHistory.js" as UsageHistory

PlasmoidItem {
    // GPT-4o family
    // o1 / o3 reasoning family
    // GPT-4 Turbo / legacy
    // GPT-3.5
    // Codex / embeddings (no output tokens)

    id: root

    // ── Script directory ──────────────────────────────────────────────────────
    readonly property string scriptDir: Qt.resolvedUrl("../tools/sh/").toString().replace("file://", "")
    // ── Settings: which tabs are enabled (persisted via Plasmoid.configuration) ─
    // Feature views (Overview / Spend / Sessions) sit ahead of provider tabs.
    property var enabledTabs: {
        var t = FeatureTabs.enabledFeatureTabsPlasmoid(Plasmoid.configuration);
        for (var i = 0; i < root.providers.length; i++) {
            var p = root.providers[i];
            if (Plasmoid.configuration[p.id + "Enabled"])
                t.push(p.id);
        }
        return t;
    }
    property int activeTab: 0
    // The last real provider tab selected (never a feature tab id) — what
    // the compact panel falls back to while a feature tab is active, in
    // preference to just the first enabled provider.
    property string lastProviderId: ""
    // Primary tab for single-tab fallbacks. The compact panel can show every
    // pinned service; without pins it mirrors the in-popup active tab — but
    // never a feature view, which has no panel meter of its own.
    readonly property string panelTab: {
        if (root.panelRotationEnabled)
            return root.panelRotationProviderId !== "" ? root.panelRotationProviderId : root.pinnedTabs[0];
        if (root.pinnedTabs.length > 0)
            return root.pinnedTabs[0];

        var tab = root.enabledTabs[root.activeTab] || "";
        if (!FeatureTabs.isFeatureTab(tab))
            return tab;
        if (root.lastProviderId !== "" && root.enabledTabs.indexOf(root.lastProviderId) !== -1)
            return root.lastProviderId;
        for (var i = 0; i < root.enabledTabs.length; i++) {
            if (!FeatureTabs.isFeatureTab(root.enabledTabs[i]))
                return root.enabledTabs[i];
        }
        return "";
    }
    property real chartTimeOffset: 0
    // ── Service status (status pages) ────────────────────────────────────────
    // Provider id → details.status from the backend:
    // { indicator, description, components, incidents, latestUpdate, url }
    property var providerStatus: ({})
    property var localSpend: ({})
    // ── Claude data ───────────────────────────────────────────────────────────
    property bool sessionAvailable: false
    property real sessionPct: 0
    property real sessionTokensUsed: 0
    property real sessionTokenLimit: 0
    property string sessionResetTime: ""
    property var sessionResetDate: null
    property string sessionCountdown: ""
    property bool weeklyAvailable: false
    property real weeklyPct: 0
    property real weeklyTokensUsed: 0
    property real weeklyTokenLimit: 0
    property string weeklyResetTime: ""
    property var weeklyResetDate: null
    property string weeklyCountdown: ""
    property real claudeExtraTokens: 0
    property string claudeSubscriptionType: ""
    property string claudeRateLimitTier: ""
    property string claudeOrganizationUuid: ""
    property string claudeEffortLevel: "" // "low" | "medium" | "high" from settings.json
    property bool claudeAutoDream: false // extended thinking toggle from settings.json
    property bool claudeExtraUsageEnabled: false
    property real claudeExtraUsageLimit: 0
    property real claudeExtraUsageUsed: 0
    property real claudeExtraUsagePct: 0
    property string claudeExtraUsageCurrency: "USD"
    // Credential *presence* only — the backend never hands tokens to the UI.
    property bool claudeHasOAuth: false
    property bool claudeHasAdminKey: false
    property var claudeModels: ({})
    property real claudeTotalCostUSD: 0
    property real claudeTotalInputTokens: 0
    property real claudeTotalOutputTokens: 0

    // Claude Code local activity stats (mirrors ~/.claude/stats-cache.json).
    property bool claudeStatsAvailable: false
    property int claudeStatsVersion: 0
    property real claudeStatsTotalMessages: 0
    property real claudeStatsTotalSessions: 0
    property real claudeStatsTotalTokens: 0
    property string claudeStatsFavoriteModel: ""
    property string claudeStatsFirstDate: ""
    property string claudeStatsComputedDate: ""
    property real claudeStatsActiveDays: 0
    property real claudeStatsSpanDays: 0
    property real claudeStatsCurrentStreak: 0
    property real claudeStatsLongestStreak: 0
    property real claudeStatsLongestSessionMs: 0
    property real claudeStatsLongestSessionMessages: 0
    // Present in stats-cache.json since the CLI started recording per-model
    // spend and tool activity.
    property real claudeStatsTotalCostUSD: 0
    property real claudeStatsTotalToolCalls: 0
    property real claudeStatsTotalWebSearches: 0
    property real claudeStatsPeakHour: -1
    property var claudeStatsModels: ({})
    property var claudeStatsDailyTokens: []
    // ── Codex (OpenAI CLI) lifetime stats, from get-codex-stats ──────────────
    property bool codexStatsAvailable: false
    property real codexStatsTotalSessions: 0
    property real codexStatsTotalMessages: 0
    property real codexStatsTotalTokens: 0
    property real codexStatsTotalToolCalls: 0
    property string codexStatsFirstDate: ""
    property string codexStatsComputedDate: ""
    property real codexStatsActiveDays: 0
    property real codexStatsSpanDays: 0
    property real codexStatsCurrentStreak: 0
    property real codexStatsLongestStreak: 0
    property real codexStatsLongestSessionMs: 0
    property real codexStatsLongestSessionMessages: 0
    property real codexStatsPeakHour: -1
    property string codexStatsFavoriteModel: ""
    property var codexStatsModels: ({})
    property var codexStatsDailyTokens: []
    property real codexStatsTotalCostUSD: 0
    // Live model / reasoning effort, from the newest rollout's turn_context
    // (falls back to ~/.codex/config.toml).
    property string codexModel: ""
    property string codexEffortLevel: ""
    // ── Antigravity / Gemini data ─────────────────────────────────────────────
    property real antigravityPct: 0
    property real antigravityGooglePct: 0
    property real antigravityExternalPct: 0
    property string antigravityResetTime: ""
    property var antigravityResetDate: null
    property string antigravityCountdown: ""
    property string antigravityEmail: ""
    property string antigravityPlanType: ""
    property real antigravityPromptCreditsMonthly: 0
    property real antigravityPromptCreditsAvailable: 0
    property var antigravityModels: ({})
    property var antigravityGroups: []
    // ── OpenAI data ───────────────────────────────────────────────────────────
    property bool openaiHasApiKey: false
    property string openaiEmail: ""
    property string openaiPlanType: ""
    property string openaiOrgId: ""
    property string openaiAccountId: ""
    property string openaiAuthMode: "" // "chatgpt" | "api_key" | ""
    property bool openaiCodexLoggedIn: false
    property var openaiModels: ({})
    property real openaiTotalCostUSD: 0
    property real openaiTotalInputTokens: 0
    property real openaiTotalOutputTokens: 0
    // ── Kiro data ─────────────────────────────────────────────────────────────
    property bool kiroUsageAvailable: false
    property string kiroPlanType: ""
    property string kiroDisplayName: i18n("Credit")
    property string kiroDisplayNamePlural: i18n("Credits")
    property real kiroCurrentUsage: 0
    property real kiroUsageLimit: 0
    property real kiroPct: 0
    property real kiroRemaining: 0
    property real kiroCurrentOverages: 0
    property real kiroOverageCap: 0
    property real kiroOverageCharges: 0
    property real kiroOverageRate: 0
    property string kiroCurrencyCode: "USD"
    property string kiroCurrencySymbol: "$"
    property string kiroResetTime: ""
    property var kiroResetDate: null
    property string kiroCountdown: ""
    property string kiroSource: ""
    // ── Codex / ChatGPT-plan usage ────────────────────────────────────────────
    // Windows are classified by their actual duration, never by response order.
    property bool codexUsageAvailable: false
    property bool codexSessionAvailable: false
    property real codexSessionPct: 0
    property var codexSessionResetDate: null
    property string codexSessionCountdown: ""
    property bool codexWeeklyAvailable: false
    property real codexWeeklyPct: 0
    property var codexWeeklyResetDate: null
    property string codexWeeklyCountdown: ""
    // Deprecated compatibility aliases. Keep these until five-hour windows return.
    readonly property real codexPrimaryPct: root.codexSessionPct
    readonly property var codexPrimaryResetDate: root.codexSessionResetDate
    readonly property string codexPrimaryCountdown: root.codexSessionCountdown
    readonly property real codexSecondaryPct: root.codexWeeklyPct
    readonly property var codexSecondaryResetDate: root.codexWeeklyResetDate
    readonly property string codexSecondaryCountdown: root.codexWeeklyCountdown
    property bool codexLimitReached: false
    // Per-model additional rate limits (additional_rate_limits[] from the endpoint)
    // Each entry: { name, primary_pct, primary_reset, primary_countdown, secondary_pct, secondary_reset, secondary_countdown }
    property var codexAdditionalLimits: []
    // ── Mistral data ──────────────────────────────────────────────────────────
    property bool mistralHasKey: false
    property bool mistralKeyValid: false
    property var mistralAvailableModels: []
    property string mistralError: ""
    property int mistralVibeSessionCount: 0
    property real mistralVibeTotalCost: 0
    property int mistralVibeTotalTokens: 0
    property int mistralVibePromptTokens: 0
    property int mistralVibeCompletionTokens: 0
    property int mistralVibeTotalSteps: 0
    property int mistralVibeToolOk: 0
    property int mistralVibeToolFail: 0
    property string mistralVibeActiveModel: ""
    property var mistralVibeRecent: []
    // ── OpenRouter data ───────────────────────────────────────────────────────
    property bool openrouterHasKey: false
    property bool openrouterKeyValid: false
    property string openrouterLabel: ""
    property real openrouterUsageUSD: 0
    property var openrouterLimitUSD: null // null = unlimited
    property var openrouterLimitRemainingUSD: null
    property bool openrouterIsFreeTier: false
    property var openrouterRateLimit: ({})
    property string openrouterError: ""
    property var ollamaWindows: []
    property var selfhostedProvider: ({})
    property var ollamaModels: ({})
    property string ollamaActivityCost: ""
    property string ollamaError: ""
    property real ollamaPct: 0
    readonly property var ollamaWeeklyWindow: {
        for (var i = 0; i < root.ollamaWindows.length; i++) {
            if (root.ollamaWindows[i].key === "ollama_weekly")
                return root.ollamaWindows[i];
        }
        return null;
    }
    // ── Grok CLI / xAI data ──────────────────────────────────────────────────
    property bool grokHasKey: false
    property bool grokLoggedIn: false
    property real grokPct: 0
    property real grokUsed: 0
    property real grokMonthlyLimit: 0
    property string grokEmail: ""
    property string grokTeamName: ""
    property string grokTierId: ""
    property string grokBillingPeriodEnd: ""
    property int grokSessionCount: 0
    property real grokTotalTokens: 0
    property int grokTotalToolCalls: 0
    property string grokError: ""
    property bool grokHasBilling: false
    property string grokQuotaKind: ""
    property string grokQuotaWindow: ""
    property bool grokQuotaExhausted: false
    // ── Z.AI data ─────────────────────────────────────────────────────────────
    property bool zaiHasKey: false
    property bool zaiKeyValid: false
    property string zaiLevel: ""
    property real zaiTokenPct: 0
    property var zaiTokenUsed: null
    property var zaiTokenLimit: null
    property var zaiTokenResetDate: null
    property string zaiTokenCountdown: ""
    property real zaiToolsPct: 0
    property var zaiToolsRemaining: null
    property var zaiToolsResetDate: null
    property string zaiToolsCountdown: ""
    property var zaiModels: []
    property string zaiError: ""
    // ── GitHub Copilot data ───────────────────────────────────────────────────
    property bool copilotHasKey: false
    property bool copilotKeyValid: false
    property string copilotUsername: ""
    property real copilotUsed: 0
    property real copilotQuota: Plasmoid.configuration.copilotQuota || 300
    property real copilotPct: 0
    property var copilotResetDate: null
    property string copilotCountdown: ""
    property string copilotError: ""
    property bool copilotUnlimited: false
    property string copilotPlan: ""
    // Copilot CLI local activity, from ~/.copilot/session-store.db. The CLI
    // records no tokens or models, so this is the activity half only.
    property bool copilotStatsAvailable: false
    property real copilotStatsTotalSessions: 0
    property real copilotStatsTotalMessages: 0
    property real copilotStatsTotalToolCalls: 0
    property real copilotStatsTotalFiles: 0
    property real copilotStatsTotalRepositories: 0
    property var copilotStatsTopRepositories: []
    property string copilotStatsFirstDate: ""
    property real copilotStatsActiveDays: 0
    property real copilotStatsSpanDays: 0
    property real copilotStatsCurrentStreak: 0
    property real copilotStatsLongestStreak: 0
    property real copilotStatsLongestSessionMs: 0
    property real copilotStatsLongestSessionMessages: 0
    property real copilotStatsPeakHour: -1
    property var copilotStatsDailyMessages: []
    // ── DeepSeek data ────────────────────────────────────────────────────────
    property bool deepseekHasKey: false
    property bool deepseekKeyValid: false
    property bool deepseekIsAvailable: false
    property var deepseekBalances: []
    property string deepseekPrimaryCurrency: ""
    property real deepseekPrimaryTotal: 0
    property real deepseekPrimaryGranted: 0
    property real deepseekPrimaryToppedUp: 0
    property string deepseekError: ""
    // ── Kimi / Moonshot data ─────────────────────────────────────────────────
    property bool kimiHasKey: false
    property bool kimiKeyValid: false
    property real kimiAvailableBalance: 0
    property real kimiVoucherBalance: 0
    property real kimiCashBalance: 0
    property string kimiError: ""
    // Kimi Code plan quota (the `kimi` CLI login) — independent of the key above
    property bool kimiPlanAvailable: false
    property bool kimiPlanExhausted: false
    property string kimiPlanMessage: ""
    property string kimiPlanError: ""
    property var kimiPlanWindows: []
    property real kimiPlanPct: 0
    property var kimiBooster: null

    // ── Cursor data ──────────────────────────────────────────────────────────
    property bool cursorLoggedIn: false
    property bool cursorAvailable: false
    property string cursorSource: ""
    property string cursorPlanName: ""
    property real cursorTotalPct: 0
    property real cursorAutoPct: 0
    property real cursorApiPct: 0
    property bool cursorHasSplit: false
    property real cursorIncludedSpend: 0
    property real cursorLimit: 0
    property real cursorOnDemandUsed: 0
    property real cursorOnDemandLimit: 0
    property var cursorResetDate: null
    property string cursorResetTime: ""
    property string cursorCountdown: ""
    property string cursorError: ""
    // Dashboard usage for the billing cycle, in the shared stats shape (stats.py)
    property var cursorStats: ({})

    // ── Cline data (local session logs, shared stats shape) ──────────────────
    property var clineStats: ({})
    // Today / last 7 days / last 30 days: [{key, label, sessions, tokens, cost}]
    property var clinePeriods: []
    property string clineError: ""
    readonly property real clineMonthTokens: clinePeriods.length > 2 ? (clinePeriods[2].tokens || 0) : 0
    // Bumped by updateCountdowns() so Repeater rows can re-read their own countdown
    property int countdownTick: 0
    // ── Muse data ───────────────────────────────────────────────────────────
    // Muse Code. No quota properties: Meta reports the plan windows only on a
    // billed model call, so the widget never asks (see providers/muse.py).
    property bool museHasLogin: false
    property string museEmail: ""
    property string museFullName: ""
    property string museModel: ""
    property real museTotalTokens: 0
    property real museInputTokens: 0
    property real museOutputTokens: 0
    property real museCostUSD: 0
    // The catalog states its own currency, so the estimate is not USD by
    // definition — keep what the backend reported rather than assuming.
    property string museCurrency: "USD"
    property real museModelCalls: 0
    property string museError: ""
    // Plan windows: only present when the user switched the billed call on.
    property bool museQuotaOn: Plasmoid.configuration.museQuotaEnabled === true
    property string museQuotaError: ""
    property bool museCurrentAvailable: false
    property real museCurrentPct: 0
    property var museCurrentResetDate: null
    property string museCurrentCountdown: ""
    property bool museWeeklyAvailable: false
    property real museWeeklyPct: 0
    property var museWeeklyResetDate: null
    property string museWeeklyCountdown: ""
    // Muse CLI local activity.
    property real museStatsTotalSessions: 0
    property real museStatsSubagentSessions: 0
    property real museStatsTotalMessages: 0
    property real museStatsTotalToolCalls: 0
    property real museStatsActiveDays: 0
    property real museStatsSpanDays: 0
    property real museStatsCurrentStreak: 0
    property real museStatsLongestStreak: 0
    property real museStatsLongestSessionMs: 0
    property real museStatsLongestSessionMessages: 0
    property real museStatsPeakHour: -1
    property string museStatsFirstDate: ""
    property var museStatsModels: ({})
    property var museStatsDailyTokens: []
    property var museStatsTopWorkspaces: []
    // ── Common ────────────────────────────────────────────────────────────────
    property string errorMsg: ""
    property bool stale: false
    property string lastUpdate: ""
    property int backoffMs: 0
    property bool showSettings: false
    // Which settings section is on screen. Session-only on purpose: the panel
    // always opens on Providers, the section people come here for.
    property string settingsTab: "providers"
    property bool showUsageChart: Plasmoid.configuration.showUsageChart
    // Unified usage history: array of {t, s, w, cp, cw}.
    // s=Claude session%, w=Claude weekly%, cp=Codex 5h%, cw=Codex weekly%.
    // `weeklyUsageHistory` exposes {t,v} for whichever window chartWindow selects.
    property var usageHistory: []
    property string chartWindow: Plasmoid.configuration.chartWindow || "weekly"
    readonly property int historyLimit: 10000
    // Granularity ("5h" | "24h" | "7d" | "30d") is remembered across tabs so switching
    // services keeps the same time range.
    property string chartGranularity: Plasmoid.configuration.chartGranularity || "7d"
    // Antigravity model filter: "both" (default), "combined", "gemini", or "rest"
    property string antigravityChartFilter: Plasmoid.configuration.antigravityChartFilter || "both"
    // Chart ranges per provider, straight from the backend: which history series
    // exist, what each one is called and how wide it is. Keyed by provider id.
    property var providerChartWindows: ({})

    function seriesForHistoryKey(key, fallbackKey) {
        var win = root.currentChartWindow();
        if (!win)
            return [];
        var out = [];
        var now_ms = new Date().getTime();
        var winSize = win.size;
        var maxT = now_ms - root.chartTimeOffset;
        var minT = maxT - winSize;
        for (var i = 0; i < root.usageHistory.length; i++) {
            var p = root.usageHistory[i];
            var v = p[key];
            if ((v === undefined || v === null) && fallbackKey)
                v = p[fallbackKey];
            if (v === undefined || v === null)
                continue;

            if (p.t >= minT && p.t <= maxT)
                out.push({
                    "t": p.t,
                    "v": v
                });
        }
        if (win.resets)
            out = UsageHistory.withResets(out, win.resetAt * 1000, win.periodMs, minT, maxT);
        return out;
    }

    // {t, v} view of the currently-selected chart window
    readonly property var weeklyUsageHistory: {
        var win = root.currentChartWindow();
        if (!win)
            return [];

        var key = win.key;
        var tab = root.enabledTabs[root.activeTab] || "";
        var fallbackKey = null;
        if (tab === "antigravity") {
            if (root.antigravityChartFilter === "gemini") {
                key = "agg";
                fallbackKey = "ag";
            } else if (root.antigravityChartFilter === "rest") {
                key = "age";
            } else {
                key = "ag";
            }
        }
        var out = root.seriesForHistoryKey(key, fallbackKey);

        // Raw money series store absolute amounts; auto-scale to their own max so the
        // spend curve fills the chart (the canvas expects a 0-100 value).
        if (win.raw && out.length > 0) {
            var maxV = 0;
            for (var j = 0; j < out.length; j++)
                if (out[j].v > maxV) {
                    maxV = out[j].v;
                }
            if (maxV > 0)
                for (var k = 0; k < out.length; k++)
                    out[k] = {
                        "t": out[k].t,
                        "v": (out[k].v / maxV) * 100,
                        "raw": out[k].v
                    };
        }
        return out;
    }
    // ── Tab snapshot export ─────────────────────────────────────────────────
    property string _exportFormat: ""
    property int _exportW: 0
    property int _exportH: 0
    property bool _exportHideHeader: false
    property string historyIOMsg: ""
    // ── Colors ────────────────────────────────────────────────────────────────
    readonly property color claudeOrange: "#cc785c"
    readonly property color googleBlue: "#4285f4"
    readonly property color googleGreen: "#34a853"
    readonly property color openaiGreen: "#10a37f"
    readonly property color kiroPurple: "#8b5cf6"
    readonly property color mistralOrange: "#ff7000"
    readonly property color openrouterPurple: "#9333ea"
    readonly property color grokWhite: "#e6e6e6"
    readonly property color zaiBlue: "#126ef4"
    readonly property color copilotPurple: "#8b5cf6"
    readonly property color deepseekBlue: "#4f8cff"
    readonly property color kimiBlue: "#1e3a8a"
    readonly property color cursorWhite: "#e6e6e6"
    readonly property color clineWhite: "#e6e6e6"
    readonly property color museBlue: "#0064e0"
    readonly property color sessionColor: "#e05252"
    readonly property color weeklyColor: "#f5a623"
    readonly property color warningColor: "#ffa64d"
    readonly property color dangerColor: "#ff4d4d"
    // ── Provider registry ─────────────────────────────────────────────────────
    // The single source of truth for every provider the widget knows about, in
    // display order. tabName/tabColor/tabIcon/enabledTabs and the settings
    // panel's service toggles all derive from this list, so adding a provider
    // is one row here instead of edits to four parallel if-chains that could
    // drift apart. Enabled state lives in Plasmoid.configuration under a fixed
    // "<id>Enabled" key. Icon filenames are listed rather than derived: the
    // "-color" suffix is inconsistent upstream artwork, not a convention.
    // The raw envelope's provider array (id, details.stats, ...) from the
    // latest backend snapshot — distinct from `providers` below, which is a
    // static UI registry (label/color/icon) and never carries live stats.
    property var rawProviders: []
    readonly property var providers: [
        {
            id: "claude",
            label: "Claude",
            color: root.claudeOrange,
            icon: "claude-color.svg",
            keyConfig: "claudeAdminApiKey",
            keyPlaceholder: "sk-ant-api03-…"
        },
        {
            id: "antigravity",
            label: "Antigravity",
            color: root.googleBlue,
            icon: "antigravity-color.svg"
        },
        {
            id: "openai",
            label: "OpenAI",
            color: root.openaiGreen,
            icon: "openai.svg",
            keyConfig: "openaiApiKey",
            keyPlaceholder: "sk-proj-…"
        },
        {
            id: "kiro",
            label: "Kiro",
            color: root.kiroPurple,
            icon: "kiro.svg"
        },
        {
            id: "mistral",
            label: "Mistral",
            color: root.mistralOrange,
            icon: "mistral-color.svg",
            keyConfig: "mistralApiKey",
            keyPlaceholder: i18n("empty → $MISTRAL_API_KEY")
        },
        {
            id: "openrouter",
            label: "OpenRouter",
            color: root.openrouterPurple,
            icon: "openrouter.svg",
            keyConfig: "openrouterApiKey",
            keyPlaceholder: i18n("empty → $OPENROUTER_API_KEY")
        },
        {
            id: "ollama",
            label: "Ollama Cloud",
            color: "#f0f0f0",
            icon: "ollama.svg",
            keyConfig: "ollamaApiKey",
            keyPlaceholder: i18n("optional — OpenCode login or $OLLAMA_API_KEY")
        },
        {
            id: "selfhosted",
            label: i18n("Local Models"),
            color: "#38bdf8",
            icon: "local-models.svg"
        },
        {
            id: "grok",
            label: "Grok",
            color: root.grokWhite,
            icon: "grok.svg",
            keyConfig: "grokApiKey",
            keyPlaceholder: i18n("empty → $GROK_API_KEY")
        },
        {
            id: "zai",
            label: "Z.AI",
            color: root.zaiBlue,
            icon: "zai.svg",
            keyConfig: "zaiToken",
            keyPlaceholder: i18n("empty → $ZAI_TOKEN")
        },
        {
            id: "copilot",
            label: "Copilot",
            color: root.copilotPurple,
            icon: "githubcopilot.svg",
            keyConfig: "githubToken",
            keyPlaceholder: i18n("optional — gh/Copilot login is used")
        },
        {
            id: "deepseek",
            label: "DeepSeek",
            color: root.deepseekBlue,
            icon: "deepseek-color.svg",
            keyConfig: "deepseekApiKey",
            keyPlaceholder: i18n("empty → $DEEPSEEK_API_KEY")
        },
        {
            id: "kimi",
            label: "Kimi",
            color: root.kimiBlue,
            icon: "kimi.svg",
            keyConfig: "moonshotApiKey",
            keyPlaceholder: i18n("empty → $MOONSHOT_API_KEY")
        },
        {
            id: "muse",
            label: "Muse",
            color: root.museBlue,
            icon: "muse-color.svg",
            keyConfig: "museApiKey",
            keyPlaceholder: i18n("optional — the CLI login is used")
        },
        {
            id: "cursor",
            label: "Cursor",
            color: root.cursorWhite,
            icon: "cursor.svg"
        },
        {
            id: "cline",
            label: "Cline",
            color: root.clineWhite,
            icon: "cline.svg"
        },
        {
            id: "opencode",
            label: "OpenCode",
            color: "#B7B1B1",
            icon: "opencode-color.svg"
        }
    ]

    function providerById(tabId) {
        for (var i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === tabId)
                return root.providers[i];
        }
        return null;
    }

    function rawProviderById(providerId) {
        for (var i = 0; i < root.rawProviders.length; i++) {
            if (root.rawProviders[i] && root.rawProviders[i].id === providerId)
                return root.rawProviders[i];
        }
        return null;
    }
    // ── Accent (theme-aware) ────────────────────────────────────────────────────
    property bool useThemeAccent: Plasmoid.configuration.useThemeAccent
    // Accent for the currently active tab
    readonly property color activeAccent: root.accentFor(root.enabledTabs[root.activeTab] || "claude")
    // ── Appearance Customization ────────────────────────────────────────────────
    property int backgroundHints: Plasmoid.configuration.backgroundHints !== undefined ? Plasmoid.configuration.backgroundHints : 1
    property int popupDecoration: Plasmoid.configuration.popupDecoration !== undefined ? Plasmoid.configuration.popupDecoration : 0
    property color cardBgColor: Plasmoid.configuration.cardBgColor || "#100a1a"
    property real cardBgOpacity: Plasmoid.configuration.cardBgOpacity !== undefined ? Plasmoid.configuration.cardBgOpacity : 0.9
    property color popupBgColor: Plasmoid.configuration.popupBgColor || "#000000"
    property real popupBgOpacity: Plasmoid.configuration.popupBgOpacity !== undefined ? Plasmoid.configuration.popupBgOpacity : 0
    readonly property color resolvedCardBg: {
        var c = Qt.color(root.cardBgColor);
        return Qt.rgba(c.r, c.g, c.b, root.cardBgOpacity);
    }
    readonly property color resolvedPopupBg: {
        var c = Qt.color(root.popupBgColor);
        return Qt.rgba(c.r, c.g, c.b, root.popupBgOpacity);
    }
    property string colorTarget: "popup"
    // ── Pin (active tab stays the default) ─────────────────────────────────────
    property string pinnedTab: Plasmoid.configuration.pinnedTab || ""
    readonly property var pinnedTabs: {
        var pins = [];
        var raw = root.pinnedTab || "";
        var parts = raw.split(",");
        for (var i = 0; i < parts.length; i++) {
            var tab = parts[i].trim();
            if (tab !== "" && root.enabledTabs.indexOf(tab) >= 0 && pins.indexOf(tab) < 0)
                pins.push(tab);
        }
        return pins;
    }
    property int panelRotationIntervalSec: PanelRotation.normalizeIntervalSec(Plasmoid.configuration.panelRotationIntervalSec)
    property string panelRotationProviderId: ""
    readonly property bool panelRotationEnabled: PanelRotation.isEnabled(root.panelRotationIntervalSec, root.pinnedTabs)

    function normalizePanelRotation() {
        root.panelRotationProviderId = PanelRotation.normalizeSelection(root.pinnedTabs, root.panelRotationProviderId);
    }

    function rotatePanelProvider() {
        root.panelRotationProviderId = PanelRotation.nextSelection(root.pinnedTabs, root.panelRotationProviderId);
    }

    onPinnedTabsChanged: root.normalizePanelRotation()
    onPanelRotationIntervalSecChanged: root.normalizePanelRotation()
    // ── Cost aggregation ─────────────────────────────────────────────────────────
    // Combined spend across paid API surfaces. Claude/OpenAI are 30-day org usage;
    // OpenRouter reports all-time credit spend, so the total is a rough combined figure.
    readonly property real totalSpendUSD: {
        var sum = 0;
        if (root.claudeTotalCostUSD > 0)
            sum += root.claudeTotalCostUSD;

        if (root.openaiTotalCostUSD > 0)
            sum += root.openaiTotalCostUSD;

        if (root.openrouterUsageUSD > 0)
            sum += root.openrouterUsageUSD;

        return sum;
    }
    // ── Timers ────────────────────────────────────────────────────────────────
    // Poll interval is user-configurable (seconds); default 300s. Clamp to a sane floor.
    property int pollIntervalSec: Plasmoid.configuration.pollIntervalSec || 300
    property bool pricingLoading: false
    property string pricingStatus: ""
    property string pricingError: ""
    property bool providerDefaultsReady: false
    property bool providerDefaultsInitializing: false
    property bool providerDetectBusy: false
    property string providerDetectStatus: ""

    function shellQuote(s) {
        return Shell.quote(s);
    }

    function scriptPath(name) {
        return root.shellQuote([root.scriptDir, name].join(""));
    }

    // Chart ranges the backend reported for a provider, newest snapshot wins.
    function chartWindowsFor(tab) {
        return root.providerChartWindows[tab] || [];
    }

    // The range currently selected on the active tab, or null when the provider
    // has no chartable series (or has not been fetched yet).
    function currentChartWindow() {
        var windows = root.chartWindowsFor(root.enabledTabs[root.activeTab] || "");
        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === root.chartWindow)
                return windows[i];
        }
        return windows.length > 0 ? windows[windows.length - 1] : null;
    }

    // Window ID for a tab at the remembered granularity, so the selected time
    // range carries across services. Providers with a single fixed range return
    // that one; an unknown tab keeps the current selection.
    function _windowForTab(tab, gran) {
        var windows = root.chartWindowsFor(tab);
        if (windows.length === 0)
            return root.chartWindow;

        for (var i = 0; i < windows.length; i++) {
            if (windows[i].granularity === gran)
                return windows[i].id;
        }
        return windows[windows.length - 1].id;
    }

    // Called after a provider refresh: if the selected range vanished (a plan
    // window the provider stopped reporting), fall back to a range it still has.
    function ensureAvailableChartWindow(provider) {
        if (root.enabledTabs[root.activeTab] !== provider)
            return;

        var windows = root.chartWindowsFor(provider);
        if (windows.length === 0)
            return;

        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === root.chartWindow)
                return;
        }

        var fallback = windows[windows.length - 1];
        root.chartWindow = fallback.id;
        Plasmoid.configuration.chartWindow = root.chartWindow;
        if (fallback.granularity !== "") {
            root.chartGranularity = fallback.granularity;
            Plasmoid.configuration.chartGranularity = root.chartGranularity;
        }
    }

    function _historyKey() {
        var win = root.currentChartWindow();
        if (!win)
            return "";
        var tab = root.enabledTabs[root.activeTab] || "";
        if (tab === "antigravity") {
            if (root.antigravityChartFilter === "gemini")
                return "agg";
            if (root.antigravityChartFilter === "rest")
                return "age";
            return "ag";
        }
        return win.key;
    }

    function hasAnySeriesData() {
        var win = root.currentChartWindow();
        if (!win)
            return false;
        var tab = root.enabledTabs[root.activeTab] || "";
        var key = win.key;
        for (var i = 0; i < root.usageHistory.length; i++) {
            var p = root.usageHistory[i];
            if (tab === "antigravity") {
                if (p.agg !== undefined || p.age !== undefined || p.ag !== undefined)
                    return true;
            } else if (p[key] !== undefined && p[key] !== null) {
                return true;
            }
        }
        return false;
    }

    function getChartWindowSize() {
        var win = root.currentChartWindow();
        return win ? win.size : 7 * 24 * 3.6e+06;
    }

    function getChartRangeText() {
        var now_ms = new Date().getTime();
        var offset = root.chartTimeOffset;
        var winSize = root.getChartWindowSize();
        var maxT = now_ms - offset;
        var minT = maxT - winSize;
        var minDate = new Date(minT);
        var maxDate = new Date(maxT);
        var isHourly = winSize <= 24 * 3.6e+06;
        if (isHourly) {
            if (minDate.toDateString() === maxDate.toDateString())
                return Qt.formatDateTime(minDate, "hh:mm") + " - " + Qt.formatDateTime(maxDate, "hh:mm") + " (" + Qt.formatDateTime(maxDate, "MMM d") + ")";
            else
                return Qt.formatDateTime(minDate, "MMM d, hh:mm") + " - " + Qt.formatDateTime(maxDate, "MMM d, hh:mm");
        } else {
            return Qt.formatDateTime(minDate, "MMM d") + " - " + Qt.formatDateTime(maxDate, "MMM d");
        }
    }

    function loadUsageHistory() {
        var raw = Plasmoid.configuration.usageHistory || "";
        // The config is a backup of the series, not the live store — the mirror
        // file is, since both frontends share it. It is only read here, at startup.
        if (!raw)
            // Legacy weekly-only history ({t, v}); normalize() migrates the shape.
            raw = Plasmoid.configuration.weeklyUsageHistory || "";
        if (raw) {
            try {
                // restore(), not record(): the config is this widget's own backup
                // and can be older than the shared file, so it is offered to it
                // rather than asserted over it.
                UsageHistory.restore(root.historyStore, JSON.parse(raw));
                root.syncUsageHistory();
            } catch (_) {
                // Unparseable config — the mirror file is the real store anyway.
            }
        }
        // Always sync with the shared mirror file on disk so points recorded in
        // Hyprland / Quickshell are merged seamlessly when switching back.
        root.autoloadHistory();
    }

    // The save protocol is in UsageHistory.js, shared with the Quickshell panel;
    // what is left here is the transport, the clock and the timers. The store's
    // `ready` flag is what keeps the mirror file from being written before the
    // startup autoload has answered — that read is async while the poll timer
    // fires at once, and a write that got in first would drop everything recorded
    // under Hyprland. `historyLimit` is readonly, so this binding runs once.
    property var historyStore: UsageHistory.newStore(root.historyLimit)
    // JSON form of usageHistory, kept alongside it so nothing has to re-serialize
    // ~30-100 KiB to find out whether anything actually changed.
    property string historyJson: "[]"
    property bool historyConfigDirty: false
    // The command the batch in flight went out on, so the watchdog can drop it.
    property string historySaveCmd: ""

    // Publish the store's series to the bindings. It replaces `history` rather
    // than patching it, so an unchanged reference means nothing to repaint.
    function syncUsageHistory() {
        if (root.usageHistory === root.historyStore.history)
            return;

        root.usageHistory = root.historyStore.history;
        // Same content, different array: worth the reference swap, not a rewrite
        // of every widget's config.
        if (root.historyJson === root.historyStore.json)
            return;

        root.historyJson = root.historyStore.json;
        root.historyConfigDirty = true;
    }

    // What the config is allowed to hold. Plasma rewrites
    // plasma-org.kde.plasma.desktop-appletsrc — the config of every widget on the
    // desktop — whole on each change, so the series has no business going through
    // it: the mirror file is the store, and the config only has to seed a fresh
    // install. It also bounds the startup seed, which is built from it and travels
    // a command line.
    readonly property int historyConfigLimit: 500

    function flushHistoryConfig() {
        if (!root.historyConfigDirty)
            return;

        root.historyConfigDirty = false;
        var points = root.usageHistory;
        // historyJson is already the whole series serialized, so only a tail costs
        // anything to produce.
        Plasmoid.configuration.usageHistory = points.length > root.historyConfigLimit ? JSON.stringify(points.slice(points.length - root.historyConfigLimit)) : root.historyJson;
    }

    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: root.flushHistoryConfig()
    }

    // One poll's provider values — the backend decides which keys a provider
    // contributes (historyValues in the contract). Called on every snapshot even
    // when none reported, which is what releases a save that failed.
    function recordHistoryValues(values) {
        UsageHistory.record(root.historyStore, values, new Date().getTime());
        root.syncUsageHistory();
        root.saveHistory();
    }

    // Ship the next batch to ~/.local/share/ai-usage-widget/usage-history-latest.json,
    // shared with the Quickshell frontend. history-io unions it in and hands the
    // merged series back, so this is also how the other frontend's points arrive.
    // take() decides whether there is anything to send, and what.
    function saveHistory() {
        var batch = UsageHistory.take(root.historyStore);
        if (!batch)
            return;

        historySaveTimeout.restart();
        // Pass the payload base64-encoded and decode it inside the shell, so the
        // JSON (quotes, brackets) never has to survive command-line quoting.
        root.historySaveCmd = root.pythonEnv() + "WIDGET_HISTORY_JSON=\"$(printf %s '" + root.base64(JSON.stringify(batch.points)) + "' | base64 -d)\" " + root.scriptPath("history-io") + " " + batch.op;
        historyIOSource.disconnectSource(root.historySaveCmd);
        historyIOSource.connectSource(root.historySaveCmd);
    }

    function finishHistorySave(merged) {
        historySaveTimeout.stop();
        root.historySaveCmd = "";
        UsageHistory.done(root.historyStore, merged);
        root.syncUsageHistory();
        // Whatever queued up while that batch was out goes now.
        root.saveHistory();
    }

    function failHistorySave() {
        historySaveTimeout.stop();
        // Drop the source too: answering after the watchdog has given up would
        // otherwise be taken for the answer to whatever went out since.
        if (root.historySaveCmd !== "")
            historyIOSource.disconnectSource(root.historySaveCmd);

        root.historySaveCmd = "";
        UsageHistory.failed(root.historyStore);
    }

    // A save that never answers would hold its batch in flight for the rest of
    // the session and stop this widget mirroring at all.
    Timer {
        id: historySaveTimeout

        interval: 30000
        repeat: false
        onTriggered: root.failHistorySave()
    }

    // The startup read is done (or gave up): the mirror is ours to write again.
    function releaseHistoryMirror() {
        if (root.historyStore.ready)
            return;

        historyMirrorTimeout.stop();
        UsageHistory.opened(root.historyStore);
        root.saveHistory();
    }

    // Waiting for the read is only ever a short deferral. If the answer never
    // comes — no shell tool, a command that never reports back — mirroring again
    // beats a widget that silently stops saving to disk for the rest of its life.
    Timer {
        id: historyMirrorTimeout

        interval: 15000
        running: true
        repeat: false
        onTriggered: root.releaseHistoryMirror()
    }

    // Restore from the mirror file when plasmoid config has no history (e.g. fresh install).
    function autoloadHistory() {
        var cmd = root.pythonEnv() + root.scriptPath("history-io") + " autoload";
        historyIOSource.disconnectSource(cmd);
        historyIOSource.connectSource(cmd);
    }

    // {t,v} view of a series ("s" or "w"), last `n` points, for spark-lines.
    function sparkSeries(seriesKey, n) {
        var out = [];
        var pts = root.usageHistory;
        for (var i = 0; i < pts.length; i++) {
            var v = pts[i][seriesKey];
            if (v === undefined || v === null)
                continue;

            out.push({
                "t": pts[i].t,
                "v": v
            });
        }
        if (n && out.length > n)
            out = out.slice(out.length - n);

        return out;
    }

    // Grab while the popup is still open and visible, save straight to Downloads.
    function doExportSnapshot(grabItem, format) {
        var tab = root.enabledTabs[root.activeTab] || "tab";
        var ts = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
        var baseName = "ai-usage-" + tab + "-" + ts;
        var tmpPng = "/tmp/" + baseName + ".png";
        root._exportFormat = format;
        root._exportW = Math.round(grabItem.width);
        root._exportH = Math.round(grabItem.implicitHeight > 0 ? grabItem.implicitHeight : grabItem.height);
        root._exportHideHeader = true;
        Qt.callLater(function () {
            grabItem.grabToImage(function (result) {
                root._exportHideHeader = false;
                if (!result.saveToFile(tmpPng)) {
                    var failCmd = "notify-send " + root.shellQuote("AI Usage Widget") + " " + root.shellQuote(i18n("Export failed: could not capture image"));
                    exportSaveSource.disconnectSource(failCmd);
                    exportSaveSource.connectSource(failCmd);
                    return;
                }
                // Save into the XDG Downloads directory, whose name is localized
                // (~/Téléchargements in French, ~/Downloads elsewhere). xdg-user-dir
                // ships with every freedesktop desktop; fall back to the
                // conventional English name only when it is missing.
                var fileName = baseName + "." + format;
                var cmd = "dl=\"$(xdg-user-dir DOWNLOAD 2>/dev/null || printf %s \"$HOME/Downloads\")\"; mkdir -p \"$dl\" && " + root.pythonEnv() + root.scriptPath("export-snapshot") + " " + root.shellQuote(format) + " " + root.shellQuote(tmpPng) + " \"$dl/" + fileName + "\"";
                if (format === "svg")
                    cmd += " " + root._exportW + " " + root._exportH;

                cmd += " && notify-send " + root.shellQuote("AI Usage Widget") + " \"$(printf " + root.shellQuote(i18n("Saved to %1", "%s")) + " \"$dl/" + fileName + "\")\"";
                exportSaveSource.disconnectSource(cmd);
                exportSaveSource.connectSource(cmd);
            });
        });
    }

    // history-io snapshots the shared file itself — see the note there for why the
    // series does not travel on a command line.
    function exportHistory() {
        var cmd = root.pythonEnv() + root.scriptPath("history-io") + " export";
        historyIOSource.disconnectSource(cmd);
        historyIOSource.connectSource(cmd);
    }

    function importHistory() {
        var cmd = root.pythonEnv() + root.scriptPath("history-io") + " import";
        historyIOSource.disconnectSource(cmd);
        historyIOSource.connectSource(cmd);
    }

    function tabColor(tabId) {
        if (FeatureTabs.isFeatureTab(tabId)) {
            var accent = FeatureTabs.accent(tabId);
            return accent !== "" ? accent : Kirigami.Theme.highlightColor;
        }
        var p = root.providerById(tabId);
        return p ? p.color : Kirigami.Theme.textColor;
    }

    function tabName(tabId) {
        if (FeatureTabs.isFeatureTab(tabId))
            return FeatureTabs.label(tabId, i18n);
        var p = root.providerById(tabId);
        return p ? p.label : tabId;
    }

    // Open the tab used last time, or the first provider on a fresh widget —
    // never a feature view by default, since the panel mirrors the active tab
    // and a feature view has no meter of its own. Resolved by id, so it stays
    // on the same tab when providers are enabled or disabled around it.
    function restoreTab() {
        if (root.pinnedTabs.length > 0) {
            var pinned = root.enabledTabs.indexOf(root.pinnedTabs[0]);
            if (pinned >= 0) {
                root.activeTab = pinned;
                return;
            }
        }
        var idx = root.enabledTabs.indexOf(root.savedTab);
        for (var i = 0; idx < 0 && i < root.enabledTabs.length; i++) {
            if (!FeatureTabs.isFeatureTab(root.enabledTabs[i]))
                idx = i;
        }
        root.activeTab = Math.max(0, idx);
    }

    // Switch the popup to a provider (or feature) tab by id.
    function selectTab(tabId) {
        var idx = root.enabledTabs.indexOf(tabId);
        if (idx < 0)
            return;
        root.activeTab = idx;
        root.errorMsg = "";
        if (!FeatureTabs.isFeatureTab(tabId))
            root.refresh();
    }

    function formatMoney(value, currency) {
        var cur = currency || "";
        var amount = Number(value || 0).toFixed(2);
        if (cur === "USD")
            return "$" + amount;

        if (cur === "CNY")
            return "¥" + amount;

        return amount + (cur ? " " + cur : "");
    }

    // Rate-limit tier shown in the Claude header, with the known words
    // localized ("default_claude_ai" → "Par défaut", "default_max_20x" →
    // "Par défaut Max 20x", …). Unknown words keep a capitalized form.
    // The backend emits stable English tokens (the wire contract is never
    // localized). Translate the fixed ones by literal id here, so xgettext can
    // extract them and the i18n tooling keeps context and plurals.
    function errorText(token) {
        if (token === "offline")
            return i18n("offline");
        if (token === "token expired")
            return i18n("token expired");
        if (token === "access denied")
            return i18n("access denied");
        if (token === "rate limited")
            return i18n("rate limited");
        if (token.indexOf("err ") === 0)
            return i18n("err %1", token.slice(4));
        return token;
    }

    function windowLabel(label) {
        if (label === "5H")
            return i18n("5H");
        if (label === "24H")
            return i18n("24H");
        if (label === "7D")
            return i18n("7D");
        if (label === "30D")
            return i18n("30D");
        return label;
    }

    function antigravityGroupLabel(label) {
        if (label === "Gemini Models")
            return i18n("Gemini Models");
        if (label === "Claude & GPT Models")
            return i18n("Claude & GPT Models");
        return label;
    }

    // Kimi Code windows arrive as a length in seconds (or a vendor name); the
    // backend's English label stays for the CLI.
    function kimiWindowLabel(w) {
        if (w.name)
            return w.name;
        var s = w.seconds || 0;
        if (s === 604800)
            return i18n("Weekly limit");
        if (s === 86400)
            return i18n("Daily limit");
        if (s && s % 86400 === 0)
            return i18np("%1-day limit", "%1-day limit", s / 86400);
        if (s && s % 3600 === 0)
            return i18np("%1-hour limit", "%1-hour limit", s / 3600);
        if (s)
            return i18np("%1-minute limit", "%1-minute limit", Math.floor(s / 60));
        return i18n("Plan usage");
    }

    // Kimi's own wording when it sends one; the backend's fallback is English.
    function kimiPlanMessageText() {
        if (root.kimiPlanMessage === "" || root.kimiPlanMessage === "Plan quota used up")
            return i18n("Plan quota used up");
        return root.kimiPlanMessage;
    }

    function clinePeriodLabel(p) {
        if (p.key === "cline_today")
            return i18n("Today");
        if (p.key === "cline_7d")
            return i18n("Last 7 days");
        if (p.key === "cline_30d")
            return i18n("Last 30 days");
        return p.label;
    }

    function grokQuotaWindowText() {
        return root.grokQuotaWindow === "rolling 24h" ? i18n("rolling 24h") : root.grokQuotaWindow;
    }

    function claudeTierLabel() {
        var raw = root.claudeRateLimitTier;
        if (!raw)
            return "";
        var parts = String(raw).replace(/_claude_ai$/i, "").split("_");
        var words = [];
        for (var i = 0; i < parts.length; i++) {
            var w = parts[i];
            if (w === "default")
                words.push(i18nc("rate limit tier", "default"));
            else if (w === "pro")
                words.push(i18nc("rate limit tier", "pro"));
            else if (w === "max")
                words.push(i18nc("rate limit tier", "max"));
            else if (w === "business")
                words.push(i18nc("rate limit tier", "business"));
            else if (w === "free")
                words.push(i18nc("rate limit tier", "free"));
            else
                words.push(w.charAt(0).toUpperCase() + w.slice(1));
        }
        return words.join(" ");
    }

    function effortLabel(level) {
        if (level === "high")
            return i18nc("effort level", "high");
        if (level === "low")
            return i18nc("effort level", "low");
        if (level === "medium")
            return i18nc("effort level", "medium");
        return level;
    }

    // Resolve a service's accent: the Plasma highlight color when theme accent is on,
    // otherwise the service's own brand color.
    // Brand logo for a tab, or "" when the provider has no artwork yet (callers
    // fall back to the plain colour dot).
    function tabIcon(tabId) {
        if (FeatureTabs.isFeatureTab(tabId))
            return "";
        var p = root.providerById(tabId);
        return p && p.icon ? Qt.resolvedUrl("../icons/" + p.icon) : "";
    }

    function accentFor(tabId) {
        if (root.useThemeAccent)
            return Kirigami.Theme.highlightColor;

        return root.tabColor(tabId);
    }

    function openColorDialog(target, selectedColor) {
        root.colorTarget = target;
        colorDialog.selectedColor = selectedColor;
        colorDialog.open();
    }

    function isPinned(tabId) {
        return root.pinnedTabs.indexOf(tabId) >= 0;
    }

    function panelShows(tabId) {
        if (root.pinnedTabs.length === 0)
            return root.panelTab === tabId;
        return root.panelRotationEnabled ? root.panelTab === tabId : root.isPinned(tabId);
    }

    function togglePin(tabId) {
        if (FeatureTabs.isFeatureTab(tabId))
            return;
        var pins = root.pinnedTabs.slice();
        var pos = pins.indexOf(tabId);
        if (pos >= 0)
            pins.splice(pos, 1);
        else
            pins.push(tabId);
        root.pinnedTab = pins.join(",");
        Plasmoid.configuration.pinnedTab = root.pinnedTab;
        // When adding a pin, jump the active view to that tab.
        if (pos < 0) {
            var idx = root.enabledTabs.indexOf(tabId);
            if (idx >= 0 && idx !== root.activeTab) {
                root.activeTab = idx;
                root.errorMsg = "";
                root.refresh();
            }
        }
    }

    // ── Burn-rate / ETA ─────────────────────────────────────────────────────────
    // Slope (%/hour) over up to the last `windowMs` of the given series key, or
    // null when there is not enough recent data. See UsageHistory.slopePerHour.
    function usageSlopePerHour(seriesKey, windowMs) {
        return UsageHistory.slopePerHour(root.usageHistory, seriesKey, windowMs);
    }

    // ETA text to reach 100% for a series given its current value. Returns "" when
    // not climbing (or climbing too slowly to matter / already full).
    function etaToFull(seriesKey, currentPct) {
        // need a meaningful climb
        // >10 days out: not actionable

        if (currentPct >= 100)
            return "";

        var slope = root.usageSlopePerHour(seriesKey, 6 * 3.6e+06); // last 6h trend
        if (slope === null || slope < 0.5)
            return "";

        var hoursLeft = (100 - currentPct) / slope;
        if (hoursLeft > 240)
            return "";

        if (hoursLeft < 1)
            return i18n("~%1m to 100%", Math.max(1, Math.round(hoursLeft * 60)));

        if (hoursLeft < 24)
            return i18n("~%1h to 100%", hoursLeft.toFixed(1).replace(/\.0$/, ""));

        return i18n("~%1d to 100%", Math.round(hoursLeft / 24));
    }

    // Period-over-period comparison: current value vs the sample closest to `periodMs` ago.
    // Returns "" if there's no comparable older sample; otherwise e.g. "+12% vs last week".
    function periodDelta(seriesKey, currentPct, periodMs, periodLabel) {
        var pts = root.usageHistory;
        if (!pts || pts.length < 2)
            return "";

        var now = pts[pts.length - 1].t;
        var target = now - periodMs;
        // need history reaching back at least ~80% of the period to be meaningful
        if (pts[0].t > target + periodMs * 0.2)
            return "";

        // find sample nearest the target time that has this series
        var best = null, bestDist = Infinity;
        for (var i = 0; i < pts.length; i++) {
            var v = pts[i][seriesKey];
            if (v === undefined || v === null)
                continue;

            var d = Math.abs(pts[i].t - target);
            if (d < bestDist) {
                bestDist = d;
                best = v;
            }
        }
        if (best === null)
            return "";

        var diff = Math.round(currentPct - best);
        if (diff === 0)
            return i18n("≈ same as %1", periodLabel);

        return i18n("%1 vs %2", (diff > 0 ? "+" : "") + diff + "%", periodLabel);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function formatTokens(n) {
        if (n >= 1e+06)
            return (n / 1e+06).toFixed(2) + "M";

        if (n >= 1000)
            return (n / 1000).toFixed(1) + "K";

        return Math.round(n).toString();
    }

    function formatDuration(ms) {
        if (!ms || ms <= 0)
            return "—";

        var totalMins = Math.floor(ms / 60000);
        var d = Math.floor(totalMins / 1440);
        var h = Math.floor((totalMins % 1440) / 60);
        var m = totalMins % 60;
        var parts = [];
        if (d > 0)
            // xgettext:no-javascript-format
            parts.push(i18nc("duration in days, abbreviated", "%1d", d));

        if (h > 0)
            parts.push(i18nc("duration in hours, abbreviated", "%1h", h));

        if (d === 0 && m > 0)
            parts.push(i18nc("duration in minutes, abbreviated", "%1m", m));

        return parts.length ? parts.join(" ") : i18n("<1m");
    }

    function formatCountdown(targetDate) {
        return Format.countdown(targetDate ? targetDate.getTime() : 0, new Date().getTime());
    }

    function updateCountdowns() {
        root.sessionCountdown = root.formatCountdown(root.sessionResetDate);
        root.weeklyCountdown = root.formatCountdown(root.weeklyResetDate);
        root.antigravityCountdown = root.formatCountdown(root.antigravityResetDate);
        root.codexSessionCountdown = root.formatCountdown(root.codexSessionResetDate);
        root.codexWeeklyCountdown = root.formatCountdown(root.codexWeeklyResetDate);
        root.kiroCountdown = root.formatCountdown(root.kiroResetDate);
        root.zaiTokenCountdown = root.formatCountdown(root.zaiTokenResetDate);
        root.zaiToolsCountdown = root.formatCountdown(root.zaiToolsResetDate);
        root.copilotCountdown = root.formatCountdown(root.copilotResetDate);
        root.museCurrentCountdown = root.formatCountdown(root.museCurrentResetDate);
        root.museWeeklyCountdown = root.formatCountdown(root.museWeeklyResetDate);
        root.cursorCountdown = root.formatCountdown(root.cursorResetDate);
        root.countdownTick++;
    }

    function usageColor(pct) {
        if (pct >= 90)
            return root.dangerColor;

        if (pct >= 70)
            return root.warningColor;

        return Kirigami.Theme.textColor;
    }

    function shortenModelName(name) {
        return name.replace(/gpt-4o-mini/g, "4o-mini").replace(/gpt-4o/g, "4o").replace(/gpt-4-turbo/g, "4-turbo").replace(/gpt-4-32k/g, "4-32k").replace(/gpt-4/g, "4").replace(/gpt-3\.5-turbo/g, "3.5-turbo").replace(/o1-mini/g, "o1-mini").replace(/o3-mini/g, "o3-mini").replace(/o4-mini/g, "o4-mini").replace(/claude-3-5-/g, "3.5-").replace(/claude-3-/g, "3-").replace(/claude-/g, "").replace(/-\d{8}$/, "").replace(/-20\d{2}-\d{2}-\d{2}$/, "");
    }

    // ── Shared provider backend ───────────────────────────────────────────────
    // Everything below only maps the backend's frontend-neutral JSON onto the
    // properties the tabs bind to. No provider API call, response parsing or
    // quota arithmetic lives in this widget any more — see
    // tools/sh/get-ai-usage and docs/provider-contract.md.

    function dateFromEpoch(seconds) {
        if (seconds === null || seconds === undefined || seconds <= 0)
            return null;

        var date = new Date(seconds * 1000);
        return isNaN(date.getTime()) ? null : date;
    }

    function emptyStatus() {
        return {
            "indicator": "",
            "description": "",
            "components": [],
            "incidents": [],
            "latestUpdate": "",
            "url": ""
        };
    }

    // Encoding lives in code/Shell.js so it can be unit-tested outside a QML
    // engine (tests/shared-code.test.js) — the widget-config keys used to reach
    // the backend mangled, and nothing here could catch it.
    function base64(text) {
        return Shell.base64(text);
    }

    // base64-encode secrets so shell metacharacters in them can't break out of
    // the command string (decoded back in the env assignment).
    function envAssign(name, value) {
        return Shell.envAssign(name, value);
    }

    // All three shell tools resolve their interpreter through
    // tools/sh/python-interp.sh, which $PYTHON3 overrides. Empty setting means
    // "search PATH", so every command below is unchanged for users who never
    // touch it. Reuses envAssign's base64 round-trip because a path may contain
    // spaces or shell metacharacters.
    function pythonEnv() {
        var env = root.envAssign("PYTHON3", String(Plasmoid.configuration.pythonPath || "").trim());
        // Let the backend load the catalog of the applet it is actually
        // installed as — the test copy renames its .mo to its own id.
        env += root.envAssign("AI_USAGE_I18N_DOMAIN", "plasma_applet_" + (Plasmoid.metaData ? Plasmoid.metaData.pluginId : ""));
        return env;
    }

    // Providers main.xml ships switched on. A fresh widget turns these off
    // unless detected; every other provider already defaults off.
    readonly property var legacyDefaultOnProviders: ["claude", "antigravity", "openai", "kiro", "grok"]

    function applyDetectedProviders(detected) {
        var ids = ["claude", "antigravity", "openai", "kiro", "mistral", "openrouter", "ollama", "selfhosted", "grok", "zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "opencode"];
        for (var i = 0; i < ids.length; i++) {
            var id = ids[i];
            var key = id + "Enabled";
            if (detected.indexOf(id) !== -1)
                Plasmoid.configuration[key] = true;
            else if (root.legacyDefaultOnProviders.indexOf(id) !== -1)
                Plasmoid.configuration[key] = false;
        }
    }

    function initializeProviderDefaults() {
        if (Plasmoid.configuration.providerDefaultsApplied === true) {
            root.providerDefaultsReady = true;
            return;
        }
        // A widget that has stored usage history was in use before
        // zero-default: keep exactly the providers it shows and never probe.
        if ((Plasmoid.configuration.usageHistory || "") !== "") {
            Plasmoid.configuration.providerDefaultsApplied = true;
            root.providerDefaultsReady = true;
            return;
        }
        root.providerDefaultsInitializing = true;
        var cmd = root.pythonEnv() + root.scriptPath("get-ai-usage") + " --detect-providers";
        providerDefaultsSource.disconnectSource(cmd);
        providerDefaultsSource.connectSource(cmd);
    }

    // Settings → Providers → "Detect installed providers": re-runs the
    // stat-only detection and switches on what it finds (never off).
    function redetectProviders() {
        if (root.providerDetectBusy)
            return;
        root.providerDetectBusy = true;
        root.providerDetectStatus = "";
        var cmd = root.pythonEnv() + root.scriptPath("get-ai-usage") + " --detect-providers";
        providerRedetectSource.disconnectSource(cmd);
        providerRedetectSource.connectSource(cmd);
    }

    function applyProviderRedetect(result) {
        root.providerDetectBusy = false;
        if (!result || result.ok !== true || !Array.isArray(result.data)) {
            root.providerDetectStatus = i18n("Detection failed.");
            return;
        }
        var added = [];
        for (var i = 0; i < root.providers.length; i++) {
            var p = root.providers[i];
            if (result.data.indexOf(p.id) !== -1 && !Plasmoid.configuration[p.id + "Enabled"]) {
                Plasmoid.configuration[p.id + "Enabled"] = true;
                added.push(p.label || p.id);
            }
        }
        root.providerDetectStatus = added.length ? i18n("Enabled: %1", added.join(", ")) : i18n("No new providers found.");
        if (added.length)
            root.refresh();
    }

    function backendCommand(ids) {
        var env = root.pythonEnv();
        env += root.envAssign("WIDGET_CLAUDE_ADMIN_KEY", Plasmoid.configuration.claudeAdminApiKey);
        env += root.envAssign("WIDGET_OPENAI_API_KEY", Plasmoid.configuration.openaiApiKey);
        env += root.envAssign("WIDGET_MISTRAL_API_KEY", Plasmoid.configuration.mistralApiKey);
        env += root.envAssign("WIDGET_OPENROUTER_API_KEY", Plasmoid.configuration.openrouterApiKey);
        env += root.envAssign("WIDGET_OLLAMA_API_KEY", Plasmoid.configuration.ollamaApiKey);
        env += root.envAssign("WIDGET_SELFHOSTED_ENDPOINT", Plasmoid.configuration.selfhostedEndpoint);
        env += root.envAssign("WIDGET_SELFHOSTED_ENGINE", Plasmoid.configuration.selfhostedEngine);
        env += root.envAssign("WIDGET_SELFHOSTED_KEY", Plasmoid.configuration.selfhostedKey);
        env += root.envAssign("WIDGET_GROK_API_KEY", Plasmoid.configuration.grokApiKey);
        env += root.envAssign("WIDGET_ZAI_TOKEN", Plasmoid.configuration.zaiToken);
        env += root.envAssign("WIDGET_GITHUB_TOKEN", Plasmoid.configuration.githubToken);
        env += root.envAssign("WIDGET_MUSE_API_KEY", Plasmoid.configuration.museApiKey);
        env += "WIDGET_MUSE_QUOTA=" + (Plasmoid.configuration.museQuotaEnabled === true ? "1" : "0") + " ";
        env += root.envAssign("WIDGET_DEEPSEEK_API_KEY", Plasmoid.configuration.deepseekApiKey);
        env += root.envAssign("WIDGET_MOONSHOT_API_KEY", Plasmoid.configuration.moonshotApiKey);
        var quota = parseInt(Plasmoid.configuration.copilotQuota || 300);
        if (isNaN(quota) || quota <= 0)
            quota = 300;

        env += "WIDGET_COPILOT_QUOTA=" + root.shellQuote(quota) + " ";
        return env + root.scriptPath("get-ai-usage") + " --provider " + root.shellQuote(ids.join(","));
    }

    function applySnapshot(text) {
        var snapshot;
        try {
            snapshot = JSON.parse(text);
        } catch (_) {
            root.errorMsg = i18n("usage backend unavailable");
            root.stale = root.lastUpdate !== "";
            return;
        }
        var providers = snapshot.providers || [];
        root.rawProviders = providers;
        root.localSpend = snapshot.localSpend || ({});
        var active = root.enabledTabs[root.activeTab] || "";
        var activeSeen = false;
        var activeError = "";
        // Assign the map once: QML `property var` only emits a change signal on
        // assignment, never when a key is set in place.
        var windows = {};
        for (var key in root.providerChartWindows)
            windows[key] = root.providerChartWindows[key];

        for (var i = 0; i < providers.length; i++) {
            var provider = providers[i] || {};
            windows[provider.id] = provider.chartWindows || [];
            if (provider.id === active) {
                activeSeen = true;
                activeError = provider.error || "";
            }
        }
        root.providerChartWindows = windows;
        for (var j = 0; j < providers.length; j++)
            root.applyProvider(providers[j] || {});
        root.recordHistoryValues(UsageHistory.collect(providers));
        root.updateCountdowns();
        if (!activeSeen)
            return;

        root.errorMsg = activeError;
        if (activeError === "") {
            root.stale = false;
            root.lastUpdate = Qt.formatTime(new Date(), "hh:mm");
            offlineRetryTimer.stop();
            return;
        }
        root.stale = root.lastUpdate !== "";
        // The backend emits these as stable English tokens (the wire contract is
        // not localized); only the displayed string is translated, by tr().
        if (activeError === "offline") {
            offlineRetryTimer.restart();
        } else if (activeError === "rate limited") {
            root.backoffMs = 300000;
            backoffTimer.interval = root.backoffMs;
            backoffTimer.restart();
        }
    }

    function applyProvider(provider) {
        var details = provider.details || {};
        // Reassigned, not patched: a `property var` only notifies on assignment.
        var statuses = Object.assign({}, root.providerStatus);
        statuses[provider.id] = details.status || root.emptyStatus();
        root.providerStatus = statuses;
        if (provider.id === "claude")
            root.applyClaude(details);
        else if (provider.id === "openai")
            root.applyOpenAi(details);
        else if (provider.id === "antigravity")
            root.applyAntigravity(details);
        else if (provider.id === "kiro")
            root.applyKiro(details);
        else if (provider.id === "mistral")
            root.applyMistral(details, provider.error || "");
        else if (provider.id === "openrouter")
            root.applyOpenRouter(details, provider.error || "");
        else if (provider.id === "ollama")
            root.applyOllama(provider);
        else if (provider.id === "selfhosted")
            root.selfhostedProvider = provider;
        else if (provider.id === "grok")
            root.applyGrok(details, provider.error || "");
        else if (provider.id === "zai")
            root.applyZai(details, provider.error || "");
        else if (provider.id === "copilot")
            root.applyCopilot(details, provider.error || "");
        else if (provider.id === "deepseek")
            root.applyDeepSeek(details, provider.error || "");
        else if (provider.id === "kimi")
            root.applyKimi(details, provider.error || "");
        else if (provider.id === "muse")
            root.applyMuse(details, provider.error || "");
        else if (provider.id === "cursor")
            root.applyCursor(details, provider.error || "");
        else if (provider.id === "cline")
            root.applyCline(details, provider.error || "");
    }

    function applyClaude(d) {
        root.claudeHasOAuth = d.hasOAuth === true;
        root.claudeHasAdminKey = d.hasAdminKey === true;
        root.claudeSubscriptionType = d.subscriptionType || "";
        root.claudeRateLimitTier = d.rateLimitTier || "";
        root.claudeOrganizationUuid = d.organizationUuid || "";
        root.claudeEffortLevel = d.effortLevel || "";
        root.claudeAutoDream = d.autoDream === true;
        var session = d.session || {};
        var weekly = d.weekly || {};
        root.sessionAvailable = session.available === true;
        root.sessionPct = session.pct || 0;
        root.sessionTokensUsed = session.tokensUsed || 0;
        root.sessionTokenLimit = session.tokenLimit || 0;
        root.sessionResetDate = root.dateFromEpoch(session.resetAt);
        root.sessionResetTime = root.sessionResetDate ? Qt.formatTime(root.sessionResetDate, "hh:mm") : "";
        root.weeklyAvailable = weekly.available === true;
        root.weeklyPct = weekly.pct || 0;
        root.weeklyTokensUsed = weekly.tokensUsed || 0;
        root.weeklyTokenLimit = weekly.tokenLimit || 0;
        root.weeklyResetDate = root.dateFromEpoch(weekly.resetAt);
        root.weeklyResetTime = root.weeklyResetDate ? Qt.formatDateTime(root.weeklyResetDate, "MMM d, hh:mm") : "";
        root.claudeExtraTokens = d.extraTokens || 0;
        var extra = d.extraUsage || {};
        root.claudeExtraUsageEnabled = extra.enabled === true;
        root.claudeExtraUsageLimit = extra.limit || 0;
        root.claudeExtraUsageUsed = extra.used || 0;
        root.claudeExtraUsagePct = extra.pct || 0;
        root.claudeExtraUsageCurrency = extra.currency || "USD";
        var org = d.organizationUsage || {};
        root.claudeModels = org.models || ({});
        root.claudeTotalInputTokens = org.totalInputTokens || 0;
        root.claudeTotalOutputTokens = org.totalOutputTokens || 0;
        root.claudeTotalCostUSD = org.totalCostUSD || 0;
        var stats = d.stats || {};
        root.claudeStatsAvailable = stats.available === true;
        root.claudeStatsVersion = stats.version || 0;
        root.claudeStatsTotalMessages = stats.totalMessages || 0;
        root.claudeStatsTotalSessions = stats.totalSessions || 0;
        root.claudeStatsTotalTokens = stats.totalTokens || 0;
        root.claudeStatsTotalCostUSD = stats.totalCostUSD || 0;
        root.claudeStatsTotalToolCalls = stats.totalToolCalls || 0;
        root.claudeStatsTotalWebSearches = stats.totalWebSearches || 0;
        root.claudeStatsFavoriteModel = stats.favoriteModel || "";
        root.claudeStatsFirstDate = stats.firstDate || "";
        root.claudeStatsComputedDate = stats.computedDate || "";
        root.claudeStatsActiveDays = stats.activeDays || 0;
        root.claudeStatsSpanDays = stats.spanDays || 0;
        root.claudeStatsCurrentStreak = stats.currentStreak || 0;
        root.claudeStatsLongestStreak = stats.longestStreak || 0;
        root.claudeStatsLongestSessionMs = stats.longestSessionMs || 0;
        root.claudeStatsLongestSessionMessages = stats.longestSessionMessages || 0;
        root.claudeStatsPeakHour = stats.peakHour === undefined ? -1 : stats.peakHour;
        root.claudeStatsModels = stats.models || ({});
        root.claudeStatsDailyTokens = stats.dailyTokens || [];
        root.ensureAvailableChartWindow("claude");
    }

    function applyOpenAi(d) {
        root.openaiHasApiKey = d.hasApiKey === true;
        root.openaiCodexLoggedIn = d.codexLoggedIn === true;
        root.openaiEmail = d.email || "";
        root.openaiPlanType = d.planType || "";
        root.openaiOrgId = d.orgId || "";
        root.openaiAccountId = d.accountId || "";
        root.openaiAuthMode = d.authMode || "";
        var codex = d.codex || {};
        var session = codex.session || {};
        var weekly = codex.weekly || {};
        root.codexSessionAvailable = session.available === true;
        root.codexSessionPct = session.pct || 0;
        root.codexSessionResetDate = root.dateFromEpoch(session.resetAt);
        root.codexWeeklyAvailable = weekly.available === true;
        root.codexWeeklyPct = weekly.pct || 0;
        root.codexWeeklyResetDate = root.dateFromEpoch(weekly.resetAt);
        root.codexUsageAvailable = codex.available === true;
        root.codexLimitReached = codex.limitReached === true;
        var additional = codex.additional || [];
        var limits = [];
        for (var i = 0; i < additional.length; i++) {
            var entry = additional[i] || {};
            var entrySession = entry.session || {};
            var entryWeekly = entry.weekly || {};
            limits.push({
                "name": entry.name || "",
                "session": {
                    "available": entrySession.available === true,
                    "pct": entrySession.pct || 0,
                    "reset": root.dateFromEpoch(entrySession.resetAt)
                },
                "weekly": {
                    "available": entryWeekly.available === true,
                    "pct": entryWeekly.pct || 0,
                    "reset": root.dateFromEpoch(entryWeekly.resetAt)
                },
                "limit_reached": entry.limitReached === true
            });
        }
        root.codexAdditionalLimits = limits;
        var org = d.organizationUsage || {};
        root.openaiModels = org.models || ({});
        root.openaiTotalInputTokens = org.totalInputTokens || 0;
        root.openaiTotalOutputTokens = org.totalOutputTokens || 0;
        root.openaiTotalCostUSD = org.totalCostUSD || 0;
        var stats = d.stats || {};
        root.codexStatsAvailable = stats.available === true;
        root.codexStatsTotalSessions = stats.totalSessions || 0;
        root.codexStatsTotalMessages = stats.totalMessages || 0;
        root.codexStatsTotalTokens = stats.totalTokens || 0;
        root.codexStatsTotalToolCalls = stats.totalToolCalls || 0;
        root.codexStatsFirstDate = stats.firstDate || "";
        root.codexStatsComputedDate = stats.computedDate || "";
        root.codexStatsActiveDays = stats.activeDays || 0;
        root.codexStatsSpanDays = stats.spanDays || 0;
        root.codexStatsCurrentStreak = stats.currentStreak || 0;
        root.codexStatsLongestStreak = stats.longestStreak || 0;
        root.codexStatsLongestSessionMs = stats.longestSessionMs || 0;
        root.codexStatsLongestSessionMessages = stats.longestSessionMessages || 0;
        root.codexStatsPeakHour = stats.peakHour === undefined ? -1 : stats.peakHour;
        root.codexStatsFavoriteModel = stats.favoriteModel || "";
        root.codexStatsModels = stats.models || ({});
        root.codexStatsDailyTokens = stats.dailyTokens || [];
        root.codexStatsTotalCostUSD = stats.totalCostUSD || 0;
        root.codexModel = stats.model || "";
        root.codexEffortLevel = stats.effortLevel || "";
        root.ensureAvailableChartWindow("openai");
    }

    function applyAntigravity(d) {
        root.antigravityEmail = d.email || "";
        root.antigravityPlanType = d.planType || "";
        root.antigravityPromptCreditsMonthly = d.promptCreditsMonthly || 0;
        root.antigravityPromptCreditsAvailable = d.promptCreditsAvailable || 0;
        root.antigravityPct = d.pct || 0;
        root.antigravityGooglePct = d.googlePct || 0;
        root.antigravityExternalPct = d.externalPct || 0;
        root.antigravityModels = d.models || ({});
        root.antigravityResetDate = root.dateFromEpoch(d.resetAt);
        root.antigravityResetTime = root.antigravityResetDate ? Qt.formatDateTime(root.antigravityResetDate, "MMM d, hh:mm") : "";
        // Build locally and assign once: QML `property var` only emits a change
        // signal on assignment, never on in-place push().
        var groups = d.groups || [];
        var out = [];
        for (var i = 0; i < groups.length; i++) {
            var group = groups[i] || {};
            var resetDate = root.dateFromEpoch(group.resetAt);
            out.push({
                "key": group.key || "",
                "label": group.label || "",
                "usedPct": group.usedPct || 0,
                "resetDate": resetDate,
                "resetTime": resetDate ? Qt.formatDateTime(resetDate, "MMM d, hh:mm") : "",
                "isExhausted": group.isExhausted === true,
                "models": group.models || []
            });
        }
        root.antigravityGroups = out;
    }

    function applyKiro(d) {
        root.kiroUsageAvailable = d.available === true;
        root.kiroPlanType = d.planType || "";
        root.kiroDisplayName = d.displayName || i18n("Credit");
        root.kiroDisplayNamePlural = d.displayNamePlural || i18n("Credits");
        root.kiroCurrentUsage = d.currentUsage || 0;
        root.kiroUsageLimit = d.usageLimit || 0;
        root.kiroPct = d.pct || 0;
        root.kiroRemaining = d.remaining || 0;
        root.kiroCurrentOverages = d.currentOverages || 0;
        root.kiroOverageCap = d.overageCap || 0;
        root.kiroOverageCharges = d.overageCharges || 0;
        root.kiroOverageRate = d.overageRate || 0;
        root.kiroCurrencyCode = d.currencyCode || "USD";
        root.kiroCurrencySymbol = d.currencySymbol || "$";
        root.kiroResetDate = root.dateFromEpoch(d.resetAt);
        root.kiroResetTime = root.kiroResetDate ? Qt.formatDateTime(root.kiroResetDate, "MMM d, hh:mm") : "";
        root.kiroSource = d.source || "";
    }

    function applyMistral(d, error) {
        root.mistralHasKey = d.hasKey === true;
        root.mistralKeyValid = d.keyValid === true;
        root.mistralAvailableModels = d.availableModels || [];
        root.mistralError = error;
        var vibe = d.vibe || {};
        root.mistralVibeSessionCount = vibe.sessionCount || 0;
        root.mistralVibeTotalCost = vibe.totalCost || 0;
        root.mistralVibeTotalTokens = vibe.totalTokens || 0;
        root.mistralVibePromptTokens = vibe.promptTokens || 0;
        root.mistralVibeCompletionTokens = vibe.completionTokens || 0;
        root.mistralVibeTotalSteps = vibe.totalSteps || 0;
        root.mistralVibeToolOk = vibe.toolOk || 0;
        root.mistralVibeToolFail = vibe.toolFail || 0;
        root.mistralVibeActiveModel = vibe.activeModel || "";
        root.mistralVibeRecent = vibe.recent || [];
    }

    function applyOpenRouter(d, error) {
        root.openrouterHasKey = d.hasKey === true;
        root.openrouterKeyValid = d.keyValid === true;
        root.openrouterLabel = d.label || "";
        root.openrouterUsageUSD = d.usageUSD || 0;
        root.openrouterLimitUSD = d.limitUSD === undefined ? null : d.limitUSD;
        root.openrouterLimitRemainingUSD = d.limitRemainingUSD === undefined ? null : d.limitRemainingUSD;
        root.openrouterIsFreeTier = d.isFreeTier === true;
        root.openrouterRateLimit = d.rateLimit || ({});
        root.openrouterError = error;
    }

    function applyOllama(provider) {
        var d = provider.details || {};
        root.ollamaWindows = provider.quotaWindows || [];
        root.ollamaModels = d.models || ({});
        root.ollamaActivityCost = d.activityCost || "";
        root.ollamaError = provider.error || "";
        root.ollamaPct = provider.summary ? (provider.summary.pct || 0) : 0;
    }

    function applyGrok(d, error) {
        root.grokHasKey = d.hasKey === true;
        root.grokLoggedIn = d.loggedIn === true;
        root.grokPct = d.pct || 0;
        root.grokUsed = d.used || 0;
        root.grokMonthlyLimit = d.monthlyLimit || 0;
        root.grokEmail = d.email || "";
        root.grokTeamName = d.teamName || "";
        root.grokTierId = d.tierId || "";
        root.grokBillingPeriodEnd = d.billingPeriodEnd || "";
        root.grokSessionCount = d.sessionCount || 0;
        root.grokTotalTokens = d.totalTokens || 0;
        root.grokTotalToolCalls = d.totalToolCalls || 0;
        root.grokHasBilling = d.hasBilling === true;
        root.grokQuotaKind = d.quotaKind || "";
        root.grokQuotaWindow = d.quotaWindow || "";
        root.grokQuotaExhausted = d.quotaExhausted === true;
        root.grokError = d.billingError || error;
    }

    function applyZai(d, error) {
        root.zaiHasKey = d.hasKey === true;
        root.zaiKeyValid = d.keyValid === true;
        root.zaiLevel = d.level || "";
        var token = d.token || {};
        var tools = d.tools || {};
        root.zaiTokenPct = token.pct || 0;
        root.zaiTokenUsed = token.used === undefined ? null : token.used;
        root.zaiTokenLimit = token.limit === undefined ? null : token.limit;
        root.zaiTokenResetDate = root.dateFromEpoch(token.resetAt);
        root.zaiToolsPct = tools.pct || 0;
        root.zaiToolsRemaining = tools.remaining === undefined ? null : tools.remaining;
        root.zaiToolsResetDate = root.dateFromEpoch(tools.resetAt);
        root.zaiModels = d.models || [];
        root.zaiError = error;
    }

    function applyCopilot(d, error) {
        root.copilotHasKey = d.hasKey === true;
        root.copilotKeyValid = d.keyValid === true;
        root.copilotUsername = d.username || "";
        root.copilotUsed = d.used || 0;
        root.copilotQuota = d.quota === undefined ? (Plasmoid.configuration.copilotQuota || 300) : d.quota;
        root.copilotPct = d.pct || 0;
        root.copilotResetDate = root.dateFromEpoch(d.resetAt);
        root.copilotUnlimited = d.unlimited === true;
        root.copilotPlan = d.plan || "";
        root.copilotError = error;
        var cstats = d.stats || {};
        root.copilotStatsAvailable = cstats.available === true;
        root.copilotStatsTotalSessions = cstats.totalSessions || 0;
        root.copilotStatsTotalMessages = cstats.totalMessages || 0;
        root.copilotStatsTotalToolCalls = cstats.totalToolCalls || 0;
        root.copilotStatsTotalFiles = cstats.totalFiles || 0;
        root.copilotStatsTotalRepositories = cstats.totalRepositories || 0;
        root.copilotStatsTopRepositories = cstats.topRepositories || [];
        root.copilotStatsFirstDate = cstats.firstDate || "";
        root.copilotStatsActiveDays = cstats.activeDays || 0;
        root.copilotStatsSpanDays = cstats.spanDays || 0;
        root.copilotStatsCurrentStreak = cstats.currentStreak || 0;
        root.copilotStatsLongestStreak = cstats.longestStreak || 0;
        root.copilotStatsLongestSessionMs = cstats.longestSessionMs || 0;
        root.copilotStatsLongestSessionMessages = cstats.longestSessionMessages || 0;
        root.copilotStatsPeakHour = cstats.peakHour === undefined ? -1 : cstats.peakHour;
        root.copilotStatsDailyMessages = cstats.dailySeries || [];
    }

    function applyDeepSeek(d, error) {
        root.deepseekHasKey = d.hasKey === true;
        root.deepseekKeyValid = d.keyValid === true;
        root.deepseekIsAvailable = d.isAvailable === true;
        root.deepseekBalances = d.balances || [];
        root.deepseekPrimaryCurrency = d.primaryCurrency || "";
        root.deepseekPrimaryTotal = d.primaryTotal || 0;
        root.deepseekPrimaryGranted = d.primaryGranted || 0;
        root.deepseekPrimaryToppedUp = d.primaryToppedUp || 0;
        root.deepseekError = error;
    }

    function applyKimi(d, error) {
        root.kimiHasKey = d.hasKey === true;
        root.kimiKeyValid = d.keyValid === true;
        root.kimiAvailableBalance = d.availableBalance || 0;
        root.kimiVoucherBalance = d.voucherBalance || 0;
        root.kimiCashBalance = d.cashBalance || 0;
        root.kimiError = error;
        var plan = d.codePlan || {};
        root.kimiPlanAvailable = plan.available === true;
        root.kimiPlanExhausted = plan.exhausted === true;
        root.kimiPlanMessage = plan.message || "";
        root.kimiPlanError = plan.error || "";
        root.kimiPlanWindows = plan.windows || [];
        root.kimiBooster = plan.booster || null;
        var pct = root.kimiPlanExhausted && root.kimiPlanWindows.length === 0 ? 100 : 0;
        for (var i = 0; i < root.kimiPlanWindows.length; i++)
            pct = Math.max(pct, root.kimiPlanWindows[i].pct || 0);
        root.kimiPlanPct = pct;
    }

    function applyCursor(d, error) {
        root.cursorLoggedIn = d.loggedIn === true;
        root.cursorAvailable = error === "";
        root.cursorSource = d.source || "";
        root.cursorPlanName = d.planName || "";
        root.cursorTotalPct = d.totalPct || 0;
        root.cursorAutoPct = d.autoPct || 0;
        root.cursorApiPct = d.apiPct || 0;
        root.cursorHasSplit = d.hasSplit === true;
        root.cursorIncludedSpend = d.includedSpend || 0;
        root.cursorLimit = d.limit || 0;
        root.cursorOnDemandUsed = d.onDemandUsed || 0;
        root.cursorOnDemandLimit = d.onDemandLimit || 0;
        root.cursorResetDate = root.dateFromEpoch(d.resetAt);
        root.cursorResetTime = root.cursorResetDate ? Qt.formatDateTime(root.cursorResetDate, "MMM d, hh:mm") : "";
        root.cursorError = error;
        root.cursorStats = d.stats || ({});
    }

    function applyCline(d, error) {
        root.clineStats = d.stats || ({});
        root.clinePeriods = d.periods || [];
        root.clineError = error;
    }

    function applyMuse(d, error) {
        root.museHasLogin = d.hasLogin === true;
        root.museEmail = d.email || "";
        root.museFullName = d.fullName || "";
        root.museError = error;
        var current = d.current || {};
        var weekly = d.weekly || {};
        root.museQuotaError = d.quotaError || "";
        root.museCurrentAvailable = current.available === true;
        root.museCurrentPct = current.pct || 0;
        root.museCurrentResetDate = root.dateFromEpoch(current.resetAt);
        root.museWeeklyAvailable = weekly.available === true;
        root.museWeeklyPct = weekly.pct || 0;
        root.museWeeklyResetDate = root.dateFromEpoch(weekly.resetAt);
        var stats = d.stats || {};
        root.museModel = stats.model || "";
        root.museTotalTokens = stats.totalTokens || 0;
        root.museInputTokens = stats.totalInputTokens || 0;
        root.museOutputTokens = stats.totalOutputTokens || 0;
        root.museCostUSD = stats.totalCostUSD || 0;
        root.museCurrency = stats.currency || "USD";
        root.museModelCalls = stats.totalModelCalls || 0;
        root.museStatsTotalSessions = stats.totalSessions || 0;
        root.museStatsSubagentSessions = stats.subagentSessions || 0;
        root.museStatsTotalMessages = stats.totalMessages || 0;
        root.museStatsTotalToolCalls = stats.totalToolCalls || 0;
        root.museStatsActiveDays = stats.activeDays || 0;
        root.museStatsSpanDays = stats.spanDays || 0;
        root.museStatsCurrentStreak = stats.currentStreak || 0;
        root.museStatsLongestStreak = stats.longestStreak || 0;
        root.museStatsLongestSessionMs = stats.longestSessionMs || 0;
        root.museStatsLongestSessionMessages = stats.longestSessionMessages || 0;
        root.museStatsPeakHour = stats.peakHour === undefined ? -1 : stats.peakHour;
        root.museStatsFirstDate = stats.firstDate || "";
        root.museStatsModels = stats.models || ({});
        root.museStatsDailyTokens = stats.dailySeries || [];
        root.museStatsTopWorkspaces = stats.topWorkspaces || [];
    }

    function refresh() {
        if (!root.providerDefaultsReady || root.providerDefaultsInitializing)
            return;
        if (root.enabledTabs.length === 0)
            return;

        if (root.backoffMs > 0)
            return;

        if (root.activeTab >= root.enabledTabs.length)
            root.activeTab = 0;

        // The active tab plus every pinned service: those are the only providers
        // whose data is on screen, so those are the only ones worth fetching.
        // Overview and Spend are the exception — they total every provider, so
        // an unpinned setup would otherwise leave them refreshing nothing.
        var ids = [];
        var active = root.enabledTabs[root.activeTab] || "";
        if (active !== "" && !FeatureTabs.isFeatureTab(active))
            ids.push(active);
        else if (active === "overview" || active === "spend") {
            for (var p = 0; p < root.providers.length; p++) {
                var id = root.providers[p].id;
                if (root.enabledTabs.indexOf(id) >= 0 && ids.indexOf(id) < 0)
                    ids.push(id);
            }
        }

        var pins = root.pinnedTabs;
        for (var i = 0; i < pins.length; i++) {
            if (ids.indexOf(pins[i]) < 0)
                ids.push(pins[i]);
        }
        // The panel shows a provider even while a feature tab is open; fetch
        // it too, or the panel stays blank.
        if (root.panelTab !== "" && ids.indexOf(root.panelTab) < 0)
            ids.push(root.panelTab);
        if (ids.length === 0)
            return;

        var cmd = root.backendCommand(ids);
        usageSource.disconnectSource(cmd);
        usageSource.connectSource(cmd);
    }

    function refreshPricing() {
        if (root.pricingLoading)
            return;
        root.pricingLoading = true;
        var cmd = root.pythonEnv() + root.scriptPath("get-ai-usage") + " --refresh-pricing";
        pricingSource.disconnectSource(cmd);
        pricingSource.connectSource(cmd);
    }

    Plasmoid.backgroundHints: root.backgroundHints
    toolTipMainText: i18n("AI API Usage")
    toolTipSubText: {
        var lines = [];
        var tab = root.enabledTabs[root.activeTab];
        if (tab === "claude") {
            var fCountdown = root.sessionCountdown === "resetting..." ? " · " + i18n("resetting...") : (root.sessionCountdown ? " (" + root.sessionCountdown + ")" : "");
            var sCountdown = root.weeklyCountdown === "resetting..." ? " · " + i18n("resetting...") : (root.weeklyCountdown ? " (" + root.weeklyCountdown + ")" : "");
            if (root.sessionAvailable) {
                lines.push(i18n("Claude 5H: %1%", Math.round(root.sessionPct)) + fCountdown);
                if (root.sessionTokenLimit > 0)
                    lines.push("  " + i18n("%1 / %2 tokens", root.formatTokens(root.sessionTokensUsed), root.formatTokens(root.sessionTokenLimit)));
            }

            if (root.weeklyAvailable)
                lines.push(i18n("Claude 7D: %1%", Math.round(root.weeklyPct)) + sCountdown);
            if (root.claudeExtraTokens > 0)
                lines.push(i18n("Extra budget: %1 tokens left", root.formatTokens(root.claudeExtraTokens)));

            if (root.claudeExtraUsageEnabled && root.claudeExtraUsageLimit > 0)
                lines.push(i18n("Extra usage: %1 / %2 %3", root.claudeExtraUsageUsed.toFixed(2), root.claudeExtraUsageLimit.toFixed(2), root.claudeExtraUsageCurrency));

            if (root.claudeTotalCostUSD > 0)
                lines.push(i18n("API Cost (30d): $%1", root.claudeTotalCostUSD.toFixed(2)));
        } else if (tab === "antigravity") {
            lines.push(i18n("Gemini: %1%", Math.round(root.antigravityPct)));
            if (root.antigravityPlanType)
                lines.push(i18n("Plan: %1", root.antigravityPlanType));

            if (root.antigravityPromptCreditsMonthly > 0)
                lines.push(i18n("Credits: %1 / %2", root.antigravityPromptCreditsAvailable, root.antigravityPromptCreditsMonthly));

            if (root.antigravityResetTime)
                lines.push(i18n("Resets: %1", root.antigravityResetTime));
        } else if (tab === "openai") {
            if (root.openaiHasApiKey)
                lines.push(i18n("API usage: configured"));

            if (root.openaiTotalCostUSD > 0)
                lines.push(i18n("API cost (30d): $%1", root.openaiTotalCostUSD.toFixed(2)));

            if (root.openaiCodexLoggedIn)
                lines.push((root.openaiEmail ? i18n("Codex: signed in as %1", root.openaiEmail) : i18n("Codex: signed in")));

            if (root.codexSessionAvailable)
                lines.push(i18n("Codex 5H left: %1%", Math.round(100 - root.codexSessionPct)) + (root.codexSessionCountdown ? " (" + i18n("resets in %1", root.codexSessionCountdown) + ")" : ""));

            if (root.codexWeeklyAvailable)
                lines.push(i18n("Codex weekly left: %1%", Math.round(100 - root.codexWeeklyPct)) + (root.codexWeeklyCountdown ? " (" + i18n("resets in %1", root.codexWeeklyCountdown) + ")" : ""));
            if (root.openaiPlanType)
                lines.push(i18n("Plan: %1", root.openaiPlanType));

            if (root.openaiCodexLoggedIn && !root.openaiHasApiKey)
                lines.push(i18n("API usage needs an OpenAI API key"));
        } else if (tab === "kiro") {
            if (root.kiroPlanType)
                lines.push(i18n("Plan: %1", root.kiroPlanType.toUpperCase()));

            if (root.kiroUsageLimit > 0)
                lines.push(i18n("Credits: %1 / %2", root.kiroCurrentUsage.toFixed(2), root.kiroUsageLimit.toFixed(0)));

            if (root.kiroResetTime)
                lines.push(i18n("Resets: %1", root.kiroResetTime) + (root.kiroCountdown ? " (" + root.kiroCountdown + ")" : ""));

            if (root.kiroCurrentOverages > 0 || root.kiroOverageCharges > 0)
                lines.push(i18n("Overage: %1", root.kiroCurrencySymbol + root.kiroOverageCharges.toFixed(2)));
        } else if (tab === "mistral") {
            if (root.mistralKeyValid)
                lines.push(i18n("API key: configured"));

            if (root.mistralAvailableModels.length > 0)
                lines.push(i18np("%1 model available", "%1 models available", root.mistralAvailableModels.length));

            if (root.mistralError)
                lines.push("⚠ " + root.errorText(root.mistralError));
        } else if (tab === "openrouter") {
            if (root.openrouterLabel)
                lines.push(root.openrouterLabel);

            if (root.openrouterUsageUSD > 0)
                lines.push(i18n("Spent: $%1", root.openrouterUsageUSD.toFixed(4)));

            if (root.openrouterLimitUSD !== null)
                lines.push(i18n("Limit: $%1", root.openrouterLimitUSD.toFixed(2)));

            if (root.openrouterIsFreeTier)
                lines.push(i18n("Free tier"));
        } else if (tab === "grok") {
            lines.push(root.grokHasBilling ? (i18n("Grok credits: %1% used", Math.round(root.grokPct))) : i18n("Grok CLI connected; billing quota unavailable"));
            if (root.grokTeamName || root.grokEmail)
                lines.push(root.grokTeamName || root.grokEmail);

            if (root.grokBillingPeriodEnd)
                lines.push(i18n("Resets: %1", root.grokBillingPeriodEnd));

            lines.push(i18np("%1 local CLI session", "%1 local CLI sessions", root.grokSessionCount));
            if (root.grokError)
                lines.push("⚠ " + root.errorText(root.grokError));
        } else if (tab === "zai") {
            lines.push(i18n("Z.AI tokens: %1%", Math.round(root.zaiTokenPct)) + (root.zaiTokenCountdown ? " (" + root.zaiTokenCountdown + ")" : ""));
            if (root.zaiTokenUsed !== null && root.zaiTokenLimit !== null && root.zaiTokenLimit > 0)
                lines.push(i18n("%1 / %2 tokens", root.formatTokens(root.zaiTokenUsed), root.formatTokens(root.zaiTokenLimit)));

            lines.push(i18n("Tools: %1%", Math.round(root.zaiToolsPct)) + (root.zaiToolsCountdown ? " (" + root.zaiToolsCountdown + ")" : ""));
            if (root.zaiToolsRemaining > 0)
                lines.push(i18n("Tools left: %1", root.zaiToolsRemaining));

            if (root.zaiLevel)
                lines.push(i18n("Level: %1", root.zaiLevel));

            if (root.zaiModels.length > 0)
                lines.push(i18np("%1 model available", "%1 models available", root.zaiModels.length));

            if (root.zaiError)
                lines.push("⚠ " + root.errorText(root.zaiError));
        } else if (tab === "copilot") {
            lines.push(i18n("Copilot: %1%", Math.round(root.copilotPct)) + (root.copilotCountdown ? " (" + root.copilotCountdown + ")" : ""));
            if (root.copilotQuota > 0)
                lines.push(i18n("%1 / %2 requests", root.copilotUsed, root.copilotQuota));

            if (root.copilotUsername)
                lines.push(root.copilotUsername);

            if (root.copilotError)
                lines.push("⚠ " + root.errorText(root.copilotError));
        } else if (tab === "deepseek") {
            if (root.deepseekKeyValid) {
                lines.push(i18n("Balance: %1", root.formatMoney(root.deepseekPrimaryTotal, root.deepseekPrimaryCurrency)));
                lines.push(root.deepseekIsAvailable ? i18n("Available for API calls") : i18n("Balance unavailable"));
            }
            if (root.deepseekError)
                lines.push("⚠ " + root.errorText(root.deepseekError));
        } else if (tab === "kimi") {
            for (var k = 0; k < root.kimiPlanWindows.length; k++)
                lines.push(root.kimiWindowLabel(root.kimiPlanWindows[k]) + ": " + Math.round(root.kimiPlanWindows[k].pct) + "%");

            if (root.kimiPlanExhausted)
                lines.push(i18n("Kimi Code: %1", root.kimiPlanMessageText()));

            if (root.kimiKeyValid)
                lines.push(i18n("Moonshot balance: %1", root.formatMoney(root.kimiAvailableBalance, "USD")));

            if (root.kimiError)
                lines.push("⚠ " + root.errorText(root.kimiError));
        } else if (tab === "cursor") {
            if (root.cursorPlanName)
                lines.push(i18n("Plan: %1", root.cursorPlanName));

            if (root.cursorAvailable)
                lines.push(i18n("Included usage: %1%", Math.round(root.cursorTotalPct)));

            if (root.cursorHasSplit)
                lines.push(i18n("Auto: %1%", Math.round(root.cursorAutoPct)) + " · " + i18n("API: %1%", Math.round(root.cursorApiPct)));

            if (root.cursorResetTime)
                lines.push(i18n("Resets: %1", root.cursorResetTime) + (root.cursorCountdown ? " (" + root.cursorCountdown + ")" : ""));

            if (root.cursorError)
                lines.push("⚠ " + root.errorText(root.cursorError));
        } else if (tab === "cline") {
            if (root.clineStats.available === true) {
                lines.push(i18n("Tokens: %1 (all time)", root.formatTokens(root.clineStats.totalTokens || 0)));
                lines.push(i18n("Sessions: %1", Math.round(root.clineStats.totalSessions || 0)));
                if ((root.clineStats.totalCostUSD || 0) > 0)
                    lines.push(i18n("Spend: %1", root.formatMoney(root.clineStats.totalCostUSD, "USD")));
            }

            if (root.clineError)
                lines.push("⚠ " + root.errorText(root.clineError));
        } else if (tab === "muse") {
            lines.push("Muse" + (root.museModel ? " · " + root.museModel : ""));
            if (root.museCurrentAvailable)
                lines.push(i18n("Current: %1%", Math.round(root.museCurrentPct)) + (root.museCurrentCountdown ? " (" + root.museCurrentCountdown + ")" : ""));
            if (root.museWeeklyAvailable)
                lines.push(i18n("Weekly: %1%", Math.round(root.museWeeklyPct)));
            if (root.museTotalTokens > 0)
                lines.push(i18n("%1 tokens", root.formatTokens(root.museTotalTokens)) + " · " + i18np("%1 session", "%1 sessions", root.museStatsTotalSessions));
            if (root.museCostUSD > 0)
                lines.push(i18n("Spend (est.): %1", root.formatMoney(root.museCostUSD, root.museCurrency)));
            if (root.museError)
                lines.push("⚠ " + root.errorText(root.museError));
        }
        if (root.errorMsg !== "")
            lines.push("⚠ " + root.errorText(root.errorMsg));
        else if (root.lastUpdate !== "")
            lines.push((root.stale ? i18n("Updated %1 (stale)", root.lastUpdate) : i18n("Updated %1", root.lastUpdate)));
        return lines.join("\n");
    }
    onChartWindowChanged: {
        root.chartTimeOffset = 0;
    }
    // Plasma fills in the stored settings after startup, one key at a time, so
    // the tab is re-resolved as they arrive. While the popup is open, enabling
    // or disabling a provider shifts the indices; stay on the tab in view.
    readonly property string savedTab: Plasmoid.configuration.lastTab || ""
    onSavedTabChanged: {
        if (!root.expanded)
            root.restoreTab();
    }
    onEnabledTabsChanged: {
        var idx = root.expanded ? root.enabledTabs.indexOf(root.savedTab) : -1;
        if (idx >= 0)
            root.activeTab = idx;
        else
            root.restoreTab();
    }
    onActiveTabChanged: {
        // Map the remembered granularity (5h/24h/7d) onto the new tab so the
        // selected time range carries across services. Single-window tabs just
        // show their one window without disturbing the remembered granularity.
        var tab = root.enabledTabs[root.activeTab] || "";
        var win = root._windowForTab(tab, root.chartGranularity);
        if (root.chartWindow !== win) {
            root.chartWindow = win;
            Plasmoid.configuration.chartWindow = win;
        }
        if (tab !== "" && !FeatureTabs.isFeatureTab(tab))
            root.lastProviderId = tab;
        // Only a tab picked in the open popup is remembered; the startup
        // restore runs before the stored value has loaded.
        if (root.expanded && tab !== "" && root.savedTab !== tab)
            Plasmoid.configuration.lastTab = tab;
        root.chartTimeOffset = 0;
        // A rate limit belongs to the provider that hit it; don't let it keep
        // the tab you just switched to empty.
        root.backoffMs = 0;
        backoffTimer.stop();
    }
    // With one pin, open the popup on that service. With multiple pins, leave the
    // current popup tab alone so the pin list only controls the panel contents.
    onExpandedChanged: {
        if (root.expanded && root.pinnedTabs.length === 1) {
            var idx = root.enabledTabs.indexOf(root.pinnedTabs[0]);
            if (idx >= 0 && idx !== root.activeTab) {
                root.activeTab = idx;
                root.errorMsg = "";
                root.refresh();
            }
        }
    }
    Component.onDestruction: root.flushHistoryConfig()
    Component.onCompleted: {
        root.loadUsageHistory();
        root.normalizePanelRotation();
        root.restoreTab();
        root.initializeProviderDefaults();
    }

    Plasma5Support.DataSource {
        id: exportSaveSource

        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
        }
    }
    // ── History export / import ─────────────────────────────────────────────────

    Plasma5Support.DataSource {
        id: historyIOSource

        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
            // The operation is encoded as the last word of the command.
            // `autosave` and `seed` differ only in the precedence history-io
            // merges them with, and are answered the same way here.
            var op = src.indexOf(" autosave") >= 0 || src.indexOf(" seed") >= 0 ? "save" : src.indexOf(" autoload") >= 0 ? "autoload" : src.indexOf(" export") >= 0 ? "export" : "import";
            var out = (data["stdout"] || "").trim();
            try {
                var res = JSON.parse(out);
                if (res.error) {
                    // autosave/autoload are background ops — stay silent on their errors
                    if (op === "import" || op === "export")
                        root.historyIOMsg = "⚠ " + res.error;
                    // A save that could not merge wrote nothing, so its batch is
                    // still this widget's to retry.
                    if (op === "save")
                        root.failHistorySave();
                    // A failed autoload still has to release the mirror, or the
                    // widget would never write its history to disk again.
                    if (op === "autoload")
                        root.releaseHistoryMirror();

                    return;
                }
                if (op === "save") {
                    // The merged file comes back, so the other frontend's points
                    // arrive without a separate read. The degraded write answers
                    // {"ok":true} with no series, leaving nothing to adopt.
                    root.finishHistorySave(res.data);
                    return;
                }
                if (res.path) {
                    root.historyIOMsg = i18n("Exported to %1", res.path);
                    return;
                }
                if (op === "autoload") {
                    // The file wins for everything it knows; the config's own
                    // points survive either way and go back through the seed
                    // lane. A no-op on a fresh install, where there is no file.
                    UsageHistory.adopt(root.historyStore, res.data);
                    root.syncUsageHistory();
                    root.releaseHistoryMirror();
                    return;
                }
                if (res.data) {
                    // array of {t,s,w} (or legacy {t,v})
                    var imported = UsageHistory.normalize(res.data, root.historyLimit);
                    // A snapshot, not a reading: restore() puts it under the
                    // running series and into the seed lane, so the file keeps
                    // its own values for anything it already has.
                    UsageHistory.restore(root.historyStore, imported);
                    root.syncUsageHistory();
                    root.saveHistory();
                    // An explicit Import is worth persisting straight away.
                    root.flushHistoryConfig();
                    // Only the manual Import button announces a count; autoload is silent.
                    if (op === "import")
                        root.historyIOMsg = i18n("Imported %1 points", imported.length);
                }
            } catch (e) {
                if (op === "save")
                    root.failHistorySave();

                if (op === "autoload")
                    root.releaseHistoryMirror();

                if (op === "import" || op === "export")
                    root.historyIOMsg = i18n("⚠ history I/O failed");
            }
        }
    }

    ColorDialog {
        id: colorDialog

        title: colorTarget === "popup" ? i18n("Choose Popup Background Color") : i18n("Choose Card Background Color")
        onAccepted: {
            var hex = selectedColor.toString().substring(0, 7);
            if (hex.charAt(0) !== '#')
                hex = '#' + hex;
            // standard hex validation
            if (colorTarget === "popup") {
                Plasmoid.configuration.popupBgColor = hex;
                root.popupBgColor = hex;
            } else {
                Plasmoid.configuration.cardBgColor = hex;
                root.cardBgColor = hex;
            }
        }
    }

    // ── Provider data ────────────────────────────────────────────────────────
    // One source for every provider: the shared backend already returns the
    // active tab's and every pinned service's data in a single document.
    Plasma5Support.DataSource {
        id: usageSource

        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
            root.applySnapshot((data["stdout"] || "").trim());
        }
    }

    Plasma5Support.DataSource {
        id: providerDefaultsSource

        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
            // Latch only on a real answer: a missing python3 or a broken
            // backend keeps the shipped defaults and retries next start.
            try {
                var result = JSON.parse((data["stdout"] || "").trim());
                if (result.ok === true && Array.isArray(result.data)) {
                    root.applyDetectedProviders(result.data);
                    Plasmoid.configuration.providerDefaultsApplied = true;
                }
            } catch (e) {}
            root.providerDefaultsInitializing = false;
            root.providerDefaultsReady = true;
            root.refresh();
        }
    }

    Plasma5Support.DataSource {
        id: providerRedetectSource

        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
            var result = null;
            try {
                result = JSON.parse((data["stdout"] || "").trim());
            } catch (e) {}
            root.applyProviderRedetect(result);
        }
    }

    Plasma5Support.DataSource {
        id: pricingSource

        engine: "executable"
        connectedSources: []
        onNewData: function (src, data) {
            disconnectSource(src);
            root.pricingLoading = false;
            var stdout = (data && data.stdout) ? data.stdout.trim() : "";
            try {
                var result = JSON.parse(stdout);
                root.pricingStatus = result.status || (result.ok === true ? "refreshed" : "no-cache");
                root.pricingError = result.error || "";
                if (result.ok === true)
                    root.refresh();
            } catch (e) {
                root.pricingStatus = "no-cache";
                root.pricingError = i18n("Could not refresh pricing.");
            }
        }
    }

    Timer {
        interval: Math.max(30, root.pollIntervalSec) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateCountdowns()
    }

    Timer {
        id: backoffTimer

        interval: 300000
        running: false
        repeat: false
        onTriggered: {
            root.backoffMs = 0;
            root.errorMsg = "";
            root.refresh();
        }
    }

    Timer {
        id: offlineRetryTimer

        interval: 60000
        running: false
        repeat: true
        onTriggered: root.refresh()
    }

    // ── Compact (panel) ───────────────────────────────────────────────────────
    compactRepresentation: Item {
        id: compactRoot

        implicitWidth: compactRow.implicitWidth + 18
        implicitHeight: Kirigami.Units.iconSizes.medium
        Layout.preferredWidth: implicitWidth
        Layout.minimumWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumHeight: implicitHeight

        MouseArea {
            id: compactMouse

            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
            hoverEnabled: true

            Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, 8)
                color: compactMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }
        }

        Timer {
            id: panelRotationTimer

            interval: root.panelRotationIntervalSec * 1000
            running: root.panelRotationEnabled && !root.expanded
            repeat: true
            onIntervalChanged: if (running)
                restart()
            onTriggered: root.rotatePanelProvider()
        }

        RowLayout {
            id: compactRow

            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                visible: root.errorMsg !== ""
                implicitWidth: 6
                implicitHeight: 6
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: root.dangerColor
                Layout.alignment: Qt.AlignVCenter

                SequentialAnimation on opacity {
                    running: root.errorMsg !== ""
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 0.3
                        duration: 800
                        easing.type: Easing.InOutSine
                    }

                    NumberAnimation {
                        to: 1
                        duration: 800
                        easing.type: Easing.InOutSine
                    }
                }
            }

            PanelSlot {
                pct: root.sessionPct
                iconColor: root.sessionColor
                iconSource: Qt.resolvedUrl("../icons/claude-color.svg")
                iconText: "C"
                stale: root.stale && root.panelShows("claude")
                visible: root.panelShows("claude") && root.sessionAvailable
                tooltipText: i18n("Claude 5-hour: %1%", Math.round(root.sessionPct)) + (root.sessionTokenLimit > 0 ? "\n" + root.formatTokens(root.sessionTokensUsed) + " / " + root.formatTokens(root.sessionTokenLimit) : "")
            }

            Rectangle {
                visible: root.panelShows("claude") && root.sessionAvailable && root.weeklyAvailable
                implicitWidth: 1
                implicitHeight: 14
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: Qt.rgba(1, 1, 1, 0.16)
                Layout.alignment: Qt.AlignVCenter
            }

            PanelSlot {
                pct: root.weeklyPct
                iconColor: root.weeklyColor
                iconSource: Qt.resolvedUrl("../icons/claude-color.svg")
                iconTint: root.weeklyColor
                iconText: i18n("7D")
                stale: root.stale && root.panelShows("claude")
                visible: root.panelShows("claude") && root.weeklyAvailable
                tooltipText: i18n("Claude 7-day: %1%", Math.round(root.weeklyPct)) + (root.weeklyTokenLimit > 0 ? "\n" + root.formatTokens(root.weeklyTokensUsed) + " / " + root.formatTokens(root.weeklyTokenLimit) : "")
            }

            PanelSlot {
                pct: root.antigravityGooglePct
                iconColor: root.googleBlue
                iconSource: Qt.resolvedUrl("../icons/antigravity-color.svg")
                iconText: "G"
                stale: root.stale && root.panelShows("antigravity")
                visible: root.panelShows("antigravity")
                tooltipText: i18n("Gemini (Google) quota: %1%", Math.round(root.antigravityGooglePct)) + (root.antigravityPlanType ? "\n" + i18n("Plan: %1", root.antigravityPlanType) : "") + (root.antigravityEmail ? "\n" + root.antigravityEmail : "")
            }

            Rectangle {
                visible: root.panelShows("antigravity")
                implicitWidth: 1
                implicitHeight: 14
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: Qt.rgba(1, 1, 1, 0.16)
                Layout.alignment: Qt.AlignVCenter
            }

            PanelSlot {
                pct: root.antigravityExternalPct
                iconColor: root.googleGreen
                iconSource: Qt.resolvedUrl("../icons/antigravity-color.svg")
                iconTint: root.googleGreen
                iconText: "X"
                stale: root.stale && root.panelShows("antigravity")
                visible: root.panelShows("antigravity")
                tooltipText: i18n("External models quota: %1%", Math.round(root.antigravityExternalPct)) + (root.antigravityPlanType ? "\n" + i18n("Plan: %1", root.antigravityPlanType) : "") + (root.antigravityEmail ? "\n" + root.antigravityEmail : "")
            }

            PanelSlot {
                // Preserve the existing API-cost fallback when no plan limit is available.
                pct: root.codexSessionAvailable ? root.codexSessionPct : (root.openaiTotalCostUSD > 0 ? Math.min(100, (root.openaiTotalCostUSD / 10) * 100) : 0)
                iconColor: root.openaiGreen
                iconSource: Qt.resolvedUrl("../icons/openai.svg")
                iconText: "C"
                stale: root.stale && root.panelShows("openai")
                visible: root.panelShows("openai") && (root.codexSessionAvailable || !root.codexUsageAvailable)
                showCost: !root.codexUsageAvailable
                costText: root.openaiTotalCostUSD > 0 ? "$" + root.openaiTotalCostUSD.toFixed(2) : (root.openaiHasApiKey ? "API" : (root.openaiCodexLoggedIn ? "Codex" : "—"))
                tooltipText: "OpenAI" + (root.codexSessionAvailable ? "\n" + i18n("Codex 5h: %1% left", Math.round(100 - root.codexSessionPct)) : "") + (root.codexWeeklyAvailable ? "\n" + i18n("Codex weekly: %1% left", Math.round(100 - root.codexWeeklyPct)) : "") + (root.openaiHasApiKey ? "\n" + i18n("API usage configured") + "\n" + i18n("Cost (30d): $%1", root.openaiTotalCostUSD.toFixed(2)) + "\n" + i18n("In: %1", root.formatTokens(root.openaiTotalInputTokens)) + "  " + i18n("Out: %1", root.formatTokens(root.openaiTotalOutputTokens)) : i18n("\nAPI usage needs an OpenAI API key")) + (root.openaiCodexLoggedIn ? i18n("\nCodex signed in") + (root.openaiEmail ? ": " + root.openaiEmail : "") : "")
            }

            Rectangle {
                visible: root.panelShows("openai") && root.codexSessionAvailable && root.codexWeeklyAvailable
                implicitWidth: 1
                implicitHeight: 14
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: Qt.rgba(1, 1, 1, 0.16)
                Layout.alignment: Qt.AlignVCenter
            }

            PanelSlot {
                pct: root.codexWeeklyPct
                iconColor: root.openaiGreen
                iconSource: Qt.resolvedUrl("../icons/openai.svg")
                iconTint: root.weeklyColor
                iconText: i18n("7D")
                stale: root.stale && root.panelShows("openai")
                visible: root.panelShows("openai") && root.codexWeeklyAvailable
                showCost: false
                tooltipText: i18n("OpenAI Codex weekly: %1% left", Math.round(100 - root.codexWeeklyPct))
            }

            PanelSlot {
                pct: root.kiroPct
                iconColor: root.kiroPurple
                iconSource: Qt.resolvedUrl("../icons/kiro.svg")
                iconText: "K"
                stale: root.stale && root.panelShows("kiro")
                visible: root.panelShows("kiro")
                showCost: !root.kiroUsageAvailable
                costText: root.kiroUsageAvailable ? "" : "—"
                tooltipText: "Kiro" + (root.kiroPlanType ? "\n" + i18n("Plan: %1", root.kiroPlanType.toUpperCase()) : "") + (root.kiroUsageLimit > 0 ? "\n" + i18n("Credits: %1 / %2", root.kiroCurrentUsage.toFixed(2), root.kiroUsageLimit.toFixed(0)) : "") + (root.kiroResetTime ? "\n" + i18n("Resets: %1", root.kiroResetTime) : "")
            }

            PanelSlot {
                pct: 0
                iconColor: root.mistralOrange
                iconSource: Qt.resolvedUrl("../icons/mistral-color.svg")
                iconText: "M"
                stale: root.stale && root.panelShows("mistral")
                visible: root.panelShows("mistral")
                showCost: true
                costText: root.mistralVibeTotalCost > 0 ? "$" + root.mistralVibeTotalCost.toFixed(2) : (root.mistralKeyValid ? i18n("✓ key") : "—")
                tooltipText: "Mistral AI" + (root.mistralKeyValid ? i18n("\nAPI key configured") : i18n("\nNo key set")) + (root.mistralVibeTotalCost > 0 ? "\n" + i18n("Spend (vibe): $%1", root.mistralVibeTotalCost.toFixed(4)) : "") + (root.mistralAvailableModels.length > 0 ? "\n" + i18np("%1 model", "%1 models", root.mistralAvailableModels.length) : "")
            }

            PanelSlot {
                pct: root.openrouterLimitUSD !== null && root.openrouterLimitUSD > 0 ? Math.min(100, (root.openrouterUsageUSD / root.openrouterLimitUSD) * 100) : 0
                iconColor: root.openrouterPurple
                iconSource: Qt.resolvedUrl("../icons/openrouter.svg")
                iconText: "OR"
                stale: root.stale && root.panelShows("openrouter")
                visible: root.panelShows("openrouter") && !root.showSettings
                showCost: true
                costText: root.openrouterKeyValid ? (root.openrouterUsageUSD > 0 ? "$" + root.openrouterUsageUSD.toFixed(3) : i18n("✓ key")) : "—"
                tooltipText: "OpenRouter" + (root.openrouterLabel ? "\n" + root.openrouterLabel : "") + (root.openrouterUsageUSD > 0 ? "\n" + i18n("Used: $%1", root.openrouterUsageUSD.toFixed(4)) : "") + (root.openrouterLimitUSD !== null ? "\n" + i18n("Limit: $%1", root.openrouterLimitUSD.toFixed(2)) : "")
            }

            PanelSlot {
                pct: root.ollamaPct
                iconColor: "#f0f0f0"
                iconSource: Qt.resolvedUrl("../icons/ollama.svg")
                iconText: "OL"
                stale: root.stale && root.panelShows("ollama")
                visible: root.panelShows("ollama") && !root.showSettings
                showCost: root.ollamaWindows.length === 0
                costText: "—"
                tooltipText: "Ollama Cloud" + (root.ollamaWindows.length > 0 ? "\n" + root.ollamaWindows[0].label + ": " + Math.round(root.ollamaPct) + "%" : "\n" + root.ollamaError)
            }

            Rectangle {
                visible: root.panelShows("ollama") && root.ollamaWindows.length > 0 && root.ollamaWindows[0].key === "ollama_session" && root.ollamaWeeklyWindow !== null
                implicitWidth: 1
                implicitHeight: 14
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                color: Qt.rgba(1, 1, 1, 0.16)
                Layout.alignment: Qt.AlignVCenter
            }

            PanelSlot {
                pct: root.ollamaWeeklyWindow ? root.ollamaWeeklyWindow.pct : 0
                iconColor: "#f0f0f0"
                iconTint: root.weeklyColor
                iconSource: Qt.resolvedUrl("../icons/ollama.svg")
                iconText: i18n("7D")
                stale: root.stale && root.panelShows("ollama")
                visible: root.panelShows("ollama") && root.ollamaWindows.length > 0 && root.ollamaWindows[0].key === "ollama_session" && root.ollamaWeeklyWindow !== null
                tooltipText: "Ollama Cloud\n" + (root.ollamaWeeklyWindow ? root.ollamaWeeklyWindow.label + ": " + Math.round(root.ollamaWeeklyWindow.pct) + "%" : "")
            }

            PanelSlot {
                pct: root.selfhostedProvider.summary ? (root.selfhostedProvider.summary.pct || 0) : 0
                iconColor: "#38bdf8"
                iconSource: Qt.resolvedUrl("../icons/local-models.svg")
                iconText: "LM"
                stale: root.stale && root.panelShows("selfhosted")
                visible: root.panelShows("selfhosted") && !root.showSettings
                showCost: !root.selfhostedProvider.summary || !root.selfhostedProvider.summary.hasChart
                costText: root.selfhostedProvider.summary ? root.selfhostedProvider.summary.text : "—"
                tooltipText: i18n("Local Models") + "\n" + (root.selfhostedProvider.error || (root.selfhostedProvider.summary ? root.selfhostedProvider.summary.text + " · " + root.selfhostedProvider.summary.detail : i18n("Checking…")))
            }

            PanelSlot {
                pct: root.grokPct
                iconColor: root.grokWhite
                iconSource: Qt.resolvedUrl("../icons/grok.svg")
                iconText: "G"
                stale: root.stale && root.panelShows("grok")
                visible: root.panelShows("grok") && !root.showSettings
                showCost: !root.grokHasBilling
                costText: root.grokHasBilling ? "" : "CLI"
                tooltipText: root.grokHasBilling ? (i18n("Grok credits: %1% used", Math.round(root.grokPct)) + (root.grokBillingPeriodEnd ? "\n" + i18n("Resets: %1", root.grokBillingPeriodEnd) : "")) : i18n("Grok CLI connected; billing quota is not exposed")
            }

            PanelSlot {
                pct: root.zaiTokenPct
                iconColor: root.zaiBlue
                iconSource: Qt.resolvedUrl("../icons/zai.svg")
                iconText: "Z"
                stale: root.stale && root.panelShows("zai")
                visible: root.panelShows("zai")
                tooltipText: i18n("Z.AI tokens: %1%", Math.round(root.zaiTokenPct)) + (root.zaiTokenUsed !== null && root.zaiTokenLimit !== null && root.zaiTokenLimit > 0 ? "\n" + i18n("%1 / %2 tokens", root.formatTokens(root.zaiTokenUsed), root.formatTokens(root.zaiTokenLimit)) : "") + (root.zaiTokenCountdown ? "\n" + i18n("Token reset: %1", root.zaiTokenCountdown) : "") + "\n" + i18n("Tools: %1%", Math.round(root.zaiToolsPct)) + (root.zaiToolsRemaining > 0 ? "\n" + i18n("Tools left: %1", root.zaiToolsRemaining) : "")
            }

            PanelSlot {
                pct: root.copilotPct
                iconColor: root.copilotPurple
                iconSource: Qt.resolvedUrl("../icons/githubcopilot.svg")
                iconText: "CP"
                stale: root.stale && root.panelShows("copilot")
                visible: root.panelShows("copilot")
                tooltipText: i18n("Copilot: %1%", Math.round(root.copilotPct)) + (root.copilotQuota > 0 ? "\n" + i18n("%1 / %2 requests", root.copilotUsed, root.copilotQuota) : "") + (root.copilotCountdown ? "\n" + i18n("Resets: %1", root.copilotCountdown) : "") + (root.copilotUsername ? "\n" + root.copilotUsername : "")
            }

            PanelSlot {
                pct: 0
                iconColor: root.deepseekBlue
                iconSource: Qt.resolvedUrl("../icons/deepseek-color.svg")
                iconText: "DS"
                stale: root.stale && root.panelShows("deepseek")
                visible: root.panelShows("deepseek")
                showCost: true
                costText: root.deepseekKeyValid ? root.formatMoney(root.deepseekPrimaryTotal, root.deepseekPrimaryCurrency) : "—"
                tooltipText: "DeepSeek" + (root.deepseekKeyValid ? "\n" + i18n("Balance: %1", root.formatMoney(root.deepseekPrimaryTotal, root.deepseekPrimaryCurrency)) + "\n" + i18n("Granted: %1", root.formatMoney(root.deepseekPrimaryGranted, root.deepseekPrimaryCurrency)) + "\n" + i18n("Topped up: %1", root.formatMoney(root.deepseekPrimaryToppedUp, root.deepseekPrimaryCurrency)) : i18n("\nNo API key set"))
            }

            PanelSlot {
                // The Kimi Code plan is a percentage and wins the pill; the
                // Moonshot balance is the fallback for API-key-only setups.
                pct: root.kimiPlanAvailable ? root.kimiPlanPct : 0
                iconColor: root.kimiBlue
                iconSource: Qt.resolvedUrl("../icons/kimi.svg")
                iconText: "K"
                stale: root.stale && root.panelShows("kimi")
                visible: root.panelShows("kimi")
                showCost: !root.kimiPlanAvailable
                costText: root.kimiKeyValid ? root.formatMoney(root.kimiAvailableBalance, "USD") : "—"
                tooltipText: {
                    var t = root.kimiPlanAvailable ? "Kimi Code" : "Kimi / Moonshot";
                    for (var i = 0; i < root.kimiPlanWindows.length; i++)
                        t += "\n" + root.kimiWindowLabel(root.kimiPlanWindows[i]) + ": " + Math.round(root.kimiPlanWindows[i].pct) + "%";
                    if (root.kimiPlanExhausted)
                        t += "\n" + root.kimiPlanMessageText();
                    if (root.kimiKeyValid)
                        t += "\n" + i18n("Balance: %1", root.formatMoney(root.kimiAvailableBalance, "USD")) + "\n" + i18n("Voucher: %1", root.formatMoney(root.kimiVoucherBalance, "USD")) + "\n" + i18n("Cash: %1", root.formatMoney(root.kimiCashBalance, "USD"));
                    else if (!root.kimiPlanAvailable)
                        t += i18n("\nNo Moonshot API key or Kimi Code login");
                    return t;
                }
            }

            PanelSlot {
                // No quota to fill: the pill shows the last 30 days' tokens.
                pct: 0
                iconColor: root.clineWhite
                iconSource: Qt.resolvedUrl("../icons/cline.svg")
                iconText: "Cl"
                stale: root.stale && root.panelShows("cline")
                visible: root.panelShows("cline")
                showCost: true
                costText: root.clineStats.available === true ? root.formatTokens(root.clineMonthTokens) : "—"
                tooltipText: {
                    if (root.clineStats.available !== true)
                        return "Cline\n" + (root.clineError || i18n("No sessions yet"));
                    var t = "Cline";
                    for (var i = 0; i < root.clinePeriods.length; i++) {
                        var p = root.clinePeriods[i];
                        t += "\n" + root.clinePeriodLabel(p) + ": " + i18n("%1 tokens", root.formatTokens(p.tokens || 0)) + " · " + i18np("%1 session", "%1 sessions", p.sessions);
                    }
                    return t;
                }
            }

            PanelSlot {
                pct: root.cursorTotalPct
                iconColor: root.cursorWhite
                iconSource: Qt.resolvedUrl("../icons/cursor.svg")
                iconText: "Cu"
                stale: root.stale && root.panelShows("cursor")
                visible: root.panelShows("cursor")
                showCost: !root.cursorAvailable
                costText: root.cursorAvailable ? "" : "—"
                tooltipText: "Cursor" + (root.cursorPlanName ? "\n" + i18n("Plan: %1", root.cursorPlanName) : "") + (root.cursorAvailable ? "\n" + i18n("Included usage: %1%", Math.round(root.cursorTotalPct)) : "\n" + (root.cursorError || i18n("Not signed in"))) + (root.cursorResetTime ? "\n" + i18n("Resets: %1", root.cursorResetTime) : "")
            }

            PanelSlot {
                property var openCodeStats: {
                    var provider = root.rawProviderById("opencode");
                    return provider && provider.details ? (provider.details.stats || ({})) : ({});
                }
                pct: 0
                iconColor: "#B7B1B1"
                iconSource: Qt.resolvedUrl("../icons/opencode-color.svg")
                iconText: "OC"
                stale: root.stale && root.panelShows("opencode")
                visible: root.panelShows("opencode") && !root.showSettings
                showCost: true
                costText: openCodeStats.totalTokens > 0 ? root.formatTokens(openCodeStats.totalTokens) : "—"
                tooltipText: {
                    var sessions = Math.round(openCodeStats.totalSessions || 0);
                    var tokens = root.formatTokens(openCodeStats.totalTokens || 0);
                    return "OpenCode\n" + i18n("%1 tokens", tokens) + " · " + i18np("%1 session", "%1 sessions", sessions);
                }
            }

            PanelSlot {
                pct: root.museCurrentAvailable ? root.museCurrentPct : 0
                iconColor: root.museBlue
                iconSource: Qt.resolvedUrl("../icons/muse-color.svg")
                iconText: "Mu"
                stale: root.stale && root.panelShows("muse")
                visible: root.panelShows("muse")
                // With the billed quota off there is no percentage to fill, so
                // the pill carries the lifetime total instead of an empty bar.
                showCost: !root.museCurrentAvailable
                costText: root.museTotalTokens > 0 ? root.formatTokens(root.museTotalTokens) : "—"
                tooltipText: "Muse" + (root.museCurrentAvailable ? "\n" + i18n("Current: %1%", Math.round(root.museCurrentPct)) + (root.museCurrentCountdown ? " (" + root.museCurrentCountdown + ")" : "") : "") + (root.museWeeklyAvailable ? "\n" + i18n("Weekly: %1%", Math.round(root.museWeeklyPct)) : "") + (root.museModel ? "\n" + root.museModel : "") + (root.museTotalTokens > 0 ? "\n" + i18n("%1 tokens", root.formatTokens(root.museTotalTokens)) + " · " + i18np("%1 session", "%1 sessions", root.museStatsTotalSessions) : i18n("\nNo local sessions yet")) + (root.museCostUSD > 0 ? "\n" + i18n("Spend (est.): %1", root.formatMoney(root.museCostUSD, root.museCurrency)) : "")
            }
        }
    }

    // ── Popup ─────────────────────────────────────────────────────────────────
    fullRepresentation: Item {
        id: popupRoot

        readonly property int popupMargin: Kirigami.Units.largeSpacing + 4
        readonly property int targetHeight: Math.ceil(mainColumn.implicitHeight + popupMargin * 2)

        implicitWidth: Kirigami.Units.gridUnit * 26
        implicitHeight: targetHeight
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight

        // PlasmaCore.Dialog latches the popup to the largest size it has seen and
        // won't shrink back when a tab swap reduces mainColumn.implicitHeight — it
        // samples the size mid-transition (old, taller content still tearing down).
        // Nudge the binding one frame later so the dialog re-samples the smaller value.
        Connections {
            function onActiveTabChanged() {
                relayoutTimer.restart();
            }

            function onShowSettingsChanged() {
                relayoutTimer.restart();
            }

            // A settings section swap changes the panel's height the same way a
            // tab swap does, and the dialog needs the same nudge to shrink back.
            function onSettingsTabChanged() {
                relayoutTimer.restart();
            }

            target: root
        }

        Timer {
            id: relayoutTimer

            interval: 0
            onTriggered: {
                popupRoot.implicitHeight = 0;
                popupRoot.implicitHeight = Qt.binding(function () {
                    return popupRoot.targetHeight;
                });
            }
        }

        // ── Glassmorphism backdrop ──────────────────────────────────────────
        // A translucent tinted layer that lets Plasma's native popup blur show
        // through, plus a faint accent glow and inner highlight for the "glass" look.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -popupRoot.popupMargin
            radius: 12
            clip: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            // Custom background tint overlay (defaults to 0 opacity, i.e. invisible/glassy).
            // Sits under the accent glow / provider watermark so raising the opacity
            // tints the glass without blotting out the decoration on top of it.
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: root.resolvedPopupBg
                visible: root.popupBgOpacity > 0
            }

            // soft accent glow in the top-left, tinted by the active service accent
            Rectangle {
                width: parent.width * 0.7
                height: parent.height * 0.7
                anchors.top: parent.top
                anchors.left: parent.left
                radius: width / 2
                opacity: 0.12
                visible: root.popupDecoration === 0 || (root.popupDecoration === 1 && (providerWatermark.source === "" || providerWatermark.status === Image.Error))

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: root.tabColor(root.enabledTabs[root.activeTab] || "claude")
                    }

                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }

            Image {
                id: providerWatermark
                anchors.top: parent.top
                anchors.left: parent.left
                width: parent.width * 0.7
                height: parent.height * 0.7
                sourceSize.width: 280
                sourceSize.height: 280
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.12
                visible: root.popupDecoration === 1 && source !== "" && status !== Image.Error
                source: root.showSettings ? Qt.resolvedUrl("../icons/org.muddyblack.aiUsageWidget.svg") : root.tabIcon(root.enabledTabs[root.activeTab] || "claude")
            }

            // crisp inner top highlight line
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 1
                color: Qt.rgba(1, 1, 1, 0.18)
            }

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, 0.1)
                }

                GradientStop {
                    position: 0.5
                    color: Qt.rgba(1, 1, 1, 0.04)
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0.06)
                }
            }
        }

        ColumnLayout {
            id: mainColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: popupRoot.popupMargin
            anchors.rightMargin: popupRoot.popupMargin
            anchors.topMargin: popupRoot.popupMargin
            height: implicitHeight
            spacing: Kirigami.Units.largeSpacing

            // ── Header ──────────────────────────────────────────────────────
            RowLayout {
                id: headerRow

                Layout.fillWidth: true
                spacing: 8
                visible: !root._exportHideHeader

                Item {
                    implicitWidth: 22
                    implicitHeight: 22
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22

                    // Brand logo of the active provider, falling back to the
                    // tinted widget logo for providers without artwork.
                    Image {
                        visible: !root.showSettings && root.tabIcon(root.enabledTabs[root.activeTab] || "claude") !== "" && status !== Image.Error
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        sourceSize.width: 36
                        sourceSize.height: 36
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        source: root.tabIcon(root.enabledTabs[root.activeTab] || "claude")
                    }

                    Kirigami.Icon {
                        visible: !root.showSettings && root.tabIcon(root.enabledTabs[root.activeTab] || "claude") === ""
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: Qt.resolvedUrl("../icons/org.muddyblack.aiUsageWidget.svg")
                        isMask: true
                        color: root.tabColor(root.enabledTabs[root.activeTab] || "claude")
                    }

                    // Raw Images with Rainbow Gradient (shown when in Settings)
                    Image {
                        visible: root.showSettings
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        sourceSize.width: 22
                        sourceSize.height: 22
                        source: Qt.resolvedUrl("../icons/org.muddyblack.aiUsageWidget.svg")
                        opacity: 0.15
                    }

                    Image {
                        visible: root.showSettings
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        sourceSize.width: 18
                        sourceSize.height: 18
                        source: Qt.resolvedUrl("../icons/org.muddyblack.aiUsageWidget.svg")
                    }
                }

                ColumnLayout {
                    spacing: 0

                    PlasmaComponents.Label {
                        text: {
                            if (root.showSettings)
                                return i18n("Settings");

                            var tab = root.enabledTabs[root.activeTab];
                            if (tab === "claude")
                                return i18n("Claude Usage");

                            if (tab === "antigravity")
                                return i18n("Antigravity Usage");

                            if (tab === "openai")
                                return i18n("OpenAI Usage");

                            if (tab === "kiro")
                                return i18n("Kiro Usage");

                            if (tab === "mistral")
                                return i18n("Mistral Usage");

                            if (tab === "openrouter")
                                return i18n("OpenRouter Usage");

                            if (tab === "ollama")
                                return i18n("Ollama Cloud Usage");
                            if (tab === "selfhosted")
                                return i18n("Local Models");

                            if (tab === "grok")
                                return i18n("Grok Usage");

                            if (tab === "zai")
                                return i18n("Z.AI Usage");

                            if (tab === "copilot")
                                return i18n("Copilot Usage");

                            if (tab === "deepseek")
                                return i18n("DeepSeek Balance");

                            if (tab === "kimi")
                                return root.kimiPlanAvailable ? i18n("Kimi Usage") : i18n("Kimi Balance");

                            if (tab === "cursor")
                                return i18n("Cursor Usage");

                            if (tab === "cline")
                                return i18n("Cline Stats");

                            if (tab === "opencode")
                                return i18n("OpenCode Usage");

                            return i18n("AI Usage Monitor");
                        }
                        font.bold: true
                        font.pixelSize: 15
                        color: Kirigami.Theme.textColor
                    }

                    PlasmaComponents.Label {
                        visible: root.showSettings || root.enabledTabs[root.activeTab] === "overview" || root.enabledTabs[root.activeTab] === "sessions" || root.enabledTabs[root.activeTab] === "spend"
                        text: {
                            if (root.showSettings) {
                                if (root.settingsTab === "panel")
                                    return i18n("Views, colors, chart and popup style");

                                if (root.settingsTab === "info")
                                    return i18n("About AI Usage Monitor and project links");

                                if (root.settingsTab === "data")
                                    return i18n("Refresh interval and usage history");

                                if (root.settingsTab === "advanced")
                                    return i18n("Python interpreter and terminal tool");

                                return i18n("Turn providers on and set their keys");
                            }
                            var tab = root.enabledTabs[root.activeTab];
                            if (tab === "overview") {
                                var count = 0;
                                for (var i = 0; i < (root.enabledTabs || []).length; i++) {
                                    var tid = root.enabledTabs[i];
                                    if (tid !== "overview" && tid !== "spend" && tid !== "sessions")
                                        count++;
                                }
                                return i18np("%1 provider", "%1 providers", count);
                            }
                            if (tab === "sessions")
                                return sessionsTabView.loading ? i18n("Refreshing…") : i18np("%1 local session", "%1 local sessions", sessionsTabView.sessionsTotal || 0);
                            if (tab === "spend") {
                                // Provider/API total: metered spend and plan-inclusive spend
                                return spendTabView ? spendTabView.summaryText : "";
                            }
                            return "";
                        }
                        font.pixelSize: 10
                        opacity: 0.5
                        color: Kirigami.Theme.textColor

                        MouseArea {
                            id: subtitleMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        QQC2.ToolTip.visible: subtitleMouseArea.containsMouse && root.enabledTabs[root.activeTab] === "spend" && spendTabView && spendTabView.summaryTooltip !== ""
                        QQC2.ToolTip.delay: 300
                        QQC2.ToolTip.text: spendTabView ? spendTabView.summaryTooltip : ""
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // ── Export button ─────────────────────────────────────────
                PlasmaComponents.ToolButton {
                    id: exportBtn

                    icon.name: "document-save"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    visible: !root.showSettings
                    opacity: hovered ? 1 : 0.6
                    QQC2.ToolTip.visible: hovered && !exportMenu.visible
                    QQC2.ToolTip.delay: 400
                    QQC2.ToolTip.text: i18n("Export current tab as PNG or SVG")
                    onClicked: exportMenu.popup()

                    QQC2.Menu {
                        id: exportMenu

                        QQC2.MenuItem {
                            text: i18n("Export as PNG")
                            icon.name: "image-x-generic"
                            onTriggered: root.doExportSnapshot(mainColumn, "png")
                        }

                        QQC2.MenuItem {
                            text: i18n("Export as SVG")
                            icon.name: "image-svg+xml"
                            onTriggered: root.doExportSnapshot(mainColumn, "svg")
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }

                PlasmaComponents.ToolButton {
                    icon.name: root.showSettings ? "arrow-left" : "configure"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    onClicked: root.showSettings = !root.showSettings
                    opacity: hovered ? 1 : (root.showSettings ? 1 : 0.6)

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    // Sessions come from a separate backend call, so root.refresh()
                    // alone leaves the list untouched while it is on screen.
                    onClicked: {
                        root.refresh();
                        if (sessionsTabView.visible)
                            sessionsTabView.refresh();
                    }
                    opacity: hovered ? 1 : 0.6

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            // ── Tab bar ──────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.enabledTabs.length > 1 && !root.showSettings

                Repeater {
                    model: root.enabledTabs

                    Rectangle {
                        id: tabPillItem
                        Layout.fillWidth: true
                        implicitHeight: 32
                        Layout.preferredHeight: 32
                        radius: 6
                        clip: true
                        color: root.activeTab === index ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        border.width: 1
                        border.color: root.activeTab === index ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.08)

                        MouseArea {
                            id: tabMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // Only needed when the pill collapsed to icon-only.
                            QQC2.ToolTip.visible: containsMouse && !tabContent.labelFits
                            QQC2.ToolTip.text: root.tabName(modelData)
                            QQC2.ToolTip.delay: 400
                            onClicked: function (mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    if (!FeatureTabs.isFeatureTab(modelData))
                                        root.togglePin(modelData);
                                    return;
                                }
                                root.activeTab = index;
                                root.errorMsg = "";
                                root.refresh();
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: tabPillItem.radius
                                color: parent.containsMouse && root.activeTab !== index ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            }
                        }

                        RowLayout {
                            id: tabContent

                            // Centred as before, but width-capped so the content can
                            // never spill past the pill onto its neighbours.
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 14)
                            spacing: 5
                            // Below this the pill drops the label and goes icon-only,
                            // so many enabled providers still fit.
                            readonly property bool labelFits: parent.width > 62

                            Image {
                                Layout.preferredWidth: 13
                                Layout.preferredHeight: 13
                                Layout.alignment: Qt.AlignVCenter
                                sourceSize.width: 26
                                sourceSize.height: 26
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                source: root.tabIcon(modelData)
                                visible: root.tabIcon(modelData) !== "" && status !== Image.Error
                                opacity: root.activeTab === index ? 1 : 0.5
                            }

                            // Fallback for providers that have no logo yet.
                            Rectangle {
                                Layout.preferredWidth: 8
                                Layout.preferredHeight: 8
                                Layout.alignment: Qt.AlignVCenter
                                radius: 4
                                color: root.tabColor(modelData)
                                opacity: root.activeTab === index ? 1 : 0.5
                                visible: root.tabIcon(modelData) === ""
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                visible: tabContent.labelFits
                                text: root.tabName(modelData)
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 12
                                font.bold: root.activeTab === index
                                color: Kirigami.Theme.textColor
                                opacity: root.activeTab === index ? 1 : 0.6
                            }
                        }

                        // Pin toggle — visible when pinned or on hover. Click to pin/unpin.
                        Kirigami.Icon {
                            id: pinIcon

                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 3
                            anchors.rightMargin: 3
                            width: 11
                            height: 11
                            source: "pin"
                            isMask: true
                            visible: !FeatureTabs.isFeatureTab(modelData) && (root.isPinned(modelData) || tabMouse.containsMouse || pinMouse.containsMouse)
                            color: root.isPinned(modelData) ? root.tabColor(modelData) : Kirigami.Theme.textColor
                            opacity: root.isPinned(modelData) ? 1 : 0.4

                            MouseArea {
                                id: pinMouse

                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePin(modelData)
                                QQC2.ToolTip.visible: containsMouse
                                QQC2.ToolTip.delay: 400
                                QQC2.ToolTip.text: root.isPinned(modelData) ? i18n("Unpin from panel") : i18n("Pin on panel")
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            SettingsPanel {
                rootItem: root
            }

            OverviewTab {
                rootItem: root
            }

            SpendTab {
                id: spendTabView
                rootItem: root
            }

            SessionsTab {
                id: sessionsTabView
                rootItem: root
            }

            ClaudeTab {
                rootItem: root
            }

            AntigravityTab {
                rootItem: root
            }

            OpenAiTab {
                rootItem: root
            }

            KiroTab {
                rootItem: root
            }

            MistralTab {
                rootItem: root
            }

            OpenRouterTab {
                rootItem: root
            }

            OllamaTab {
                rootItem: root
            }

            SelfhostedTab {
                rootItem: root
            }

            GrokTab {
                rootItem: root
            }

            ZaiTab {
                rootItem: root
            }

            CopilotTab {
                rootItem: root
            }

            DeepSeekTab {
                rootItem: root
            }

            KimiTab {
                rootItem: root
            }

            MuseTab {
                rootItem: root
            }

            CursorTab {
                rootItem: root
            }

            ClineTab {
                rootItem: root
            }

            OpenCodeTab {
                rootItem: root
            }

            UsageChart {
                rootItem: root
            }

            // ── Footer ─────────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: !root.showSettings

                Rectangle {
                    visible: root.errorMsg !== ""
                    implicitWidth: 6
                    implicitHeight: 6
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: root.dangerColor
                    Layout.alignment: Qt.AlignVCenter
                }

                PlasmaComponents.Label {
                    visible: root.errorMsg !== ""
                    text: root.errorText(root.errorMsg)
                    color: root.dangerColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }
                // Combined 30-day spend across paid API surfaces

                Rectangle {
                    visible: root.totalSpendUSD > 0
                    implicitHeight: 16
                    implicitWidth: spendLabel.implicitWidth + 14
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 6

                    PlasmaComponents.Label {
                        id: spendLabel

                        anchors.centerIn: parent
                        text: "Σ $" + root.totalSpendUSD.toFixed(2)
                        font.pixelSize: 9
                        font.bold: true
                        color: Kirigami.Theme.textColor
                        opacity: 0.8
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        QQC2.ToolTip.visible: containsMouse
                        QQC2.ToolTip.delay: 300
                        QQC2.ToolTip.text: {
                            var l = [i18n("Combined API spend")];
                            if (root.claudeTotalCostUSD > 0)
                                l.push(i18n("Claude (30d): $%1", root.claudeTotalCostUSD.toFixed(2)));

                            if (root.openaiTotalCostUSD > 0)
                                l.push(i18n("OpenAI (30d): $%1", root.openaiTotalCostUSD.toFixed(2)));

                            if (root.openrouterUsageUSD > 0)
                                l.push(i18n("OpenRouter (all-time): $%1", root.openrouterUsageUSD.toFixed(2)));

                            return l.join("\n");
                        }
                    }
                }

                PlasmaComponents.Label {
                    visible: root.lastUpdate !== "" && root.errorMsg === ""
                    text: (root.stale ? i18n("updated %1 · stale", root.lastUpdate) : i18n("updated %1", root.lastUpdate))
                    opacity: 0.45
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }
    }
}
