# Providers

What each provider tab reads, where it looks for credentials, and what the
underlying API does or does not expose. For the JSON model these all produce,
see [`provider-contract.md`](provider-contract.md).

## Claude and OpenAI cost estimates

Organization token costs use the community-maintained
[LiteLLM JSON pricing catalog](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json).
The widget downloads data only, with no LiteLLM package dependency. Direct
Anthropic and OpenAI standard token rates are selected by exact model ID;
reseller and regional rates are excluded. Prices refresh automatically once
per day when organization usage needs pricing, and both providers share
`pricing-litellm-v1.json` in the widget's cache directory (`AI_USAGE_CACHE_DIR`
can override that location). No account credentials or usage are sent to the
catalog host.

A failed or malformed download retains the last good cache and retries after
15 minutes. Before the first successful download, or for a model absent from
the catalog, tokens remain visible with `priced: false`; cost totals include
only priced models. These are standard-rate estimates, not invoices: contract
discounts, batch rates, long-context tiers and other per-request charges cannot
be reconstructed from the aggregate usage available here. Claude Code's local
recorded costs and subscription limits continue to come from their existing
sources.

## Setup per provider

Enable only the services you use. Each one has its own setup requirement:

| Service | What you need |
|---|---|
| Claude | Claude Code, signed in locally |
| Antigravity | Node.js 18+, the `antigravity-usage` CLI, and a Google account with access |
| OpenAI | An OpenAI API key for organization API usage; a Codex CLI login provides Codex/ChatGPT plan limits and account status |
| Grok | Grok CLI authenticated with `grok --oauth`; an xAI API key is optional |
| Kiro | kiro-cli signed in (`kiro-cli login`), or the Kiro IDE signed in at least once |
| Mistral AI | A Mistral API key; vibe CLI is optional and adds local session statistics |
| OpenRouter | An OpenRouter API key entered in widget settings |
| Ollama Cloud | Enable the provider, then use an Ollama API key in widget settings or `$OLLAMA_API_KEY`; the `ollama-cloud` API-key login from OpenCode is also detected automatically |
| Local Models | Enable the separate Local Models provider. It checks Ollama (`127.0.0.1:11434`), vLLM (`127.0.0.1:8000`), and llama.cpp (`127.0.0.1:8080`). Set one or more comma-separated URLs in provider settings, or use `WIDGET_SELFHOSTED_ENDPOINT`, `WIDGET_SELFHOSTED_ENGINE`, and optional `WIDGET_SELFHOSTED_KEY`. Empty URLs auto-discover all three defaults. Token counters are since server start, where exposed. |

The local provider only reads health, model, slot, and metrics endpoints. It never sends a generation request. On a local URL, NVIDIA VRAM and GPU activity are read with a 300 ms `nvidia-smi` timeout. This is host-level telemetry and may appear under multiple servers on the same machine. Remote servers use only telemetry exposed by their runtime. Ollama's `/api/ps` reports loaded model size but not total GPU memory or token counters; those values are shown without a percentage or invented token total when no hardware telemetry is available. Runtime counters reset when the server restarts. The panel gauge uses the highest available utilization across configured servers.
| Z.AI | A Z.AI token from widget settings, `$ZAI_TOKEN`, `$Z_AI_API_KEY`, `~/.config/zai/token`, `~/.zai/token`, or the one `glm-acp-agent --setup` already stored |
| GitHub Copilot | Usually nothing to configure: the Copilot editor login (`~/.config/github-copilot/apps.json`), the Copilot CLI login, or `gh auth token` is picked up automatically. Widget settings, `$GITHUB_TOKEN` and `$GH_TOKEN` still win when set; a token with fine-grained **Plan: read** permission additionally unlocks the documented billing endpoint. Personal billing only |
| DeepSeek | A DeepSeek API key from widget settings, `$DEEPSEEK_API_KEY`, or `~/.config/deepseek/api-key` |
| Kimi / Moonshot AI | A Kimi Code login (`kimi`, then `/login`) for the plan quota, and/or a Moonshot API key from widget settings, `$MOONSHOT_API_KEY`, `$KIMI_API_KEY`, or `~/.config/moonshot/api-key` for the API balance |
| Muse | Nothing to configure for the local stats — `muse login` is enough. The optional plan quota additionally uses `$META_API_KEY` or the key `muse login` stored |
| Cursor | cursor-agent signed in (`cursor-agent login`), or the Cursor IDE signed in. No API key |
| Cline | The Cline CLI, run at least once. Nothing to configure |

