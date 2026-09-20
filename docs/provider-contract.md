# Provider data contract (schema version 1)

All five frontends — the KDE Plasma widget (`package/contents/ui`), the
Hyprland/Quickshell shell (`hyprland/`), the Windows tray app (`windows/`), the
macOS menu bar app (`macos/`) and the terminal frontend (`aiusage/render.py`) —
get all of their provider data from a single backend. The Linux frontends run it
through `package/contents/tools/sh/get-ai-usage`; the Windows app, which has no
shell, calls it in-process; the macOS app runs a frozen copy of the same package
as a subprocess.

The macOS app is the one that reads only the **provider-agnostic** half of this
document — `summary`, `quotaWindows`, `chartWindows`, `slots`, `historyValues`
and the shared `details.status` — and nothing under `details` beyond those. That
is deliberate, and it is what makes a third UI codebase affordable: a provider
added to the backend appears there with no Swift change at all. Keep it that
way; see `macos/README.md`.

```
shared provider backend (Python, stdlib only)   package/contents/tools/aiusage
  - credential discovery, HTTP, local-data reads   aiusage/providers/, aiusage/http.py
  - normalization                                  aiusage/normalize/
                 │
                 ▼  thin bash launcher, execs into the package above
  package/contents/tools/sh/get-ai-usage
                 │
          stable JSON model
           ┌─────────┼─────────┐
           ▼         ▼         ▼
      KDE Plasma Quickshell terminal
          UI          UI     aiusage/render.py
   (shared JS: package/contents/code/Format.js, UsageHistory.js)
```

No frontend performs a provider network request, parses a provider response, or
computes a quota percentage or reset window. They map the fields below onto
their own widgets — or columns — and nothing else.

## Invoking the backend

```bash
get-ai-usage --provider claude            # one provider
get-ai-usage --provider claude,openai     # several (KDE: active tab + pins)
get-ai-usage --all                        # every enabled provider (Hyprland)
get-ai-usage --normalize < envelope.json  # replay a raw envelope, no network
get-ai-usage --list                       # known provider ids
get-ai-usage --sessions --query <text>    # search local sessions through the backend
get-ai-usage --sessions --source <ids>      # filter cached sessions by source
```

The terminal frontend renders that same model, either fetching it itself or
reading an envelope on stdin:

```bash
ai-usage-cli                        # table of every enabled provider
ai-usage-cli --compact              # one line, for status bars
get-ai-usage --all | ai-usage-cli   # render a fetched envelope, no second fetch
```

`--all` respects the provider toggles in the shared settings file
(`$XDG_CONFIG_HOME/ai-usage-widget/hyprland-settings.json`, overridable with
`AI_USAGE_CONFIG`). `--provider` fetches exactly what was asked for, because the
Plasma widget keeps its own toggles in the plasmoid configuration.

### Session search

`get-ai-usage --sessions --query <text>` performs session search in the shared
backend. Empty, whitespace-only, and non-empty queries all return 60-session
pages by default; `--limit <n>` and `--offset <n>` select a page. The response
includes the exact `total`, `totalExact`, `offset`, `limit`, and `hasMore`
metadata, so frontends can append another page with **Load more** rather than
loading every match in one response or filtering client-side. A non-empty query
searches the underlying session records rather than filtering only that
60-session result, using only the safe display fields
`provider`, `title`, `sessionName`, `state`, and `detail`. It does not search
`fullTitle`, opaque resume keys, IDs, paths, or transcripts. Claude's `title`
is a clipped opening-prompt preview; raw prompt text never leaves the backend.
Provider readers retain their existing safety limits while supplying records
for the search.

#### Session sources

Session responses retain the existing fields and add the following field:

```json
{
  "sources": [
    { "id": "openai", "label": "Codex" },
    { "id": "opencode", "label": "OpenCode" }
  ]
}
```

`sources` describes only providers that have cached, parsed session rows. It is
returned independently of the active source filter, search text, page, and
page size. Descriptors use this canonical order and these verified IDs and
labels:

| ID | Label |
| --- | --- |
| `cline` | Cline |
| `muse` | Muse |
| `openai` | Codex |
| `grok` | Grok |
| `claude` | Claude Code |
| `opencode` | OpenCode |
| `antigravity` | Antigravity |

