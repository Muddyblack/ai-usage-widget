#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
#
# Contract tests for the shared provider backend.
#
# Every case replays a recorded raw envelope through `get-ai-usage --normalize`,
# so the whole provider matrix — success, missing credentials, malformed
# responses, offline and rate-limited — is covered without touching the network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/package/contents/tools/sh/get-ai-usage"
FIXTURES="$ROOT/tests/fixtures"

failures=0
checks=0

# check <fixture> <description> <jq boolean expression over the provider object>
check() {
    local fixture="$1" description="$2" filter="$3" result
    checks=$((checks + 1))
    if ! result="$("$BACKEND" --normalize <"$FIXTURES/$fixture.json" 2>&1)"; then
        printf 'FAIL %s: backend errored\n%s\n' "$fixture" "$result" >&2
        failures=$((failures + 1))
        return
    fi
    if ! printf '%s' "$result" | jq -e "$filter" >/dev/null 2>&1; then
        printf 'FAIL %s: %s\n  got: %s\n' "$fixture" "$description" "$result" >&2
        failures=$((failures + 1))
    fi
}

# ── Envelope invariants every provider must satisfy ─────────────────────────

for fixture in "$FIXTURES"/*.json; do
    name="$(basename "$fixture" .json)"
    check "$name" "carries the full contract shape" '
        (has("id") and has("label") and has("accent") and has("ok") and has("stale")
         and has("error") and has("updatedAt") and has("summary") and has("quotaWindows")
         and has("chartWindows") and has("slots") and has("historyValues") and has("details"))
        and (.summary | has("pct") and has("text") and has("detail") and has("hasChart"))
        and (.quotaWindows | type) == "array"
        and (.historyValues | type) == "object"
        and (.error | type) == "string"'
    check "$name" "carries a status block" '
        (.details.status | (.indicator | type) == "string" and (.url | type) == "string"
         and (.components | type) == "array" and (.incidents | type) == "array")'
    # No credential may ever reach a frontend.
    check "$name" "never leaks a credential" '
        (tojson | test("secret|sk-ant-|sk-oauth|gh-secret|zai-secret|xai-secret|ds-secret|or-secret|codex-secret") | not)'
    check "$name" "reset timestamps are epoch seconds or 0" '
        [.quotaWindows[].resetAt] | all((type == "number") and (. == 0 or . > 1000000000))'
    check "$name" "chart windows are fully described" '
        .chartWindows | all(
            (.id | type) == "string" and (.key | type) == "string"
            and (.label | type) == "string" and (.size | type) == "number" and .size > 0
            and (.granularity | type) == "string"
            and (.raw | type) == "boolean" and (.resets | type) == "boolean"
            and (.periodMs | type) == "number" and (.resetAt | type) == "number"
            and (if .resets then .periodMs > 0 else .periodMs == 0 end))'
    check "$name" "charts only series the provider reports" '
        (.historyValues | keys) as $series
        | (.chartWindows | length) == 0 or ($series | length) == 0
          or ([.chartWindows[].key] | inside($series))'
done

# ── Claude ──────────────────────────────────────────────────────────────────

check claude-success "prefers semantic limits over legacy windows" '
    .ok and (.error == "")
    and .details.session.pct == 23 and .details.weekly.pct == 61
    and .details.session.tokensUsed == 120000 and .details.session.tokenLimit == 500000
    and .historyValues == {s: 23, w: 61}'
check claude-success "formats the session window for the panel" '
    (.quotaWindows[0] | .key == "session" and .available and .detail == "120000 / 500000 tokens")'
check claude-success "keeps a scoped week out of the account week" '
    .details.weekly.pct == 61
    and (.details.scopedWeekly | length) == 1
    and (.details.scopedWeekly[0] | .pct == 44 and .model == "" and .label == "7-day scoped")'
check claude-scoped-week "reads the account week and the per-model week apart" '
    .ok and .details.session.pct == 9 and .details.weekly.pct == 17
    and (.details.scopedWeekly | length) == 1
    and (.details.scopedWeekly[0] | .pct == 13 and .model == "Fable"
         and .key == "weekly_fable" and .label == "7-day Fable"
         and .resetAt == 1786949999)'
check claude-scoped-week "shows a scoped week that is not the binding limit" '
    (.quotaWindows | map(.key)) == ["session", "weekly", "weekly_fable"]
    and (.quotaWindows[2] | .available and .pct == 13 and .label == "7-day Fable")'
check claude-success "reports credential presence, not values" '
    .details.hasOAuth == true and .details.hasAdminKey == true
    and .details.subscriptionType == "max" and .details.organizationUuid == "org-1234"'
check claude-success "prices organization usage in one place" '
    .details.organizationUsage.totalInputTokens == 2005000
    and .details.organizationUsage.totalOutputTokens == 400500
    and (.details.organizationUsage.models["claude-sonnet-4"].priced == true)
    and (.details.organizationUsage.models["mystery-model"].priced == false)
    and ((.details.organizationUsage.totalCostUSD - 12) | fabs) < 0.001'
check claude-success "derives local activity statistics" '
    .details.stats.available
    and .details.stats.activeDays == 3
    and .details.stats.longestStreak == 3
    and .details.stats.totalToolCalls == 13
    and .details.stats.totalTokens == 165
    and .details.stats.favoriteModel == "claude-opus-4"
    and .details.stats.peakHour == 14
    and (.details.stats.dailyTokens | map(.date)) == ["2026-07-22", "2026-07-23"]
    and (.details.stats.dailyTokens[1].total) == 120'
check claude-success "offers 5H/24H/7D/30D when both windows exist" '
    (.chartWindows | map(.id)) == ["session", "day", "weekly", "monthly"]
    and (.chartWindows | map(.key)) == ["s", "s", "w", "w"]
    and (.chartWindows[0].granularity) == "5h"
    and (.chartWindows[2].size) == 604800000
    and (.chartWindows[3].size) == 2592000000
    and (.chartWindows[3].granularity) == "30d"'
check claude-success "anchors resets so a sleep gap can be redrawn" '
    (.chartWindows[0] | .periodMs == 18000000 and .resetAt == 1784473200)
    and (.chartWindows[1] | .size == 86400000 and .periodMs == 18000000)
    and (.chartWindows[2] | .periodMs == 604800000 and .resetAt == 1784991600)'
check claude-malformed "offers no chart ranges without windows" '
    (.chartWindows | length) == 0'
check claude-success "summarises the status page" '
    .details.status.indicator == "minor"
    and .details.status.components == ["API (degraded performance)"]
    and .details.status.incidents == ["Elevated errors"]
    and .details.status.latestUpdate == "We are looking into it."
    and .details.status.url == "https://status.claude.com"'
check copilot-github-status "scopes GitHub status to Copilot" '
    .details.status.indicator == "minor"
    and .details.status.description == "Copilot degraded"
    and .details.status.components == ["Copilot (degraded performance)"]
    and .details.status.incidents == ["Slow Copilot completions"]
    and .details.status.latestUpdate == "Completions are slower than usual."
    and .details.status.url == "https://www.githubstatus.com"'
check cline-gatus-status "reads a Gatus page by the latest check per endpoint" '
    .details.status.indicator == "major"
    and .details.status.components == ["Web App (down)"]
    and .details.status.url == "https://status.cline.bot"'
check mistral-missing "links a status page that has no feed" '
    .details.status.indicator == "" and .details.status.url == "https://status.mistral.ai"'
check zai-missing "has no status page" '
    .details.status.indicator == "" and .details.status.url == ""'
check claude-missing-credentials "reports a logged-out account" '
    (.ok | not) and .error == "Claude not logged in" and .stale
    and .historyValues == {} and (.details.hasOAuth | not)'
check claude-admin-key-only "keeps API stats usable without OAuth" '
    .ok and .error == "OAuth missing — API stats only" and .details.hasAdminKey'
check claude-offline "surfaces the offline state" '
    (.ok | not) and .error == "offline" and .stale'
check claude-rate-limited "surfaces the rate-limited state" '
    (.ok | not) and .error == "rate limited" and .stale'
check claude-malformed "treats an unknown body as no windows" '
    .ok and (.details.session.available | not) and (.details.weekly.available | not)
    and .historyValues == {}'

# ── OpenAI / Codex ──────────────────────────────────────────────────────────

check openai-codex-success "classifies app-server windows by duration" '
    .details.codex.available
    and .details.codex.session.pct == 58 and .details.codex.session.resetAt == 1785010000
    and .details.codex.weekly.pct == 30
    and .historyValues == {cp: 58, cw: 30}'
check openai-codex-success "keeps named per-model limits, minus the codex entry" '
    (.details.codex.additional | length) == 1
    and .details.codex.additional[0].name == "Spark"
    and .details.codex.additional[0].limitReached
    and .details.codex.additional[0].session.pct == 90
    and .details.codex.additional[0].weekly.pct == 9'
check openai-codex-success "prices organization completions" '
    .details.organizationUsage.totalInputTokens == 3001000
    and (.details.organizationUsage.models["gpt-4o"].priced == true)'
check openai-codex-success "carries Codex CLI statistics" '
    .details.stats.available and .details.stats.model == "gpt-5-codex"
    and .details.stats.effortLevel == "medium" and .details.stats.activeDays == 2
    and (.details.stats.dailyTokens | map(.date)) == ["2026-07-23", "2026-07-24"]'
check openai-codex-success "maps chart ranges onto the Codex series" '
    (.chartWindows | map(.id)) == ["codex_primary", "codex_day", "codex_weekly", "codex_monthly"]
    and (.chartWindows | map(.key)) == ["cp", "cp", "cw", "cw"]'
check openai-api-key-only "offers no chart ranges without plan windows" '
    (.chartWindows | length) == 0'
check openai-legacy-windows "classifies legacy windows even when reversed" '
    .details.codex.session.pct == 20 and .details.codex.weekly.pct == 70
    and (.details.codex.additional | length) == 1
    and .details.codex.additional[0].name == "GPT-5"
    and .details.codex.additional[0].session.pct == 100'
check openai-missing-credentials "reports a missing key and login" '
    (.ok | not) and .error == "OpenAI: no API key or Codex login"'
check openai-api-key-only "stays healthy with billing only" '
    .ok and .error == "" and (.details.codex.available | not)
    and .summary.hasChart == false
    and .details.organizationUsage.totalCostUSD > 0'
check openai-offline "marks a failed plan lookup stale, not fatal" '
    .ok and .stale and (.details.codex.available | not)'

# ── Antigravity ─────────────────────────────────────────────────────────────

check antigravity-success "averages quota per family" '
    .details.googlePct == 40 and .details.externalPct == 100
    and .details.pct == 60
    and (.details.groups | length) == 2
    and (.details.groups[0].key == "gemini")
    and (.details.groups[1].models == ["autocomplete-1", "claude-sonnet-4-5"])
    and .details.groups[1].isExhausted
    and .historyValues == {ag: 60, agg: 40, age: 100}'
check antigravity-success "charts 5h, 24h, 7d, 30d ranges" '
    (.chartWindows | map(.label)) == ["5H", "24H", "7D", "30D"]
    and (.chartWindows | all(.raw | not)) and (.chartWindows | all(.resets | not))'
check antigravity-success "keeps models without a quota out of the average" '
    (.details.models["autocomplete-1"].hasQuota | not)
    and .details.models["gemini-3-pro"].usedPct == 60'
check antigravity-not-running "shortens the not-running message" '
    (.ok | not) and .error == "Antigravity is not running in IDE"'
check antigravity-missing "reports an unconfigured provider" '
    (.ok | not) and .error == "Antigravity not configured"'

# ── Kiro ────────────────────────────────────────────────────────────────────

check kiro-success "exposes credits, overage and reset" '
    .ok and .details.pct == 25 and .details.currentUsage == 250
    and .details.overageCharges == 0.8 and .details.resetAt == 1785542400
    and .historyValues == {kr: 25}'
check kiro-missing "reports no local snapshot" '
    (.ok | not) and .error == "Kiro: no local usage data found"'
check kiro-error "passes the tool error through" '
    (.ok | not) and (.error | startswith("Kiro: No Kiro state found"))'
check kiro-success "labels an IDE snapshot as such" '.details.source == "ide"'
check kiro-cli-success "reads the live kiro-cli numbers" '
    .ok and .details.source == "cli" and .details.planType == "free"
    and .details.currentUsage == 0.13 and .details.usageLimit == 50
    and .details.resetAt == 1790812800 and .quotaWindows[0].detail == "0.13 / 50 credits"'

# ── Mistral ─────────────────────────────────────────────────────────────────

check mistral-success "marks the spend series as a raw money value" '
    (.chartWindows | length) == 4 and (.chartWindows | all(.raw)) and (.chartWindows | all(.resets | not))'
check deepseek-success "marks the balance series as a raw money value" '
    (.chartWindows | length) == 4 and (.chartWindows | all(.raw))'
check kiro-success "charts 5h, 24h, 7d, 30d ranges" '
    (.chartWindows | map(.label)) == ["5H", "24H", "7D", "30D"]
    and (.chartWindows | all(.raw | not)) and (.chartWindows | all(.resets | not))'
check mistral-success "aggregates vibe CLI spend" '
    .ok and .details.vibe.totalCost == 12.5 and .details.vibe.sessionCount == 4
    and .details.keyValid and .details.hasKey
    and (.details.availableModels | length) == 2
    and .historyValues == {mv: 12.5}'
check mistral-invalid-key "keeps local stats on an invalid key" '
    (.ok | not) and .error == "Invalid API key (401)"
    and .details.vibe.totalCost == 12.5'
check mistral-missing "reports an unconfigured key" '
    (.ok | not) and .error == "Mistral: no API key configured"'

# ── OpenRouter ──────────────────────────────────────────────────────────────

check openrouter-success "derives the credit percentage" '
    .ok and .details.usageUSD == 3.25 and .details.limitUSD == 10
    and .historyValues == {or: 32.5}
    and .quotaWindows[0].detail == "$3.25 / $10"'
check openrouter-unlimited "treats a null limit as unlimited" '
    .ok and .details.limitUSD == null and .summary.pct == 0
    and .historyValues == {}
    and (.quotaWindows[0].detail | endswith("unlimited"))'
check openrouter-missing "reports an unconfigured key" '
    (.ok | not) and .error == "OpenRouter: no API key configured"'

# ── Grok ────────────────────────────────────────────────────────────────────

check grok-billing "reports billing quota and local activity" '
    .ok and .details.hasBilling and .details.pct == 42
    and .summary.hasChart and .historyValues == {gr: 42}
    and (.quotaWindows | length) == 2
    and .quotaWindows[0].detail == "21 / 50"
    and .quotaWindows[1].detail == "1 session · 900 tokens · 4 tool calls"'
check grok-free-tier "hides the chart when there is no billing quota" '
    .ok and (.details.hasBilling | not) and .summary.text == "CLI"
    and (.summary.hasChart | not) and .historyValues == {} and (.chartWindows | length) == 0
    and .quotaWindows[1].detail == "3 sessions · 12000 tokens · 9 tool calls"'
check grok-missing "asks for a login" '
    (.ok | not) and (.error | test("grok --oauth"))'

# ── Z.AI ────────────────────────────────────────────────────────────────────

check zai-success "turns relative resets into absolute timestamps" '
    .ok and .details.hasKey and .details.token.pct == 25 and .details.token.resetAt == 1785003600
    and .details.tools.resetAt == 1785007200 and .details.tools.remaining == 60
    and .historyValues == {za: 25}
    and .quotaWindows[0].detail == "250 / 1000 tokens"'
# Live responses put an absolute millisecond epoch in nextResetTime, not a
# duration. Adding that to `now` once produced reset dates decades out, which
# the year-less formatting hid. Both shapes have to survive.
check zai-absolute-reset "keeps an absolute reset epoch instead of adding it to now" '
    .ok and .details.token.resetAt == 1785007200
    and .details.tools.resetAt == 1786000000
    and ([.quotaWindows[] | select(.key == "zai_tokens_long")] | first | .resetAt) == 1785086400'
check zai-absolute-reset "resets stay within a plausible horizon of now" '
    [.quotaWindows[].resetAt] | all(. == 0 or (. > 1785000000 and . < 1785000000 + 60 * 86400))'
# The monitor endpoints report consumption, not a share of a quota, so the
# row carries a value instead of a meter and is ruled off from the windows.
check zai-today "reports the service day total beside the quota windows" '
    .ok and .details.today.available
    and .details.today.tokens == 41175632 and .details.today.calls == 370
    and .details.today.date == "2026-08-11"
    and (.details.today.models | map(.name)) == ["GLM-5.2", "GLM-5-Turbo", "GLM-4.7"]'
check zai-today "renders the day total as a value, not a meter" '
    (.quotaWindows | map(.key)) == ["zai_tokens", "zai_tokens_long", "zai_tools", "zai_today"]
    and (.quotaWindows[3] | .detail == "41.18M tokens" and .note == "370 calls"
         and (.showMeter | not) and .resetAt == 1786485600)'
# The reset column shows the date this rolls over TO, so the label has to name
# the day being summed — otherwise the row reads as being about tomorrow.
check zai-today "names the day it is summing" '
    (.quotaWindows[3].label) == "Today (Aug 11)"'
# A day total that has stopped growing would read as a stuck counter, so the
# date change is carried rather than left to the reader to work out.
check zai-success "stays silent about a day total that was not fetched" '
    (.details.today.available | not)
    and ([.quotaWindows[] | select(.key == "zai_today")] | length) == 0'
check zai-invalid-token "passes the token error through" '
    (.ok | not) and .error == "Z.AI: Invalid Z.AI token"'
check zai-missing "reports an unconfigured token" '
    (.ok | not) and .error == "Z.AI: no token configured"'

# ── Copilot ─────────────────────────────────────────────────────────────────

check copilot-success "reports premium requests against the quota" '
    .ok and .details.hasKey and .details.used == 125 and .details.quota == 500 and .details.pct == 25
    and .details.resetAt == 1785542400
    and .historyValues == {gh: 25}
    and .quotaWindows[0].detail == "125 / 500 requests"'
check copilot-error "passes the token error through" '
    (.ok | not) and (.error | startswith("Copilot: GitHub token cannot"))'
check copilot-missing "reports an unconfigured token" '
    (.ok | not) and .error == "Copilot: no token configured"'
# /copilot_internal/user reports the plan's own entitlement and the day it
# actually resets, so neither the configured quota nor "the first of next
# month" is guessed at.
check copilot-plan-quota "takes the quota and reset day from the plan" '
    .ok and .details.quota == 200 and .details.used == 19.8 and .details.plan == "individual"
    and .quotaWindows[0].detail == "19.8 / 200 requests"
    and .quotaWindows[0].resetAt == 1785542400'
check copilot-plan-quota "reports the local Copilot CLI activity" '
    .details.stats.available and .details.stats.totalSessions == 12
    and .details.stats.totalMessages == 96 and .details.stats.totalToolCalls == 210
    and .details.stats.totalFiles == 34 and .details.stats.totalRepositories == 2
    and .details.stats.activeDays == 3 and .details.stats.longestStreak == 3
    and .details.stats.peakHour == 14
    and .details.stats.totalTokens == 0 and .details.stats.dailyUnit == "messages"
    and (.details.stats.dailySeries | map(.total)) == [20, 36, 40]
    and .details.stats.topRepositories[0].name == "octocat/hello"'
# An unlimited plan has no bar to fill, so the meter is dropped rather than
# rendered as a permanent 0%.
check copilot-unlimited "renders an unlimited plan without a meter" '
    .ok and .details.unlimited and .summary.text == "∞"
    and (.quotaWindows[0].showMeter | not)
    and .quotaWindows[0].detail == "412 requests · unlimited"'
# The activity half stands on its own: no token, but the CLI history is local.
check copilot-missing "still reports no stats when there is no CLI history" '
    (.details.stats.available | not)'

# ── DeepSeek ────────────────────────────────────────────────────────────────

check deepseek-success "reports the balance split" '
    .ok and .details.primaryTotal == 12.5 and .details.symbol == "$"
    and .summary.text == "$12.5" and .historyValues == {ds: 12.5}
    and .quotaWindows[1].detail == "$2.5 / $10"'
check deepseek-error "passes the key error through" '
    (.ok | not) and .error == "DeepSeek: Invalid DeepSeek API key"'
check deepseek-missing "reports an unconfigured key" '
    (.ok | not) and .error == "DeepSeek: no API key configured"'

# ── Kimi / Moonshot ─────────────────────────────────────────────────────────

check kimi-success "reports the Moonshot balance split" '
    .ok and .details.keyValid
    and ((.details.availableBalance - 49.58894) | fabs) < 0.00001
    and ((.details.voucherBalance - 46.58893) | fabs) < 0.00001
    and ((.details.cashBalance - 3.00001) | fabs) < 0.00001
    and .historyValues == {km: 49.58894}'
check kimi-missing "reports that neither Kimi source is set up" '
    (.ok | not) and .error == "Kimi: no Moonshot API key or Kimi Code login"'
check kimi-success "keeps the balance-only view without a Kimi Code login" '
    .summary.detail == "Moonshot API" and .details.codePlan.available == false'
check kimi-code-success "shows the Kimi Code windows without a Moonshot key" '
    .ok and .summary.detail == "Kimi Code" and .summary.pct == 45
    and ([.quotaWindows[].label] == ["5-hour limit", "Weekly limit", "Extra usage"])
    and .quotaWindows[0].detail == "30 / 100" and .quotaWindows[2].detail == "$2.5 left"
    and .historyValues == {kc: 30, kcw: 45}
    and (.chartWindows | map(.label)) == ["5H", "24H", "7D", "30D"]
    and .details.codePlan.booster.balance == 2.5 and (.details.keyValid | not)'
check kimi-code-success "sends the raw window length so frontends can word the label" '
    [.details.codePlan.windows[] | {name, seconds}] == [{name: "", seconds: 18000}, {name: "", seconds: 604800}]'
check kimi-code-exhausted "reports a used-up plan as full rather than as an error" '
    .ok and .summary.pct == 100 and .quotaWindows[0].detail == "Credits used up"
    and .summary.hasChart == false and .chartWindows == [] and .details.codePlan.exhausted'

# ── Cursor ──────────────────────────────────────────────────────────────────

check cursor-success "reads included usage, the auto/API split and on-demand spend" '
    .ok and .summary.detail == "Pro" and .summary.pct == 62.5
    and ([.quotaWindows[].key] == ["cursor_total", "cursor_auto", "cursor_api", "cursor_on_demand"])
    and .quotaWindows[0].detail == "$12.5 / $20" and .quotaWindows[3].detail == "$3 / $10"
    and .quotaWindows[0].resetAt == 1790495647 and .details.resetAt == 1790495647
    and .historyValues == {cu: 62.5}'
check cursor-free "handles a free plan that reports percentages only" '
    .ok and .summary.detail == "Free" and .summary.pct == 0
    and .quotaWindows[0].detail == "0% of included usage" and (.quotaWindows | length) == 3
    and .details.nextUpgrade.name == "Pro" and .details.source == "cli"'
check cursor-success "turns the dashboard usage into the shared stats shape" '
    .details.stats.available and .details.stats.totalTokens == 198998
    and ((.details.stats.totalCostUSD - 1.56585075) | fabs) < 0.000001
    and .details.stats.favoriteModel == "claude-4.5-sonnet"
    and .details.stats.totalSessions == 2 and .details.stats.totalRequests == 3
    and .details.stats.longestSessionMs == 600000 and .details.stats.longestSessionMessages == 2
    and .details.stats.models.default.requests == 1 and .details.stats.dailyUnit == "tokens"
    and (.details.stats.partial | not)'
check cursor-free "has no stats without a stats blob" '.details.stats.available == false'
# ── Cline ───────────────────────────────────────────────────────────────────

check cline-success "sums the local session logs" '
    .ok and .details.stats.available and .details.stats.totalSessions == 3
    and .details.stats.totalTokens == 97365 and ((.details.stats.totalCostUSD - 0.47) | fabs) < 0.000001
    and .details.stats.favoriteModel == "anthropic/claude-sonnet-4.5"
    and .details.stats.models["anthropic/claude-sonnet-4.5"].sessions == 2
    and .details.stats.topWorkspaces[0] == {name: "ai-usage-widget", sessions: 2}
    and .details.stats.longestSessionMs == 600000
    and ([.quotaWindows[].key] == ["cline_today", "cline_7d", "cline_30d"])
    and .quotaWindows[2].detail == "97.4k tokens · 3 sessions · $0.47"
    and .summary.text == "97.4k" and .summary.detail == "last 30 days"
    and (.details.periods[1] | .sessions == 3 and .tokens == 97365)'
check cline-missing "reports a machine that never ran Cline" '
    (.ok | not) and .error == "Cline: no sessions yet — run cline once" and .details.stats.available == false'
check cursor-missing "reports a missing login" '
    (.ok | not) and .error == "Cursor: not signed in — run cursor-agent login"'
check cursor-expired "passes the login error through" '
    (.ok | not) and .error == "Cursor: login expired — run cursor-agent login"'

# ── Muse ────────────────────────────────────────────────────────────────────
#
# Muse is the only stats-only provider: Meta reports the plan windows solely on
# a billed model call, so the widget reads Muse's own local files and shows no
# quota at all. Every assertion here is therefore about totals, not meters.

check muse-success "reports lifetime totals from local sessions" '
    .ok and .details.hasLogin
    and .details.stats.totalTokens == 150000 and .details.stats.totalOutputTokens == 30000
    and .details.stats.model == "muse-spark-1.3-contributor"
    and .summary.text == "150k" and .summary.detail == "muse-spark-1.3-contributor"
    and .historyValues == {mu: 150000}'
# The catalog Muse caches locally carries its own price list, so spend is
# computed offline — the one provider here that can price itself.
check muse-success "prices the tokens from the local catalog" '
    .details.stats.totalCostUSD == 0.009
    and (.quotaWindows | map(.key)) == ["muse_tokens", "muse_spend"]
    and (.quotaWindows[] | select(.key == "muse_spend") | .detail) == "$0.01"
    and .details.stats.totalCostUSD == 0.009'
# No quota exists, so no row may claim one: a meter with no denominator would
# read as "0% used" forever.
check muse-success "shows no meter, because there is no quota to meter" '
    .summary.pct == 0 and ([.quotaWindows[].showMeter] | any | not)
    and ([.quotaWindows[].resetAt] | unique) == [0]'
check muse-success "carries the shared activity block" '
    .details.stats.available and .details.stats.activeDays == 3
    and .details.stats.longestStreak == 3 and .details.stats.peakHour == 14
    and .details.stats.dailyUnit == "tokens"
    and (.details.stats.dailySeries | map(.total)) == [10000, 8000, 12000]
    and .details.stats.topWorkspaces[0].name == "ai-usage-widget"
    and .details.stats.favoriteModel == "muse-spark-1.3-contributor"'
# Muse 1.0.3 does not always record token counters; the tab still has to be
# worth opening when it does not.
check muse-unpriced "stays usable when the logs carry no token counters" '
    .ok and .details.stats.totalTokens == 0 and .details.stats.totalCostUSD == 0
    and (.quotaWindows | map(.key)) == ["muse_tokens"]
    and .details.stats.available and .details.stats.totalSessions == 2
    and .details.stats.totalToolCalls == 3'
check muse-error "reports a login with no sessions yet" '
    (.ok | not) and .error == "Muse: no sessions yet"
    and .details.hasLogin and (.details.stats.available | not)'
check muse-missing "reports a machine without Muse" '
    (.ok | not) and .error == "Muse: not installed" and (.details.hasLogin | not)'
check muse-malformed "degrades when usage is not an object" '
    (.ok | not) and .error == "Muse: not installed"'

# ── Muse, with the billed quota switched on ─────────────────────────────────

check muse-quota-success "renders the plan windows above the free totals" '
    .ok and .summary.pct == 26 and .summary.text == "26%"
    and (.quotaWindows | map(.key)) == ["muse_current", "muse_weekly", "muse_tokens", "muse_spend"]
    and (.quotaWindows[0] | .pct == 26 and .resetAt == 1788528365 and .showMeter)
    and (.quotaWindows[1] | .pct == 9 and .resetAt == 1788739200)
    and .details.current.available and .details.weekly.available
    and .historyValues == {mu: 150000, mc: 26, mw: 9}
    and ([.chartWindows[].key] | unique | sort) == ["mc", "mw"]'
# The review case: paying for a quota and then discarding it because the local
# logs happen to be empty would be the worst of both worlds.
check muse-quota-only "renders a paid-for quota with no local sessions" '
    .ok and (.quotaWindows | map(.key)) == ["muse_current", "muse_weekly"]
    and .summary.pct == 26
    and (.details.stats.available | not)'
# A window at 0% used is a fresh window, not a missing one.
check muse-quota-success "gates availability on the reset time, not the pct" '
    [.quotaWindows[] | select(.showMeter) | .resetAt] | all(. > 1000000000)'

# ── End-to-end: settings toggles, key plumbing and the outer envelope ───────

TEST_TMP="$(mktemp -d)"
trap 'case "$TEST_TMP" in /tmp/*) rm -rf -- "$TEST_TMP" ;; esac' EXIT

cat >"$TEST_TMP/config.json" <<'JSON'
{
  "providers": {
    "claude": false, "antigravity": false, "openai": false, "kiro": false,
    "mistral": false, "openrouter": false, "grok": false, "muse": false,
    "zai": true, "copilot": true, "deepseek": true
  },
  "keys": { "zai": "zai-test", "github": "github-test", "deepseek": "deepseek-test" },
  "copilotQuota": 500
}
JSON

cat >"$TEST_TMP/zai.json" <<'JSON'
{"success":true,"data":{"level":"pro","limits":[
  {"type":"TOKENS_LIMIT","percentage":25,"nextResetTime":3600000,"used":250,"limit":1000},
  {"type":"TIME_LIMIT","percentage":40,"nextResetTime":7200000,"remaining":60,"usageDetails":[]}]}}
JSON
printf '{"login":"octocat"}\n' >"$TEST_TMP/github-user.json"
printf '[{"grossQuantity":125}]\n' >"$TEST_TMP/github-usage.json"
# A 200 that carries no quota snapshot — an account GitHub answers without
# Copilot quota — is what sends the provider to the billing endpoint.
printf '{"login":"octocat"}\n' >"$TEST_TMP/copilot-internal-empty.json"
printf '{"login":"octocat","copilot_plan":"individual","quota_reset_date":"2026-08-01","quota_snapshots":{"premium_interactions":{"has_quota":true,"unlimited":false,"entitlement":200,"quota_remaining":180.2,"percent_remaining":90.1}}}\n' \
    >"$TEST_TMP/copilot-internal.json"
cat >"$TEST_TMP/deepseek.json" <<'JSON'
{"is_available":true,"balance_infos":[
  {"currency":"USD","total_balance":"12.50","granted_balance":"2.50","topped_up_balance":"10.00"}]}
JSON

run_backend() {
    # The CLI-login providers (kiro-cli, Kimi Code, Cursor) follow the XDG
    # variables, so a developer's own would otherwise leak real logins in.
    env -u KIRO_CLI_DB -u KIRO_IDE_DB -u KIMI_CODE_HOME -u CURSOR_AUTH_PATH -u CURSOR_IDE_DB \
        XDG_CONFIG_HOME="$TEST_TMP/home/.config" \
        XDG_DATA_HOME="$TEST_TMP/home/.local/share" \
        HOME="$TEST_TMP/home" \
        AI_USAGE_CONFIG="$TEST_TMP/config.json" \
        AI_USAGE_CACHE_DIR="$TEST_TMP/cache" \
        ZAI_RESPONSE_FILE="$TEST_TMP/zai.json" \
        COPILOT_USER_RESPONSE_FILE="$TEST_TMP/github-user.json" \
        COPILOT_USAGE_RESPONSE_FILE="$TEST_TMP/github-usage.json" \
        COPILOT_INTERNAL_RESPONSE_FILE="${COPILOT_INTERNAL_FILE:-$TEST_TMP/copilot-internal-empty.json}" \
        DEEPSEEK_BALANCE_RESPONSE_FILE="$TEST_TMP/deepseek.json" \
        MUSE_SESSIONS_DIR="$TEST_TMP/muse-sessions" \
        MUSE_AUTH_PATH="$TEST_TMP/muse-auth.json" \
        MUSE_SETTINGS_PATH="$TEST_TMP/muse-settings.json" \
        MUSE_CATALOG_DIR="$TEST_TMP/muse-catalog" \
        "$BACKEND" "$@"
}

assert_backend() {
    local description="$1" filter="$2" output
    shift 2
    checks=$((checks + 1))
    output="$(run_backend "$@")"
    if ! printf '%s' "$output" | jq -e "$filter" >/dev/null 2>&1; then
        printf 'FAIL %s\n  got: %s\n' "$description" "$output" >&2
        failures=$((failures + 1))
    fi
}

# check_prog <label> <expected stdout> <python program, aiusage importable>
check_prog() {
    local label="$1" expected="$2" prog="$3" got
    checks=$((checks + 1))
    if ! got="$(TEST_TMP="$TEST_TMP" python3 -c "import sys; sys.path.insert(0, '$ROOT/package/contents/tools')
$prog" 2>&1)"; then
        got="raised: $got"
    fi
    if [ "$got" = "$expected" ]; then
        return 0
    fi
    failures=$((failures + 1))
    printf 'FAIL %s\n  expected: %s\n  got: %s\n' "$label" "$expected" "$got"
}

assert_backend "--all honours the provider toggles and API keys" '
    .schemaVersion == 1
    and (.providers | length) == 3
    and (.providers | map(.id) | sort) == ["copilot", "deepseek", "zai"]
    and .active == "zai"
    and (.providers[] | select(.id == "zai") | .historyValues.za) == 25
    and (.providers[] | select(.id == "copilot") | .historyValues.gh) == 25
    and (.providers[] | select(.id == "copilot") | .quotaWindows[0].detail) == "125 / 500 requests"
    and (.providers[] | select(.id == "deepseek") | .details.currency) == "USD"
    and (tojson | test("zai-test|github-test|deepseek-test") | not)' --all

COPILOT_INTERNAL_FILE="$TEST_TMP/copilot-internal.json"
assert_backend "prefers the Copilot plan quota over the billing endpoint" '
    (.providers[] | select(.id == "copilot") | .details.quota) == 200
    and (.providers[] | select(.id == "copilot") | .details.used) == 19.8
    and (.providers[] | select(.id == "copilot") | .details.resetAt) == 1785542400' --all
unset COPILOT_INTERNAL_FILE

assert_backend "--provider fetches exactly what was asked for" '
    (.providers | map(.id)) == ["deepseek", "zai"]' --provider deepseek,zai

assert_backend "--provider ignores the enabled toggles" '
    (.providers | length) == 1 and .providers[0].id == "kiro"' --provider kiro

# ── kiro-cli, Kimi Code and Cursor: the CLI logins, end to end ──────────────
#
# Each login is planted where the vendor's own CLI writes it, and each answer
# is a recorded one — the Kiro and Cursor bodies are live payloads of a free
# account, identifiers removed — so the real readers run without a socket.
CLI_HOME="$TEST_TMP/cli-home"
mkdir -p "$CLI_HOME/.config/cursor" "$CLI_HOME/.kimi-code/credentials" "$CLI_HOME/.local/share/kiro-cli"
CLI_HOME="$CLI_HOME" python3 - <<'PY'
import base64, json, os, sqlite3
home = os.environ["CLI_HOME"]
db = sqlite3.connect(os.path.join(home, ".local/share/kiro-cli/data.sqlite3"))
db.execute("CREATE TABLE auth_kv (key TEXT PRIMARY KEY, value TEXT)")
db.execute("CREATE TABLE state (key TEXT PRIMARY KEY, value BLOB)")
db.execute("INSERT INTO auth_kv VALUES (?, ?)", ("kirocli:social:token", json.dumps({
    "access_token": "kiro-secret-token", "refresh_token": "kiro-secret-refresh",
    "expires_at": "2099-01-01T00:00:00.123456789Z", "provider": "google",
    "profile_arn": "arn:aws:codewhisperer:us-east-1:000000000000:profile/TEST"})))
db.commit()
payload = base64.urlsafe_b64encode(json.dumps({"exp": 4102444800}).encode()).decode().rstrip("=")
with open(os.path.join(home, ".config/cursor/auth.json"), "w") as f:
    json.dump({"accessToken": f"eyJhbGciOiJIUzI1NiJ9.{payload}.cursor-secret-sig", "refreshToken": "cursor-secret-refresh"}, f)
with open(os.path.join(home, ".kimi-code/credentials/kimi-code.json"), "w") as f:
    json.dump({"access_token": "kimi-secret-token", "refresh_token": "kimi-secret-refresh", "expires_at": 4102444800,
               "scope": "", "token_type": "Bearer", "expires_in": 900}, f)
PY
cat >"$TEST_TMP/kiro-cli.json" <<'JSON'
{"daysUntilReset":0,"limits":[],"nextDateReset":1790812800.0,
 "overageConfiguration":{"overageLimit":null,"overageStatus":"DISABLED"},
 "subscriptionInfo":{"subscriptionTitle":"KIRO FREE"},
 "usageBreakdownList":[{"bonuses":[],"currency":"USD","currentOverages":0,"currentOveragesWithPrecision":0.0,
   "currentUsage":0,"currentUsageWithPrecision":0.13,"displayName":"Credit","displayNamePlural":"Credits",
   "freeTrialInfo":{"currentUsage":23,"currentUsageWithPrecision":23.07,"freeTrialExpiry":1770928838.6,
     "freeTrialStatus":"EXPIRED","usageLimit":500,"usageLimitWithPrecision":500.0},
   "nextDateReset":1790812800.0,"overageCap":10000,"overageCapWithPrecision":10000.0,"overageCharges":0.0,
   "overageCredits":[],"overageRate":0.04,"resourceType":"CREDIT","unit":"INVOCATIONS",
   "usageLimit":50,"usageLimitWithPrecision":50.0}],
 "userInfo":{"email":"test@example.com","userId":"test"}}
JSON
cat >"$TEST_TMP/cursor-usage.json" <<'JSON'
{"billingCycleStart":"1787817247821","billingCycleEnd":"1790495647821",
 "planUsage":{"remainingBonus":false,"autoPercentUsed":0,"apiPercentUsed":0,"totalPercentUsed":0},
 "spendLimitUsage":{"pooledLimit":0,"pooledRemaining":0,"individualLimit":0,"limitType":"user","overallLimit":0,"overallRemaining":0},
 "displayMessage":"You've used 0% of your included usage","autoBucketModels":["default"]}
JSON
cat >"$TEST_TMP/cursor-plan.json" <<'JSON'
{"planInfo":{"planName":"Free","price":"Free","billingCycleEnd":"1790495647821"},
 "nextUpgrade":{"tier":"pro","name":"Pro","includedAmountCents":2000,"price":"$20/mo","description":"Upgrade to Cursor Pro"}}
JSON
# The dashboard's two usage RPCs, as a personal account answers them. The
# per-request list names the account and the conversation; neither may reach
# the envelope.
cat >"$TEST_TMP/cursor-aggregated.json" <<'JSON'
{"aggregations":[{"modelIntent":"default","inputTokens":"31047","outputTokens":"879","cacheReadTokens":"67072","totalCents":6.085075,"tier":0}],
 "totalInputTokens":"31047","totalOutputTokens":"879","totalCacheReadTokens":"67072","totalCostCents":6.085075}
JSON
cat >"$TEST_TMP/cursor-events.json" <<'JSON'
{"totalUsageEventsCount":2,"usageEventsDisplay":[
 {"timestamp":"1789047292738","model":"default","kind":"USAGE_EVENT_KIND_CUSTOM_SUBSCRIPTION","customSubscriptionName":"free",
  "requestsCosts":1.6,"usageBasedCosts":"-","isTokenBasedCall":true,
  "tokenUsage":{"inputTokens":20000,"outputTokens":500,"cacheReadTokens":40000,"totalCents":3.925475},
  "owningUser":"123456","userEmail":"test@example.com","isChargeable":true,"isHeadless":false,
  "chargedCents":3.925475,"conversationId":"conv-secret-1","subscriptionProductId":"free"},
 {"timestamp":"1789047269035","model":"default","kind":"USAGE_EVENT_KIND_CUSTOM_SUBSCRIPTION","customSubscriptionName":"free",
  "requestsCosts":0.9,"usageBasedCosts":"-","isTokenBasedCall":true,
  "tokenUsage":{"inputTokens":11047,"outputTokens":379,"cacheReadTokens":27072,"totalCents":2.1596},
  "owningUser":"123456","userEmail":"test@example.com","isChargeable":true,"isHeadless":false,
  "chargedCents":2.1596,"conversationId":"conv-secret-1","subscriptionProductId":"free"}]}
JSON
# Shaped after the Kimi CLI's own parser (parseManagedUsagePayload): numbers may
# arrive as strings, and wallet amounts are cents × 10^6.
cat >"$TEST_TMP/kimi-code.json" <<'JSON'
{"usage":{"used":"450","limit":"1000","resetTime":"2026-09-14T00:00:00Z"},
 "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
            "detail":{"used":30,"limit":100,"resetTime":"2026-09-10T18:00:00.000Z"}}],
 "boosterWallet":{"balance":{"type":"BOOSTER","amount":"1000000000","amountLeft":"250000000"},
                  "monthlyUsed":{"priceInCents":750,"currency":"USD"}}}
JSON

cli_checks=$((checks + 1))
checks=$cli_checks
cli_out="$(env -u KIRO_CLI_DB -u KIRO_IDE_DB -u KIMI_CODE_HOME -u CURSOR_AUTH_PATH -u CURSOR_IDE_DB \
    -u MOONSHOT_API_KEY -u KIMI_API_KEY -u WIDGET_MOONSHOT_API_KEY \
    HOME="$CLI_HOME" XDG_CONFIG_HOME="$CLI_HOME/.config" XDG_DATA_HOME="$CLI_HOME/.local/share" \
    AI_USAGE_CONFIG="$TEST_TMP/config.json" AI_USAGE_CACHE_DIR="$TEST_TMP/cache" \
    KIRO_CLI_USAGE_RESPONSE_FILE="$TEST_TMP/kiro-cli.json" \
    CURSOR_USAGE_RESPONSE_FILE="$TEST_TMP/cursor-usage.json" \
    CURSOR_PLAN_RESPONSE_FILE="$TEST_TMP/cursor-plan.json" \
    CURSOR_AGGREGATED_RESPONSE_FILE="$TEST_TMP/cursor-aggregated.json" \
    CURSOR_EVENTS_RESPONSE_FILE="$TEST_TMP/cursor-events.json" \
    KIMI_CODE_USAGE_RESPONSE_FILE="$TEST_TMP/kimi-code.json" \
    "$BACKEND" --provider kiro,kimi,cursor)"
if ! printf '%s' "$cli_out" | jq -e '
    (.providers[] | select(.id == "kiro")
        | .ok and .details.source == "cli" and .details.planType == "free"
          and .details.currentUsage == 0.13 and .details.usageLimit == 50 and .details.resetAt == 1790812800
          and .quotaWindows[0].detail == "0.13 / 50 credits")
    and (.providers[] | select(.id == "cursor")
        | .ok and .summary.detail == "Free" and .details.resetAt == 1790495647 and .details.source == "cli"
          and .details.stats.available and .details.stats.totalTokens == 98998
          and .details.stats.totalRequests == 2 and .details.stats.totalSessions == 1
          and .details.stats.dailyUnit == "tokens" and (.details.stats.dailySeries | map(.total) | add) == 98998)
    and (.providers[] | select(.id == "kimi")
        | .ok and ([.quotaWindows[].label] == ["5-hour limit", "Weekly limit", "Extra usage"])
          and .quotaWindows[0].resetAt == 1789063200 and .quotaWindows[1].resetAt == 1789344000
          and .details.codePlan.booster.balance == 2.5
          and .historyValues == {kc: 30, kcw: 45})
    and (tojson | test("secret|test@example.com") | not)' >/dev/null 2>&1; then
    printf 'FAIL the CLI logins are read end to end\n  got: %s\n' "$cli_out" >&2
    failures=$((failures + 1))
fi

check_prog "a Kimi 429 for a used-up plan reads as exhausted" "True Credits used up" '
from aiusage.providers.kimi_code import parse_usage_response
r = parse_usage_response(429, """{"code":"resource_exhausted","message":"insufficient balance","details":[{"type":"common.error.v1.ErrorDetail","debug":{"reason":"REASON_QUOTA_EXCEEDED","localizedMessage":{"locale":"en-US","message":"Credits used up."}}}]}""")
print(r["exhausted"], r["message"])'
check_prog "a plain Kimi 429 is still rate limiting" "Kimi Code rate limited" '
from aiusage.providers.kimi_code import parse_usage_response
print(parse_usage_response(429, "{}")["error"])'
check_prog "an expired Kimi Code login is reported, not refreshed" "Kimi Code login expired — run kimi once to refresh it" '
import json, os
home = os.path.join(os.environ["TEST_TMP"], "kimi-expired")
os.makedirs(os.path.join(home, "credentials"), exist_ok=True)
json.dump({"access_token": "kimi-secret-token", "expires_at": 1000}, open(os.path.join(home, "credentials", "kimi-code.json"), "w"))
os.environ["KIMI_CODE_HOME"] = home
from aiusage.providers.kimi_code import get_kimi_code_usage
print(get_kimi_code_usage()["error"])'
check_prog "an expired Cursor token is reported without a request" "login expired — run cursor-agent login" '
import base64, json, os
path = os.path.join(os.environ["TEST_TMP"], "cursor-expired-auth.json")
payload = base64.urlsafe_b64encode(json.dumps({"exp": 1000}).encode()).decode().rstrip("=")
json.dump({"accessToken": "h." + payload + ".s"}, open(path, "w"))
os.environ["CURSOR_AUTH_PATH"] = path
from aiusage.providers.cursor import get_cursor_usage
print(get_cursor_usage()["error"])'
check_prog "an unexpected ARN region never reaches the hostname" "us-east-1 eu-central-1" '
from aiusage.providers.kiro import _region_of
print(_region_of("arn:aws:codewhisperer:evil.example/x:1:profile/a"), _region_of("arn:aws:codewhisperer:eu-central-1:1:profile/a"))'

# ── Muse, end to end: only local files, and never a socket ──────────────────
#
# The store, the catalog and the settings file are all planted here, so this
# exercises the real reader: dynamic model, catalog pricing, workspace names.
mkdir -p "$TEST_TMP/muse-sessions/2026/09/04/aaa" \
    "$TEST_TMP/muse-sessions/2026/09/04/aaa/subagent/bbb" \
    "$TEST_TMP/muse-sessions/.msp-view-v1/aaa" \
    "$TEST_TMP/muse-catalog"
cat >"$TEST_TMP/muse-auth.json" <<'JSON'
{"providers": {"meta": {"mechanism": "oauth", "api_key": "muse-secret-token", "access_token": "muse-secret-token", "user_email": "test@example.com", "user_full_name": "Test User"}}}
JSON
cat >"$TEST_TMP/muse-settings.json" <<'JSON'
{"schema_version": 1, "provider": "meta", "model": "fixture-spark-9.9"}
JSON
# Hex-named exactly as the CLI writes it, to prove the directory is globbed
# rather than reconstructed from a provider id.
cat >"$TEST_TMP/muse-catalog/6d657461__p746268.json" <<'JSON'
{"schema_version": 1, "provider_id": "meta", "profile_id": "tbh", "source": "provider_catalog",
 "rows": [
   {"model_id": "fixture-spark-9.9", "display_label": "fixture-spark-9.9", "visibility": "visible",
    "is_current": true, "is_default": true, "context_limit": 1007997, "output_limit": 128000,
    "cost": {"input": "1.00", "output": "10.00", "cached": "0.10", "currency": "USD"}}
 ]}
JSON
cat >"$TEST_TMP/muse-sessions/2026/09/04/aaa/session.jsonl" <<'JSON'
{"schema_version":1,"id":"1","stream":{"kind":"session","id":"aaa"},"sequence":1,"recorded_at":1785000000000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session.metadata","payload_schema_version":1,"payload":{"kind":"metadata","record":{"workspace_root":"/home/someone/secret-project"}}}
{"schema_version":1,"id":"2","stream":{"kind":"session","id":"aaa"},"sequence":2,"recorded_at":1785000001000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"run.model.configured","payload_schema_version":1,"payload":{"kind":"run_model","record":{"model_id":"fixture-spark-9.9","provider_id":"meta"}}}
{"schema_version":1,"id":"3","stream":{"kind":"session","id":"aaa"},"sequence":3,"recorded_at":1785000002000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session","payload_schema_version":1,"payload":{"kind":"run","run_id":"r1","event":{"kind":"user_prompt_display"}}}
{"schema_version":1,"id":"4","stream":{"kind":"session","id":"aaa"},"sequence":4,"recorded_at":1785000003000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session","payload_schema_version":1,"payload":{"kind":"run","run_id":"r1","event":{"kind":"model_completed","model":"fixture-spark-9.9","usage":{"input_tokens":1000,"output_tokens":200,"cached_tokens":400,"reasoning_tokens":10}}}}
{"schema_version":1,"id":"5","stream":{"kind":"session","id":"aaa"},"sequence":5,"recorded_at":1785000004000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session","payload_schema_version":1,"payload":{"kind":"run","run_id":"r1","event":{"kind":"assistant_tool_calls_committed","tool_calls":[{"name":"bash"},{"name":"read"}]}}}
{"schema_version":1,"id":"6","stream":{"kind":"session","id":"aaa"},"sequence":6,"recorded_at":1785000005000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session","payload_schema_version":1,"payload":{"kind":"run","run_id":"r1","event":{"kind":"assistant_message_committed"}}}
{"schema_version":1,"id":"7","stream":{"kind":"session","id":"aaa"},"sequence":7,"recorded_at":1785000006000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session","payload_schema_version":1,"payload":{"kind":"run","run_id":"r1","event":{"kind":"terminal"}}}
JSON
printf '{"schema_version":1,"id":"8","stream":{"kind":"session","id":"bbb"},"sequence":1,"recorded_at":1785000007000000,"record_type":"event","durability":"durable","causation_id":null,"payload_type":"runtime.session","payload_schema_version":1,"payload":{"kind":"run","run_id":"r2","event":{"kind":"model_completed","model":"fixture-spark-9.9","usage":{"input_tokens":500,"output_tokens":100,"cached_tokens":0,"reasoning_tokens":5}}}}\n' >"$TEST_TMP/muse-sessions/2026/09/04/aaa/subagent/bbb/session.jsonl"

# 1000 input of which 400 cached, + 200 output, on the subagent 500 + 100:
#   (1500 - 400)/1e6 * $1.00 + 400/1e6 * $0.10 + 300/1e6 * $10.00 = $0.00414
assert_backend "reads Muse from local files only, priced by the local catalog" '
    (.providers | length) == 1 and .providers[0].id == "muse"
    and .providers[0].ok
    and .providers[0].details.hasLogin
    and .providers[0].details.stats.model == "fixture-spark-9.9"
    and .providers[0].details.stats.totalOutputTokens == 300
    and .providers[0].details.stats.totalTokens == 1800
    and ((.providers[0].details.stats.totalCostUSD * 100000 | round) == 414)
    and .providers[0].details.stats.contextWindow == 1007997
    and .providers[0].details.stats.totalSessions == 1
    and .providers[0].details.stats.subagentSessions == 1
    and .providers[0].details.stats.totalToolCalls == 2
    and .providers[0].details.stats.totalMessages == 2
    and .providers[0].details.stats.topWorkspaces[0].name == "secret-project"
    and .providers[0].details.email == "test@example.com"
    and .providers[0].historyValues.mu == 1800
    and (.providers[0].quotaWindows | map(.key)) == ["muse_tokens", "muse_spend"]' --provider muse

# The credential in the store is never read, never exported and never rendered;
# only the workspace *folder name* may appear, never the path it sits in.
assert_backend "never leaks the stored credential or a filesystem path" '
    (tojson | test("muse-secret-token") | not)
    and (tojson | test("/home/someone") | not)' --provider muse

# The counted-once fold the TUI itself prints wins over per-call raw sums.
cat >"$TEST_TMP/muse-sessions/.msp-view-v1/aaa/snapshot-1.json" <<'JSON'
{"view_materialization": {"current_state": {"tokenUsage": {"promptTokens": 900, "outputTokens": 250, "totalTokens": 1150}, "turnCount": 1}}}
JSON
rm -f "$TEST_TMP/cache/muse-stats.json"
assert_backend "prefers the view snapshot's counted-once totals" '
    (.providers[0].details.stats.totalTokens) == 1750
    and (.providers[0].details.stats.totalOutputTokens) == 350' --provider muse

# The cached blob is derived from the catalog and the view snapshots too, not
# only from the session logs. Both land without any session.jsonl being
# touched, so neither may be allowed to leave a stale total on screen — hence
# no `rm` of the cache here, unlike the assertion above.
cat >"$TEST_TMP/muse-sessions/.msp-view-v1/aaa/snapshot-1.json" <<'JSON'
{"view_materialization": {"current_state": {"tokenUsage": {"promptTokens": 900, "outputTokens": 450, "totalTokens": 1350}, "turnCount": 1}}}
JSON
touch -d "@$(($(date +%s) + 5))" "$TEST_TMP/muse-sessions/.msp-view-v1/aaa/snapshot-1.json"
assert_backend "a new view snapshot invalidates the stats cache" '
    (.providers[0].details.stats.totalTokens) == 1950
    and (.providers[0].details.stats.totalOutputTokens) == 550' --provider muse

# Same for a re-fetched catalog: the price list moves, the cost has to move.
# The catalog is shared with the assertions further down, so it is put back
# exactly as it was — with a fresh mtime, so the restored prices invalidate the
# cache in their turn.
cp "$TEST_TMP/muse-catalog/6d657461__p746268.json" "$TEST_TMP/muse-catalog.orig"
sed 's/"input": "1.00"/"input": "2.00"/' "$TEST_TMP/muse-catalog.orig" >"$TEST_TMP/muse-catalog/6d657461__p746268.json"
touch -d "@$(($(date +%s) + 10))" "$TEST_TMP/muse-catalog/6d657461__p746268.json"
assert_backend "a re-priced catalog invalidates the stats cache" '
    (.providers[0].details.stats.totalCostUSD) > 0.005' --provider muse
mv "$TEST_TMP/muse-catalog.orig" "$TEST_TMP/muse-catalog/6d657461__p746268.json"
touch -d "@$(($(date +%s) + 15))" "$TEST_TMP/muse-catalog/6d657461__p746268.json"

# The billed quota is opt-in: an untouched install makes no call at all.
assert_backend "the billed quota stays off until it is switched on" '
    .providers[0].details.quotaError == "disabled"
    and (.providers[0].details.current.available | not)
    and (.providers[0].historyValues | has("mc") | not)' --provider muse

# SSE frames arrive CRLF-terminated often enough that splitting on "\n\n"
# alone would silently yield no quota at all. Replay a real-shaped CRLF stream.
printf 'event: response.created\r\ndata: {"type":"response.created"}\r\n\r\nevent: response.subscription_usage\r\ndata: {"type":"response.subscription_usage","subscription":{"window":{"used_percent":26,"resets_at":1788528365,"window_duration_mins":300},"weekly":{"used_percent":9,"resets_at":1788739200}}}\r\n\r\n' >"$TEST_TMP/muse-quota-crlf.sse"

MUSE_QUOTA_RESPONSE_FILE="$TEST_TMP/muse-quota-crlf.sse" WIDGET_MUSE_QUOTA=1 \
    assert_backend "parses a CRLF-terminated SSE quota stream" '
    .providers[0].details.quotaError == ""
    and .providers[0].details.current.pct == 26
    and .providers[0].details.weekly.pct == 9
    and .providers[0].historyValues.mc == 26' --provider muse

check_prog "an unset switch reads as off" "False" '
import os
os.environ.pop("WIDGET_MUSE_QUOTA", None)
from aiusage.config import muse_quota_enabled
print(muse_quota_enabled())'
check_prog "an explicit opt-in turns it on" "True" '
import os
os.environ["WIDGET_MUSE_QUOTA"] = "1"
from aiusage.config import muse_quota_enabled
print(muse_quota_enabled())'

# A timeout must not be reported as a rejected credential.
check_prog "an HTTP 401 is a rejected credential" "rejected" '
from urllib.error import HTTPError
from aiusage.providers.muse_quota import error_code
print(error_code(HTTPError("u", 401, "x", {}, None)))'
check_prog "a timeout is unreachable, not invalid" "unreachable" '
from aiusage.providers.muse_quota import error_code
print(error_code(TimeoutError()))'
check_prog "a 500 is unreachable, not a bad key" "unreachable" '
from urllib.error import HTTPError
from aiusage.providers.muse_quota import error_code
print(error_code(HTTPError("u", 500, "x", {}, None)))'
check_prog "no credential is reported as such" "{} no-credential" '
import os
os.environ["WIDGET_MUSE_QUOTA"] = "1"
os.environ.pop("MUSE_QUOTA_RESPONSE_FILE", None)
os.environ["MUSE_AUTH_PATH"] = "/nonexistent/auth.json"
os.environ["META_API_KEY"] = ""
from aiusage.providers.muse_quota import get_muse_quota
q, e = get_muse_quota()
print(q, e)'
# CRLF frames must parse exactly like LF ones.
check_prog "CRLF and LF frames parse identically" "True" '
from aiusage.providers.muse_quota import parse_subscription_event
body = ("event: response.subscription_usage\r\n"
        "data: {\"type\": \"response.subscription_usage\", \"subscription\": {\"window\": {\"used_percent\": 7}}}\r\n\r\n")
print(parse_subscription_event(body) == parse_subscription_event(body.replace("\r\n", "\n")))'
# The model for the billed call is the CLI's own, never a name pinned in our
# source — and the warning the frontends show is priced from the local catalog.
check_prog "the quota model comes from the CLI settings" "fixture-spark-9.9" '
import os
os.environ["MUSE_SETTINGS_PATH"] = os.environ["TEST_TMP"] + "/muse-settings.json"
from aiusage.providers.muse_quota import quota_model
print(quota_model())'
check_prog "one refresh is priced from the local catalog" "132 0.00121" '
import os
os.environ["MUSE_SETTINGS_PATH"] = os.environ["TEST_TMP"] + "/muse-settings.json"
os.environ["MUSE_CATALOG_DIR"] = os.environ["TEST_TMP"] + "/muse-catalog"
from aiusage.providers.muse_quota import refresh_cost
c = refresh_cost()
print(c["tokens"], round(c["usd"], 5))'

# Opt-in like every other provider that is useless without its vendor
# installed — and unlike the PR this replaces, which defaulted Muse on.
check_prog "muse stays off until it is switched on" "False" '
from aiusage.config import provider_enabled
print(provider_enabled({}, "muse"))'

# A stats-only provider must not grow a network path by accident. Checked
# against the import graph rather than the text, so prose about not opening a
# socket does not fail its own test.
check_prog "the provider module imports nothing that can reach the network" "clean" '
import ast, inspect
from aiusage.providers import muse
NET = {"urllib", "http", "socket", "ssl", "requests", "httpx", "asyncio", "ftplib", "smtplib", "telnetlib", "xmlrpc"}
found = set()
for node in ast.walk(ast.parse(inspect.getsource(muse))):
    if isinstance(node, ast.Import):
        found.update(a.name.split(".")[0] for a in node.names)
    elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
        found.add(node.module.split(".")[0])
print(", ".join(sorted(found & NET)) or "clean")'

# The shared formatter must not have drifted either vendor'"'"'s printed strings.
check_prog "the shared formatter keeps both vendors byte-identical" "41.18M 1.00K 500 30k 1.5k 2M 500" '
from aiusage.normalize.zai import _compact as z
from aiusage.normalize.muse import _compact as m
print(z(41180000), z(1000), z(500), m(30000), m(1500), m(2000000), m(500))'

checks=$((checks + 1))
if run_backend --provider nonsense >/dev/null 2>&1; then
    printf 'FAIL: an unknown provider id should be rejected\n' >&2
    failures=$((failures + 1))
fi

cat >"$TEST_TMP/defaults.json" <<'JSON'
{"providers": {"claude": false, "antigravity": false, "openai": false, "kiro": false,
               "mistral": false, "openrouter": false, "grok": false, "muse": false}}
JSON
checks=$((checks + 1))
defaults="$(HOME="$TEST_TMP/home" AI_USAGE_CONFIG="$TEST_TMP/defaults.json" \
    AI_USAGE_CACHE_DIR="$TEST_TMP/cache" "$BACKEND" --all)"
if ! printf '%s' "$defaults" | jq -e '(.providers | length) == 0 and .active == ""' >/dev/null 2>&1; then
    printf 'FAIL: opt-in providers should stay off by default\n  got: %s\n' "$defaults" >&2
    failures=$((failures + 1))
fi

# ── Credentials from the environment are stripped ───────────────────────────
# A token pasted into the widget's settings field with a trailing newline is
# passed straight through as WIDGET_*. urllib rejects such a header value with
# a ValueError whose message contains the credential, so an unstripped value
# both breaks the provider and prints the secret in the traceback. Tested here
# rather than through a provider call: a fixture returns before the header is
# built, so only resolve_key itself can show the difference.
# shellcheck source=../package/contents/tools/sh/python-interp.sh
. "$ROOT/package/contents/tools/sh/python-interp.sh"
if py_resolve; then
    checks=$((checks + 1))
    # $'…' keeps the newline: command substitution would strip it and the case
    # under test would silently disappear.
    stripped="$(WIDGET_TEST_KEY=$'secret-value\n' \
        PYTHONPATH="$ROOT/package/contents/tools" "$PY" -c '
from aiusage.http import resolve_key
print(repr(resolve_key("WIDGET_TEST_KEY", "", )))
')"
    if [ "$stripped" != "'secret-value'" ]; then
        printf 'FAIL: a trailing newline must not survive into a credential\n  got: %s\n' "$stripped" >&2
        failures=$((failures + 1))
    fi
fi

if [ "$failures" -ne 0 ]; then
    printf '%d of %d checks failed\n' "$failures" "$checks" >&2
    exit 1
fi
printf 'get-ai-usage: %d checks passed\n' "$checks"