All configuration is done in the widget's settings panel (right-click the widget
→ *Configure*).

Provider APIs do not all expose the same information. In particular,
Codex/ChatGPT plan limits are separate from OpenAI API organization usage,
DeepSeek reports a balance rather than a usage window, and Grok's free tier does
not expose progressive usage before its limit is exhausted.

## Ollama Cloud *(experimental)*

The Ollama Cloud tab reads `GET https://ollama.com/api/usage` with an Ollama
Cloud API key. It accepts the session, weekly, and monthly limit buckets the
service actually returns, plus the optional recent activity cost and per-model
request counts. The endpoint is undocumented and has changed shape, so the
widget reports an error if it stops returning recognizable limit data. It does
not guess reset times or convert request counts to tokens. Reading the endpoint
does not run a model.

Older plans expose session and weekly limits; newer plans expose a monthly
credit pool. Both response shapes are supported. On an older plan, Ollama may
report a zero recent activity cost even while quota has been used, so the tab
hides that zero. A positive reported cost and a monthly plan's zero remain
visible. The widget does not change the account's billing plan.

Key order: widget settings → `$OLLAMA_API_KEY` → OpenCode's
`ollama-cloud` API-key entry in `~/.local/share/opencode/auth.json` (or
`$XDG_DATA_HOME/opencode/auth.json` when set, on every OS). OpenCode's `/connect` flow saves that key. Other
OpenCode provider logins remain separate; OpenCode does not aggregate their
account quotas for this widget.

## Claude

On each refresh cycle the widget reads `~/.claude/.credentials.json` to get the OAuth access token, then calls Anthropic's subscription usage endpoint. It prefers the current semantic `limits[]` entries and falls back to the legacy `five_hour` and `seven_day` objects. Only windows with usable data are displayed; legacy five-hour support remains available if Anthropic returns it.

## Antigravity

The widget reads credentials from the `antigravity-usage` CLI configuration (stored in `~/.config/antigravity-usage/` or `~/Library/Application Support/antigravity-usage/`), then calls the Google Cloud Code API to fetch quota information for all available models.

## OpenAI

The OpenAI tab has two independent sections. API usage is fetched from the official OpenAI organization usage endpoint with an API key and summarized over the last 30 days. Codex subscription limits are read through the local Codex app-server, with the authenticated web usage endpoint retained as a compatibility fallback. Windows are classified by their actual duration instead of assuming that `primary` means five hours. Codex plan limits are separate from API billing usage.

## Grok *(free tier tested; paid plans untested)*

The Grok tab reads the Grok CLI login from `~/.grok/auth.json`, fetches the same credit/billing data used by the CLI, and summarizes local CLI sessions from `~/.grok/sessions`. For the tested free tier, the CLI only records the exact token allowance after it returns `free-usage-exhausted`, so the widget can show the confirmed exhausted amount and rolling 24-hour window but cannot infer progressive usage before that event. Paid-plan billing parsing is implemented but remains unverified. An xAI API key is optional; CLI OAuth is the primary source for quota data.

## Kiro

The Kiro tab needs no API key and works with either Kiro tool:

- **kiro-cli** — kiro-cli stores no usage snapshot, but it keeps its login in `~/.local/share/kiro-cli/data.sqlite3`. The widget opens that store read-only and asks the same `getUsageLimits` endpoint the CLI's own `/usage` screen shows. This live figure wins whenever it answers. The CLI's access token lasts about an hour after kiro-cli last ran and the widget deliberately does not renew it (a second refresher could sign the CLI out), so an expired login reports as such until kiro-cli runs again.
- **Kiro IDE** — the IDE caches its last usage payload in `~/.config/Kiro/User/globalStorage/state.vscdb`, read with no network request. It is the fallback, and the only source on a machine without kiro-cli.

Either way the tab shows the credit breakdown, usage percentage, reset date, overage information and plan tier, and feeds the percentage into the 30-day chart history.