The command line accepts `--source <id[,id...]>` and
`--source=<id[,id...]>`, only with `--sessions`. IDs are trimmed, validated
against the registry, deduplicated, and sent in canonical order. Unknown IDs,
empty tokens, and a source option without `--sessions` are errors. Omitting
`--source`, or passing an empty source selection from a frontend, means All.

Multiple source IDs are an OR filter. Text search is then applied to the
matching rows, and `total`, `totalExact`, `offset`, `limit`, and `hasMore` are
computed for that filtered result. Changing sources starts at offset zero.
Refresh and Load more preserve the current source selection and search text;
Load more appends the next page. If a refresh reports that a selected source
is no longer available, frontends clear the stale selection and issue one
query-only All request.

The source list is view-local and is not persisted. In KDE Plasma,
Hyprland, Windows, and macOS, the selector sits beside the Sessions search
field and leaves the title row unchanged. It is hidden when there are no
sources. With one source, it shows that source without an All option. With
multiple sources, All appears first, selecting multiple entries is supported,
and selecting every source normalizes back to All. These frontends share the
same cache, canonical IDs, labels, OR semantics, pagination reset, refresh,
Load more, stale-response, and stale-selection behavior.

`--query-only` reads the already reconciled cache and does not scan provider
stores, build a manifest, or collect new rows. A refresh may be incomplete if
one or more local stores cannot be read. When a valid persisted cache is
available, the backend preserves that cache; if all collectors fail, the
direct fallback may instead contain no rows and no source descriptors. A cache
read failure returns an empty `sources` list and an empty schema-complete
result.

The source metadata and searchable fields remain public, redacted data. They
expose no filesystem paths, raw session IDs, transcripts, full titles, opaque
resume keys, source fingerprints, or credentials. The existing row resume flow
still passes only its opaque `openKey` back to `--open-session`; that key is not
part of source metadata and remains subject to the existing row redaction and
open-session boundary. Existing callers that do not send a source selection
remain compatible; `sources` is additive to the session response.

The session views in KDE, Hyprland, Windows, and macOS send search requests to
this backend instead of filtering locally. Their search inputs are debounced
before a request is started, including the macOS input. Session rows remain
redacted, and existing opaque resume keys are still the only values passed back
to `--open-session`.

API keys come from `WIDGET_*` environment variables (what Plasma passes) or from
the `keys` object of the settings file (what the Hyprland settings page writes).
The environment always wins.

Beyond that, each provider searches the places its vendor's own tooling uses, in a
fixed order: the `WIDGET_*` variable, then one or more conventional environment
variables, then the first readable config file. Where a vendor documents a different
variable name than the one this package grew up with, both are accepted —
`Z_AI_API_KEY` alongside `ZAI_TOKEN`, `KIMI_API_KEY` alongside `MOONSHOT_API_KEY` —
because a provider that knows only one spelling reports "no token configured" at
somebody who did set the key. Several providers additionally borrow a credential another tool already stores:
`~/.config/glm-acp-agent/credentials.json` for Z.AI, `~/.vibe/config.toml` for
Mistral, the Copilot editor/CLI logins and `gh auth token` for Copilot, and —
only on its opt-in quota path — the Muse login store for Muse. A borrowed
credential always ranks last, so an explicit one wins.
`tests/python/test_credentials.py` pins the order with an isolated home.

## Envelope

```json
{
  "schemaVersion": 1,
  "updatedAt": 1785000000,
  "active": "claude",
  "providers": [ { "…provider result…" } ]
}
```

`active` is the first healthy provider, used by the Hyprland shell to pick a tab
when its remembered one disappears.

## Provider result

```json
{
  "id": "claude",
  "label": "Claude",
  "accent": "#cc785c",
  "icon": "claude-color.svg",
  "ok": true,
  "stale": false,
  "error": "",
  "updatedAt": 1785000000,
  "summary":       { "pct": 23, "text": "23%", "detail": "max", "hasChart": true },
  "quotaWindows":  [ { "…window…" } ],
  "slots":         [ { "…panel pill…" } ],
  "historyValues": { "s": 23, "w": 61 },
  "details":       { "…provider specific…" }
}
```

