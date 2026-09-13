#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
#
# Rendering tests for the terminal frontend.
#
# Every case renders a recorded envelope through `ai-usage-cli`, so the whole
# provider matrix — including the states that carry no quota windows at all —
# is covered without touching the network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/package/contents/tools/sh/get-ai-usage"
CLI="$ROOT/package/contents/tools/sh/ai-usage-cli"
FIXTURES="$ROOT/tests/fixtures"

failures=0
checks=0

fail() {
    printf 'FAIL %s: %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
}

# Wrap one normalized provider object into an envelope the frontend can render.
envelope_for() {
    "$BACKEND" --normalize <"$FIXTURES/$1.json" | jq -s '{schemaVersion: 1, updatedAt: 0, active: "", providers: .}'
}

# renders <fixture> <description> <ere> [cli args...]
renders() {
    local fixture="$1" description="$2" pattern="$3" out
    shift 3
    checks=$((checks + 1))
    if ! out="$(envelope_for "$fixture" | "$CLI" "$@" 2>&1)"; then
        fail "$fixture" "frontend errored: $out"
        return
    fi
    if ! printf '%s\n' "$out" | grep -qE "$pattern"; then
        fail "$fixture" "$description
  wanted: $pattern
  got:    $out"
    fi
}

# renders_not <fixture> <description> <ere> [cli args...]
renders_not() {
    local fixture="$1" description="$2" pattern="$3" out
    shift 3
    checks=$((checks + 1))
    if ! out="$(envelope_for "$fixture" | "$CLI" "$@" 2>&1)"; then
        fail "$fixture" "frontend errored: $out"
        return
    fi
    if printf '%s\n' "$out" | grep -qE "$pattern"; then
        fail "$fixture" "$description
  unwanted: $pattern
  got:      $out"
    fi
}

# ── Invariants every fixture must satisfy ───────────────────────────────────

for fixture in "$FIXTURES"/*.json; do
    name="$(basename "$fixture" .json)"
    label="$(envelope_for "$name" | jq -r '.providers[0].label // ""')"

    # The headline reason a CLI exists: a provider that cannot report must still
    # appear. Dropping the row would make a missing key look like a provider the
    # user never enabled.
    renders "$name" "names the provider" "$(printf '%s' "$label" | sed 's/[.[\*^$]/\\&/g')" --color never

    # Same rule the backend contract test enforces: no credential may reach a
    # frontend, and rendering must not become the exception.
    renders_not "$name" "never prints a credential" \
        'secret|sk-ant-|sk-oauth|gh-secret|zai-secret|xai-secret|ds-secret|or-secret|codex-secret' --color never

    # Trailing whitespace makes copied output ugly and breaks naive diffing.
    renders_not "$name" "leaves no trailing whitespace" ' +$' --color never

    renders_not "$name" "emits no escapes with --color never" $'\033' --color never
    renders_not "$name" "emits no box drawing with --ascii" '[^[:print:][:space:]]' --color never --ascii
    renders "$name" "compact mode prints the provider" "$(printf '%s' "$label" | sed 's/[.[\*^$]/\\&/g')" --compact --color never
done

# ── Error and stale states are visible, not swallowed ───────────────────────

renders claude-missing-credentials "surfaces a missing login"    'not logged in' --color never
renders claude-offline            "surfaces an offline provider" 'offline' --color never
renders claude-rate-limited       "surfaces a rate limit"        'rate limited' --color never
renders zai-invalid-token         "surfaces an invalid token"    'Invalid Z.AI token' --color never
renders antigravity-not-running   "surfaces a dead IDE"          'not running' --color never

# ── Values ──────────────────────────────────────────────────────────────────

renders claude-success   "renders both Claude windows"     '5-hour session' --color never
renders claude-success   "renders the weekly percentage"   '61%' --color never
renders claude-success   "draws a meter"                   '\[[#█]+[-░]*\]' --color never
renders kimi-success     "renders money without a meter"   'Available balance +\$' --color never
renders muse-success     "renders the lifetime token row"  'Tokens +150k' --color never
renders muse-success     "renders the offline spend row"   'Spend \(est\.\) +\$0\.01' --color never
renders_not muse-success "draws no meter without a quota"  'Tokens +\[' --color never
renders kimi-success     "draws no meter for a balance"    '^Kimi' --color never
renders_not kimi-success "omits the meter on a balance row" 'Available balance +\[' --color never
renders openrouter-unlimited "keeps the window note"       'unlimited' --color never
# The value belongs in the usage column and the call count beside it, so a
# meterless row keeps its aside instead of cramming both into one cell.
renders zai-today        "prints the day total as a value" 'Today \(Aug 11\) +41\.18M tokens +370 calls' --color never
renders_not zai-today    "draws no meter for a day total" 'Today +\[' --color never

# ── Compact mode ────────────────────────────────────────────────────────────

checks=$((checks + 1))
lines="$(envelope_for claude-success | "$CLI" --compact --color never | wc -l)"
[ "$lines" = "1" ] || fail claude-success "compact mode must be one line, got $lines"

checks=$((checks + 1))
compact="$(envelope_for kimi-success | "$CLI" --compact --color never)"
case "$compact" in
    *'$'*) ;;
    *) fail kimi-success "compact mode must use summary.text, got: $compact" ;;
esac

checks=$((checks + 1))
compact="$(envelope_for muse-success | "$CLI" --compact --color never)"
case "$compact" in
    *'150k'*) ;;
    *) fail muse-success "compact mode must use summary.text, got: $compact" ;;
esac

# ── Colour ──────────────────────────────────────────────────────────────────

checks=$((checks + 1))
if ! envelope_for claude-success | "$CLI" --color always | grep -q $'\033'; then
    fail claude-success "--color always must emit escapes"
fi

checks=$((checks + 1))
if envelope_for claude-success | NO_COLOR=1 "$CLI" --color auto | grep -q $'\033'; then
    fail claude-success "NO_COLOR must disable colour"
fi

# ── Argument handling ───────────────────────────────────────────────────────

checks=$((checks + 1))
if envelope_for claude-success | "$CLI" --provider nope >/dev/null 2>&1; then
    fail cli "an unknown provider id must fail"
fi

checks=$((checks + 1))
if envelope_for claude-success | "$CLI" --color sideways >/dev/null 2>&1; then
    fail cli "an invalid --color value must fail"
fi

checks=$((checks + 1))
if printf 'not json' | "$CLI" >/dev/null 2>&1; then
    fail cli "a malformed envelope on stdin must fail"
fi

checks=$((checks + 1))
if ! envelope_for claude-success | "$CLI" --json | jq -e '.providers[0].id == "claude"' >/dev/null 2>&1; then
    fail cli "--json must pass the envelope through"
fi

checks=$((checks + 1))
if ! "$CLI" --list </dev/null | grep -qx claude; then
    fail cli "--list must print the provider ids"
fi

# A selection applied to an envelope must filter it rather than refetch.
checks=$((checks + 1))
if envelope_for claude-success | "$CLI" --provider zai --color never | grep -q Claude; then
    fail cli "--provider must filter an envelope from stdin"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

if [ "$failures" -gt 0 ]; then
    printf '\n%d of %d checks failed\n' "$failures" "$checks" >&2
    exit 1
fi
printf 'ai-usage-cli: %d checks passed\n' "$checks"