## Mistral AI

The widget validates the configured API key against the Mistral API and lists available models, highlighting the one currently active in vibe CLI. Since Mistral exposes no public billing REST API, cost data is sourced locally from vibe CLI session logs (`~/.vibe/logs/session/*/meta.json`): cumulative spend, session count, total tokens, and the last session title are shown in a stats card. The spend bar is scaled against a $50 soft cap and feeds into a 30-day chart. The key is resolved from widget settings → `$MISTRAL_API_KEY` → `~/.vibe/.env` → `~/.config/mistral/api-key`.

## OpenRouter *(untested)*

The widget fetches credit usage and limit from the OpenRouter API using the configured key. The popup shows USD spent, the credit limit (if any), and the account label. The usage bar reflects spend as a percentage of the limit; if no limit is set the bar stays empty.

## Z.AI

The Z.AI tab calls the Z.AI usage quota endpoint with the configured token. It shows the 5-hour token quota, monthly tools quota, reset countdowns, and model details when the API response includes them. The token is resolved from widget settings → `$ZAI_TOKEN` → `$Z_AI_API_KEY` → `~/.config/zai/token` → `~/.zai/token`.

## GitHub Copilot

The GitHub Copilot tab has a **Usage** and a **Stats** sub-tab.

Usage reads premium request consumption from `GET /copilot_internal/user` — the endpoint the Copilot editor plugins themselves call. It answers any Copilot login, and reports the plan's own entitlement, how much of it is left, the plan name, and the date the allowance actually resets, so neither the quota nor the reset day has to be guessed. If that endpoint does not answer (an account without a Copilot quota), the documented `GET /users/{user}/settings/billing/premium_request/usage` billing endpoint is used instead, scaled against the configured quota (default 300); a fine-grained token needs **Plan: read** permission for it. Personal billing only — usage billed through an organization or enterprise is not shown yet.

The credential is resolved from widget settings → `$GITHUB_TOKEN` / `$GH_TOKEN` → `~/.config/github-copilot/token` → the Copilot plugin login in `apps.json` / `hosts.json` (under `$XDG_CONFIG_HOME/github-copilot`, `~/.config/github-copilot` or `~/.copilot`) → `gh auth token`. So a machine that is already signed in to the Copilot CLI, a JetBrains/Neovim Copilot plugin, or the GitHub CLI needs no token pasted at all. A VS Code Copilot login is still not imported: VS Code keeps its session token in encrypted secret storage rather than a reusable file.

Stats aggregates the Copilot CLI's own history from `~/.copilot/session-store.db` — sessions, messages, tool calls, files touched, repositories, active days, streaks, peak hour, longest session and a messages-per-day sparkline. The CLI records no token counts, models or cost, so those tiles are absent rather than shown as zero.

## DeepSeek

The DeepSeek tab calls `GET https://api.deepseek.com/user/balance` with the configured API key. It shows whether the account has sufficient balance for API calls, the primary total balance, and the granted / topped-up split. The key is resolved from widget settings → `$DEEPSEEK_API_KEY` → `~/.config/deepseek/api-key`.

## Kimi / Moonshot AI

The Kimi tab combines two independent sources; either one is enough.

- **Kimi Code plan** — read with the login the `kimi` CLI stores in `~/.kimi-code/credentials/kimi-code.json` (`$KIMI_CODE_HOME` is honoured), from the same `GET https://api.kimi.com/coding/v1/usages` endpoint its `/usage` panel shows (`$KIMI_CODE_BASE_URL` is honoured). It shows each plan window with its reset countdown — the 5-hour and weekly windows are charted — plus the extra-usage wallet when there is one. A plan that is used up is shown as full rather than as an error. The access token is short-lived and the widget does not refresh it (the CLI rotates the pair itself and a second refresher could sign it out), so run `kimi` once when the tab reports an expired login.
- **Moonshot API balance** — `GET https://api.moonshot.ai/v1/users/me/balance` with the available, voucher and cash balances. The key is resolved from widget settings → `$MOONSHOT_API_KEY` / `$KIMI_API_KEY` → `~/.config/moonshot/api-key`.

## Cursor *(free login/stats tested; paid quotas untested)*