| field | meaning |
| --- | --- |
| `icon` | brand logo filename under `contents/icons/`, `""` when the provider has no artwork yet (frontends fall back to an `accent` dot). Bare filename, not a path — the two frontends sit at different depths and each resolves the directory itself |
| `ok` | the provider produced usable data |
| `stale` | data is missing or older than this refresh |
| `error` | human-readable failure, `""` when healthy. Well-known values: `offline`, `rate limited`, `token expired`, `access denied`, `err <http status>`, `python3 missing` (unlike the others, not retried — see the bash launcher in `tools/sh/get-ai-usage`; the string is fixed vocabulary and means "no Python 3 interpreter could be resolved by `tools/sh/python-interp.sh`", not that the literal `python3` binary is absent) |
| `updatedAt` | epoch seconds when the data was collected |
| `summary.pct` | headline percentage (0–100) |
| `summary.text` | headline string, already formatted (`"23%"`, `"$12.5"`, `"CLI"`) |
| `summary.detail` | plan / account line |
| `summary.hasChart` | false when the provider has no series worth charting |
| `quotaWindows[]` | ordered rows: `key`, `label`, `pct`, `available`, `resetAt`, `resetText`, `detail`, `showMeter`, and optionally `note` |
| `note` | aside shown beside the value. Only meaningful with `showMeter: false`, where `detail` becomes the value itself and would otherwise leave the row no room for context. Optional — a frontend that ignores it loses the aside, nothing else |
| `chartWindows[]` | chart ranges — see below. Empty when the provider has no chartable series |
| `slots[]` | compact panel pills: `pct`, `color`, `text` (null → show the meter), `tooltip` |
| `historyValues` | series keys this provider contributes to the shared usage history |
| `details` | everything the detailed KDE tabs render |

All timestamps are **epoch seconds**, `0` meaning "no reset known".
`resetText` is a preformatted local-time string for frontends that do not want
to format it themselves; the Plasma widget formats from `resetAt` instead so it
keeps following the desktop locale.

### Chart windows

Which history series a provider contributes, and what each chart range means.
Both frontends render the list they are handed rather than keeping their own
copy of the table, so a provider's ranges are defined in exactly one place.

| field | meaning |
| --- | --- |
| `id` | range identifier, persisted as the user's selection (`session`, `codex_weekly`, `kiro`, …) |
| `key` | which `historyValues` series it plots |
| `label` | button text (`5H`, `24H`, `7D`, `30D`) |
| `size` | how much time the chart shows, in ms |
| `granularity` | `5h` / `24h` / `7d`, or `""` for a provider with a single fixed range. Frontends carry it across tabs so switching services keeps the range |
| `raw` | the series holds absolute money rather than percentages, so the chart auto-scales it to its own maximum |
| `resets` | the underlying quota empties periodically |
| `periodMs` | how often it empties (0 when `resets` is false) |
| `resetAt` | epoch seconds of the *next* reset, which anchors every earlier one |

`size` and `periodMs` differ for the 24H range: it plots the five-hour series
over a wider span. `periodMs` and `resetAt` are what let a frontend redraw a
reset that happened while the machine was asleep at the moment it really
happened, instead of sloping from the last pre-sleep sample to the first sample
after wake-up (`UsageHistory.withResets`).

### History series keys

| key | series |
| --- | --- |
| `s` / `w` | Claude 5-hour / 7-day |
| `cp` / `cw` | Codex 5-hour / weekly |
| `ag` | Antigravity average |
| `agg` | Antigravity Gemini |
| `age` | Antigravity External / rest |
| `kr` | Kiro credits |
| `or` | OpenRouter credit usage |
| `mv` | Mistral vibe spend (absolute USD, auto-scaled by the chart) |
| `gr` | Grok credits |
| `za` | Z.AI tokens |
| `gh` | Copilot premium requests |
| `ds` | DeepSeek balance (absolute) |
| `km` | Kimi / Moonshot balance (absolute) |
| `kc` / `kcw` | Kimi Code 5-hour / weekly plan pct |
| `cu` | Cursor included usage |
| `mu` | Muse tokens (absolute) |
| `mc` / `mw` | Muse Current / Weekly plan pct — only present when the opt-in quota is switched on |

### Credentials

Credentials and access tokens are **never** part of a result. The backend
exposes presence only: `details.hasKey` and `details.keyValid` for
single-credential providers, the specific `details.hasOAuth` /
`details.hasAdminKey` / `details.hasApiKey` / `details.codexLoggedIn` for the
two that accept more than one, and `details.hasLogin` for Muse, whose default
path needs no credential at all. A contract test asserts that no fixture secret
can appear anywhere in a result.