The Cursor tab needs no API key and no Cursor IDE: it uses the login `cursor-agent login` stores in `~/.config/cursor/auth.json`, falling back to the Cursor IDE's own login in its `state.vscdb`. With it, the widget calls the two dashboard RPCs the CLI's `/usage` screen uses (`aiserver.v1.DashboardService/GetCurrentPeriodUsage` and `GetPlanInfo` on `api2.cursor.sh`) and shows the included usage for the billing cycle, how much of it went to Auto/Composer versus hand-picked API models, on-demand spend against its limit, the plan name and the cycle's end. Enterprise seats get no plan block from Cursor — the CLI says the same — and the tab reports that instead of a number. A **Stats** sub-tab mirrors the Usage page of cursor.com/dashboard for the current billing cycle: tokens, the usage value Cursor prices it at, requests, conversations, active days, peak hour, a per-day sparkline and a per-model breakdown, from the same `GetAggregatedUsageEvents` / `GetFilteredUsageEvents` calls the dashboard makes (the request list is capped at 500 per refresh; beyond that the per-day figures cover the newest requests). Free/Hobby accounts without an included allowance report **usage unavailable**: the billing endpoint can return all-zero percentages even when agent usage is blocked. These are not an agent-session quota or reset timer, so the widget does not draw meters or record quota history for that response. Dashboard stats remain available. Cursor is opt-in, so enable it under **Settings → Providers**.

## Cline

The Cline tab is **offline**: it reads the session records the Cline CLI writes to `~/.cline/data/sessions/<id>/<id>.json` and keeps only the provider, model, workspace folder name, start and end time, and the token and cost totals (sub-agents included). Prompts, titles, git remotes and transcripts are never read into the result. **Usage** shows today, the last 7 days and the last 30 days — tokens, sessions, and spend when Cline recorded one; a lifetime token count says little on its own, since a token costs very different amounts from model to model. **Stats** keeps the all-time picture: tokens, spend, sessions, active days, streaks, longest session, peak hour, a per-day sparkline, top workspaces and a per-model breakdown. Cline is opt-in, so enable it under **Settings → Providers**.

## Muse

The Muse tab is **fully offline** — it opens no socket, and a test enforces that against the provider's import graph. It reads what Muse Code writes to disk anyway:

| File | What the tab takes from it |
| --- | --- |
| `~/.local/share/muse/sessions/**/session.jsonl` | sessions, subagents, turns, messages, tool calls, per-call token counters, workspace folder name |
| `~/.local/share/muse/sessions/.msp-view-v1/<id>/snapshot-*.json` | the folded counted-once token totals — the same numbers the TUI's `/usage` prints |
| `~/.local/share/muse/model-catalog/*.json` | every model id, its real context limit, and its price list |
| `~/.config/muse/settings.json` | the model the CLI will use next |
| `~/.config/muse/auth.json` | login presence and display name only; the stored tokens are never read |

Because Meta ships the price list to disk, this is the one tab that can price its own usage offline: tokens × the catalog's rates gives the spend estimate, per model and in total, in the catalog's own currency. Nothing is hardcoded — a new Muse model needs no widget update.

**The plan quota is opt-in, because it is the one number here that costs money.** The Current/Weekly windows in the TUI's `/usage` screen are stored nowhere: they arrive only as a `response.subscription_usage` frame riding a live model call, and are absent from the MSP wire schema, the view fold, `session-index.db` and the feature-config cache. The CLI has no `usage`/`status`/`quota` subcommand either, and the frame is the *last* event on the stream — after generation has been paid for — so the call cannot be cut short. (Running `/usage` in the CLI itself stays free: it re-displays what a call you already made told it.)

So reading it from a widget means one minimal model call per refresh — about 12 input and 120 output tokens, `store: false`, cached 30 minutes. At the contributor tier that is a few cents a year; at standard rates closer to ten dollars. [The provider contract](provider-contract.md) says a statistic must not cost the user, so:

- **Off by default.** Out of the box the tab makes no network call at all — `providers/muse.py` imports no networking module, and a test enforces that against its import graph.
- Turn it on in settings → *Muse Quota* (Hyprland has the same toggle, or `WIDGET_MUSE_QUOTA=1` / `museQuota: true`). Both panels state the cost next to the switch, priced from your own model's catalog rates.
- The billed path lives in a separate module (`providers/muse_quota.py`) so it cannot be reached by accident, and every failure falls back to the free local numbers — saying whether the credential was refused or the endpoint was unreachable, rather than calling a working key invalid.
- `MUSE_QUOTA_TTL_SECONDS` (default 1800) bounds how often it can fire, so a 5-minute poll interval cannot become a per-poll model call.

The tab itself is off by default too: enable *Muse* in settings if you use Muse Code.

## Local sessions

The optional Sessions tab (**Settings → Views**) lists recent local activity merged
from Claude Code, Codex, Grok CLI, Cline, OpenCode, Antigravity and Muse: a redacted title
preview, the workspace/session name, active/idle state and recency only — source paths,
raw session IDs, and transcript contents never leave the backend
(`get-ai-usage --sessions`). Claude's title is a clipped opening-prompt preview; raw prompt
text never leaves the backend. Titles can contain prompt text or artifact headings; they are
shortened, not scrubbed of secrets, and may expose sensitive text in the local UI.

Rows for Claude Code, Codex, Grok CLI, Cline, OpenCode and Antigravity carry a ⧉ button that resumes that
exact session in your terminal (`get-ai-usage --open-session <key>`, using each
CLI's own resume flag: `claude --resume`, `codex resume`, `grok --resume`,
`cline --id`, `opencode --session <id>`, `agy --conversation <id>`). The button spawns your `$TERMINAL`, falling back through
ghostty/alacritty/kitty/wezterm/konsole/gnome-terminal/xfce4-terminal/xterm, and
resumes headless in the background if none is found. **Muse has no button** — it
ships no CLI binary here and documents no resume/continue flag, so its rows are
display-only.

Antigravity CLI transcripts are read from
`~/.gemini/antigravity-cli/brain/<id>/.system_generated/logs/transcript.jsonl`;
editor artifact sessions are read from `~/.gemini/antigravity/brain/<id>/*.md`.
The reader examines at most 20,000 lines and 4 MiB per CLI transcript, stopping
at a record larger than 256 KiB. Editor title reads are limited to 2,000 characters.
The Sessions tab displays up to 60 characters of the first user prompt or artifact
heading as plain text. Listing these sessions makes no network requests; choosing
Resume launches `agy`, which can use its own network connections.

Search is backend-powered, not a client-side-only filter. The command
`get-ai-usage --sessions --query <text>` searches all underlying session records
for a non-empty query, using only `provider`, `title`, `sessionName`, `state`,
and `detail`. Empty, whitespace-only, and non-empty queries all return 60-row
pages with exact totals and show **Load more** while another page exists.
`fullTitle`, opaque resume keys, IDs, paths, and transcripts are not searchable or
exposed. The KDE, Hyprland, and Windows frontends request
the backend after their search input debounce, and macOS does the same through
its debounced search task. Existing redaction and opaque resume-key handling
remain unchanged.

## Usage history

Each refresh records the usage values that a provider actually reports into a rolling history of up to 10,000 samples — only when a value moves, plus one sighting an hour, so a flat stretch costs two points rather than one per refresh — used by the chart, spark-lines, burn-rate ETA, and period comparison. Rolling plan windows (Claude, Codex) empty at a known instant, so when the machine was asleep across one the chart replays the drop where it actually happened instead of sloping from the last pre-sleep sample to the first one after wake-up. Most series are percentages; Mistral stores its raw vibe CLI spend and DeepSeek stores its raw balance so their charts retain meaningful units. Existing session and weekly history fields are retained even while a window is unavailable, so five-hour charts can return without migration if providers restore that limit.

History lives in `~/.local/share/ai-usage-widget/usage-history-latest.json`, shared by both frontends, so it survives a full uninstall/reinstall; the widget's Plasma config keeps only a recent tail of it as a first-run fallback, because Plasma rewrites every widget's config whole on each change. You can also manually **Export** (copies the shared file to a timestamped snapshot) and **Import** from the settings panel. If a saved file is unreadable or in an unrecognized format, it's discarded and history starts fresh rather than erroring out.