Most helpers now report presence rather than echoing the credential back, so a
token never crosses a process boundary at all. The exceptions are
`get-openai-usage` and `get-grok-usage`, whose credentials the backend itself
needs in order to call the plan endpoints.

## `details` per provider

**claude** — `hasOAuth`, `hasAdminKey`, `subscriptionType`, `rateLimitTier`,
`organizationUuid`, `effortLevel`, `autoDream`, `session`/`weekly`
(`available`, `pct`, `resetAt`, `tokensUsed`, `tokenLimit`), `scopedWeekly`
(one entry per `weekly_scoped` limit — a narrower week that runs alongside the
all-models one, such as Fable; `key`, `label`, `model`, `available`, `pct`,
`resetAt`, and a matching `quotaWindows` row), `extraTokens`,
`extraUsage` (`enabled`, `limit`, `used`, `pct`, `currency`),
`organizationUsage` (`models` keyed by model with `input_tokens`,
`output_tokens`, `cost_usd`, `priced`, plus `totalInputTokens`,
`totalOutputTokens`, `totalCostUSD`), `stats`, `status`.

**openai** — `hasApiKey`, `codexLoggedIn`, `email`, `planType`, `orgId`,
`accountId`, `authMode`, `codex` (`available`, `limitReached`, `session`,
`weekly`, `additional[]` with `name`, `limitReached`, `session`, `weekly`),
`organizationUsage`, `stats` (plus `model` and `effortLevel` from the newest
rollout), `status`.

**antigravity** — `email`, `planType`, `promptCreditsMonthly`,
`promptCreditsAvailable`, `pct`, `googlePct`, `externalPct`, `resetAt`,
`models` keyed by model id (`displayName`, `usedPct`, `resetTime`, `resetAt`,
`isExhausted`, `hasQuota`), `groups[]` (`key`, `label`, `usedPct`, `resetAt`,
`isExhausted`, `models`).

**kiro** — `available`, `planType`, `displayName`, `displayNamePlural`,
`currentUsage`, `usageLimit`, `pct`, `remaining`, `currentOverages`,
`overageCap`, `overageCharges`, `overageRate`, `currencyCode`,
`currencySymbol`, `resetAt`, `source` (`cli` = live from the kiro-cli login,
`ide` = the Kiro IDE's cached snapshot).

**mistral** — `hasKey`, `keyValid`, `availableModels`, `vibe` (`sessionCount`,
`totalCost`, `totalTokens`, `promptTokens`, `completionTokens`, `totalSteps`,
`toolOk`, `toolFail`, `activeModel`, `recent`), `status`.

**openrouter** — `hasKey`, `keyValid`, `label`, `usageUSD`, `limitUSD`
(null = unlimited), `limitRemainingUSD`, `isFreeTier`, `rateLimit`, `status`.

**grok** — `hasKey`, `loggedIn`, `pct`, `used`, `monthlyLimit`, `email`,
`teamName`, `tierId`, `billingPeriodEnd`, `sessionCount`, `totalTokens`,
`totalToolCalls`, `hasBilling`, `quotaKind`, `quotaWindow`, `quotaExhausted`,
`billingError`.

**zai** — `hasKey`, `keyValid`, `level`, `token` (`pct`, `used`, `limit`,
`resetAt`), `tokenLong` (`pct`, `resetAt`), `tools` (`pct`, `remaining`,
`resetAt`), `models`, `today` (`available`, `date`, `rollsOverAt`, `tokens`,
`calls`, `models[]` with `name`/`tokens`, `tools` with `search`/`reader`/
`zread`).

`today` comes from two further monitor endpoints, `model-usage` and
`tool-usage`, both taking `startTime`/`endTime` in `yyyy-MM-dd HH:mm:ss` —
they reject ISO-8601 with a `T`. The bounds are the plain **local calendar
date**, sent without timezone conversion, because that is what the vendor's
dashboard does and matching it is the whole point of the figure (verified
digit-for-digit against a live account). The service applies those bounds on
its own clock, which runs ahead of Europe, so the day being summed is shifted
and the total stops growing before local midnight; `rollsOverAt` carries the
date change so a total that has stopped moving does not read as stuck. Neither
call can fail the provider: the quota windows are the point, and a missing
statistic must not cost them.

**copilot** — `hasKey`, `keyValid`, `username`, `used`, `quota`, `pct`,
`unlimited`, `plan`, `resetAt`, `stats`. The quota and the reset day come from
the plan itself when `/copilot_internal/user` answers (the endpoint the editors
use, which any Copilot login can read); the documented billing endpoint is the
fallback for a token that carries billing scope, and only there does the
configured quota and a guessed first-of-next-month reset apply.

**deepseek** — `hasKey`, `keyValid`, `isAvailable`, `balances`,
`primaryCurrency`, `primaryTotal`, `primaryGranted`, `primaryToppedUp`,
`currency`, `symbol`.

**kimi** — `hasKey`, `keyValid`, `balanceError`, `availableBalance`,
`voucherBalance`, `cashBalance`, `currency`, `codePlan` (`loggedIn`,
`available`, `exhausted`, `message`, `error`, `windows[]` with `label`, `name`,
`seconds`, `pct`, `used`, `limit`, `resetAt`, and `booster` — `balance`, `total`,
`monthlyLimit`, `monthlyUsed`, `currency` — or null). `label` is the English
wording; `name` (the vendor's own, when it sends one) and `seconds` let a
translated frontend word the label itself. The Moonshot balance
and the Kimi Code plan are independent; the provider is healthy when either
answers, and a plan Kimi reports as used up (HTTP 429 `resource_exhausted`)
is a full window, not an error.

**cursor** — `loggedIn`, `source` (`cli` / `ide`), `planName`, `price`,
`totalPct`, `autoPct`, `apiPct`, `hasSplit`, `includedSpend`, `limit`,
`bonusSpend`, `remaining` (USD), `resetAt`, `cycleStartAt`, `onDemandUsed`,
`onDemandLimit`, `displayMessage`, `nextUpgrade` (`name`, `price`), `stats`
(the shared stats shape, for the current billing cycle: `totalTokens`,
`totalCostUSD`, `totalRequests`, `totalSessions` = distinct conversations,
`models` keyed by model with `input`/`output`/`cached`/`cacheWrite`/`total`/
`cost`/`requests`, `dailySeries` with `dailyUnit` `tokens` or `requests`, and
`partial` when the paged request list stopped short). It comes from the
dashboard's `GetAggregatedUsageEvents` and `GetFilteredUsageEvents`; the
backend reduces each request to model, tokens, cost, time and a conversation
ordinal, so no account or conversation identifier reaches the envelope.

**cline** — `stats` (the shared stats shape, all time, from the CLI's local
session records: `totalTokens`, `totalCostUSD`, `totalSessions`, `models`
keyed by model with `input`/`output`/`cached`/`cacheWrite`/`total`/`cost`/
`sessions`, `topWorkspaces`, `dailySeries`) and `periods[]` (`key` —
`cline_today` / `cline_7d` / `cline_30d` — `label`, `sessions`, `tokens`,
`cost`). "Today" starts at local midnight; the other two are rolling. No
network request is made.

**muse** — `hasLogin`, `email`, `fullName` (display identity from the CLI
login store), `current` / `weekly` (`available`, `pct`, `resetAt`),
`quotaError`, `stats`. Deliberately thin: every total, the model and the
currency live in `stats` and are read from there, so no number appears twice in
one envelope.

Muse is the only provider whose quota cannot be read for free, and the only one
that can price itself. Both follow from the same fact: Meta publishes the
Current/Weekly plan windows solely as a `response.subscription_usage` frame on a
live model call — they are in neither the MSP wire schema, the view fold,
`session-index.db` nor the feature-config cache, and the CLI has no
`usage`/`status`/`quota` subcommand.

The provider is therefore split in two, and the rule above decides which half
runs by default:

- `providers/muse.py` is the default path and imports no networking module at
  all — a test asserts that against its import graph, not its text. It reads
  what Muse writes to disk anyway: session logs, the folded counted-once totals
  under `.msp-view-v1/`, the login store (presence and display name only), the
  selected model in `settings.json`, and the model catalog cache. That
  catalog's own `cost` rows are what make the offline spend estimate possible,
  and they are why no model id, context window or price is hardcoded anywhere.
- `providers/muse_quota.py` is the opt-in half: one minimal streaming call per
  `MUSE_QUOTA_TTL_SECONDS` (default 1800), gated on `WIDGET_MUSE_QUOTA`, which
  `config.muse_quota_enabled()` defaults to off. Separate module so the free
  path cannot reach a credential or a socket; its `refresh_cost()` prices one
  refresh from the user's own catalog so both frontends can state the cost
  beside the switch.

`quotaError` distinguishes `disabled`, `no-credential`, `no-model`, `rejected`
and `unreachable` — a flaky network must never be reported as a bad key — and
any quota failure degrades to the free local numbers rather than failing the
provider. A quota that did come back renders even when the local logs are
empty: paying for a window and then discarding it would be the worst of both.

### Shared sub-objects

`stats` (Claude Code, Codex CLI, Copilot CLI and Muse Code): `available`,
`totalMessages`, `totalSessions`, `totalTokens`, `totalToolCalls`,
`favoriteModel`, `firstDate`, `computedDate`, `activeDays`, `spanDays`,
`currentStreak`, `longestStreak`, `longestSessionMs`,
`longestSessionMessages`, `peakHour`, `models`, `dailyTokens[]` (`date`,
`total`), plus `dailySeries[]` and `dailyUnit` — the per-day series the
frontends draw, named separately because not every CLI counts tokens. Claude
adds `version`, `totalCostUSD` and `totalWebSearches`; Codex adds `model` and
`effortLevel`; Copilot (which records no tokens, models or cost) adds
`totalFiles`, `totalRepositories` and `topRepositories[]` (`name`, `sessions`)
and reports `dailyUnit: "messages"`; Muse adds `subagentSessions`,
`totalInputTokens`, `totalOutputTokens`, `totalCachedTokens`,
`totalReasoningTokens`, `totalCostUSD` (priced offline from the local
catalog), `totalModelCalls`, `contextWindow`, `workspaceCount`,
`topWorkspaces[]` (`name`, `sessions`), `model` and `currency`.

`status` — present on every provider, attached by `normalize()` itself:
`indicator` (`none` | `minor` | `major` | `critical`, or `""` when there is
no live reading), `description`, `components[]`, `incidents[]`,
`latestUpdate` and `url` (the human status page, `""` when the provider has
none). Which page belongs to which provider, and which feed it publishes,
is the `STATUS_PAGES` table in `contract.py`: Atlassian Statuspage
(`/api/v2/summary.json` — Claude, OpenAI, Cursor, Kimi, and Copilot scoped
to GitHub's `Copilot*` components) or Gatus (`/api/v1/endpoints/statuses` —
Cline). Pages with no feed (Antigravity, Grok, DeepSeek, Mistral,
OpenRouter) come through as `indicator: ""` plus a `url`, which the
frontends render as a plain link. Feeds are cached on disk for
`AI_USAGE_STATUS_TTL` seconds (default 300) so a fast poll interval does not
hammer them.

## Shared frontend code

Three things are identical in both QML frontends and live in
`package/contents/code/` so they cannot drift (the terminal frontend keeps no
history and formats its own countdowns from `resetText`):

- `Format.js` — countdown formatting (`countdown`, `countdownFromEpoch`).
- `UsageHistory.js` — collecting `historyValues` from a response, the rolling
  series and the state machine that saves it, migrating legacy points, and
  replaying quota resets.

`~/.local/share/ai-usage-widget/usage-history-latest.json` is the store, shared
by both frontends, and `tools/sh/history-io` owns every access to it. It holds the
newest `DEFAULT_LIMIT` samples — 10,000, about 40 bytes each, which is a month of
unbroken 5-minute polling and most of a year on a machine that sleeps. A save
carries only new samples, so the size costs nothing per poll; `export` copies the
file rather than taking the series from a frontend, because a single command-line
argument is capped at 128 KB and a full series passes that well before the point
cap does. The Plasma widget's config keeps a 500-sample tail of the same series,
which is also what bounds the startup seed. A save
(`history-io autosave`) takes an `flock`, unions the payload into whatever is
already on disk, replaces the file by rename, and prints the merged series back
to the caller. A lock it cannot take is an error, not something to go ahead
without: the merge is a read-modify-write, so racing the holder would drop one
side's points. The frontend keeps its batch and retries on the next poll. That makes a save a merge rather than an overwrite, so two
frontends — or two Plasma widget instances, which are two writers too — converge
instead of clobbering each other, and each one picks up the other's points on
its next poll without a separate read. The rename matters because a reader that
catches a partial write treats the file as corrupt and *deletes* it.

The union has no way to tell which of two values for one key is the newer one, so
it gives the payload precedence — which makes what a payload may hold the whole
contract. There are two kinds, and `history-io` has an entry point for each:

- `autosave` — **readings the frontend has just taken**, and only those keys.
  Asserted, which is right because nothing anywhere is newer for them. A whole
  series would also carry that frontend's copies of the *other* one's points,
  with the same precedence, and roll them back.
- `seed` — **a series the frontend restored** rather than measured: the widget
  config it starts from, a snapshot the user imported. Offered, not asserted:
  the file keeps its own values and gains only the keys it lacks. It can predate
  what is on disk, and a frontend cannot tell — its copy of the file is from
  whenever it last saved, and the other frontend may have written since. So the
  comparison happens inside the lock, where both sides are visible at once,
  rather than out in the frontend against a copy that may already be behind.

A third rule keeps the two apart: **a point is only ever patched by the writer
that created it.** `UsageHistory.record` patches the caller's own last point and
appends otherwise. The timestamp *is* that ownership, so two frontends polling in
the same millisecond both claim the point and its value flips between their
readings until the merge window passes — left as it is, since closing it means a
writer id in every point for a one-point wobble at roughly 0.1% a day.

**Only changes are stored.** Most readings repeat the one before, so `record`
keeps a flat run as its first sighting, its last sighting before the value moves,
and one sighting an hour. The chart joins samples with curves, and a run's two
ends are what keep the line flat until the change instead of ramping across the
whole run; the hourly one bounds that for a run that ends while nothing is
watching. The latest reading is shown but not saved until its run ends (the
store's `tail`), so the line still reaches the present. The burn rate and the
chart's pulse fit the series resampled every five minutes (`slopePerHour`), not
the stored points, so they do not move with how a run happens to be stored.

The state machine over all this — the two lanes, one batch in flight, what an
answer means — is `UsageHistory.js` too, shared rather than written out twice in
QML, where only a running Plasma session or Quickshell could exercise it. Each
frontend is left with the transport and the timers. One batch is in flight at a
time, because the answer replaces the series with what is on disk and two could
land out of order; anything recorded meanwhile waits its turn. A batch that fails
goes back to its lane and waits for the *next poll* — history-io leaves the file
untouched when it cannot merge, so nothing is lost, and resending immediately
would only fail the same way as fast as the shell can fork.

Neither frontend writes the file before it has read it: the startup read is
asynchronous while the poll timer fires immediately, so a write that got in
first would drop everything recorded under the other frontend. The file wins over
the restored copy for everything it knows; what it does not know follows as a
seed.

The Plasma widget also keeps a copy in its widget config, but only as a backup
to seed a fresh install — it is read at startup and flushed on a slow timer,
because Plasma rewrites `plasma-org.kde.plasma.desktop-appletsrc` (every
widget's config) whole on each change and the series runs to 30-100 KiB.

The union therefore exists twice: in QML (`UsageHistory.union`) for the startup
restore, and in Python (`aiusage/history.py`) for the on-disk merge.
`tests/shared-code.test.js` replays the same cases through both and compares the
JSON byte for byte, so they cannot drift.

A save costs about 60 ms of CPU, nearly all of it process startup — at the
default 300 s poll that is 0.02% of one core, or ~17 s of CPU per day.

## Testing

`tests/python/test_fixtures.py` replays `tests/fixtures/*.json` — raw envelopes for
success, missing credentials, malformed responses, offline and rate-limited
states — through the in-process normalizers, so the whole provider matrix is
covered without network access and runs on Windows.

`test_provider_values.py` preserves the provider-specific expectations.
`test_collect.py` and `test_muse.py` run the real collectors against the response
hooks, local log files and SQLite stores. Recorded bodies formerly embedded in
the shell suite live in `tests/fixtures/*-response.json`. Synthetic settings and
session logs are created by the tests. The raw `muse-quota.json`
response goes through the quota reader instead of the envelope normalizer.

`tests/python/test_cli.py` renders each of those fixtures through the terminal
frontend, asserting among other things that a provider which cannot report still
produces a row — a state the graphical frontends show as a tab or a pill, and
which a table could silently drop instead.

`tests/shared-code.test.js` covers the shared frontend modules. Run them all
with `make test`.

## Changing the contract

Adding a field is backwards compatible. Removing or repurposing one is not:
bump `SCHEMA_VERSION` in `package/contents/tools/aiusage/contract.py`, update
this document, and update every frontend in the same change — except that
the macOS app needs no change for a new provider, only for a new *field*.
