#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
set -euo pipefail

# Credential discovery decides whether a provider renders a number or the
# "no token configured" row, and it is the one part of a provider that never
# shows up in the envelope (docs/provider-contract.md: credentials are never
# part of a result). That makes a wrong precedence invisible to the contract
# tests — a key can sit on disk, valid, while the widget claims there is none.
#
# Each case builds a pristine HOME, plants exactly one credential, and asserts
# which one the resolver settles on.

repo="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$repo/package/contents/tools/sh/get-ai-usage"

tmp="$(mktemp -d)"
trap 'case "$tmp" in /tmp/*) rm -rf -- "$tmp" ;; esac' EXIT

failures=0
checks=0

# resolve <provider-function> — runs the real resolver against a clean HOME and
# whatever variables the caller exported, and prints what it found.
resolve() {
    local fn="$1"
    HOME="$tmp/home" PYTHONPATH="$repo/package/contents/tools" python3 -c "
from aiusage.providers.${fn%%:*} import ${fn##*:}
print(${fn##*:}())"
}

# expect <description> <expected> <provider-function>
expect() {
    local description="$1" expected="$2" fn="$3" got
    checks=$((checks + 1))
    got="$(resolve "$fn")"
    if [ "$got" != "$expected" ]; then
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$description" "$expected" "$got" >&2
        failures=$((failures + 1))
    fi
}

# expect_expr <description> <expected> <import line> <expression> — for the
# resolvers that return a record rather than a bare string.
expect_expr() {
    local description="$1" expected="$2" import="$3" expr="$4" got
    checks=$((checks + 1))
    got="$(HOME="$tmp/home" PYTHONPATH="$repo/package/contents/tools" python3 -c "
$import
print($expr)")"
    if [ "$got" != "$expected" ]; then
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$description" "$expected" "$got" >&2
        failures=$((failures + 1))
    fi
}

fresh_home() {
    rm -rf "$tmp/home"
    mkdir -p "$tmp/home/.config"
}

# ── Z.AI ────────────────────────────────────────────────────────────────────

fresh_home
expect "no credential anywhere yields an empty key" "" "zai:_zai_key"

fresh_home
mkdir -p "$tmp/home/.config/zai"
printf 'from-config-file\n' >"$tmp/home/.config/zai/token"
expect "reads the conventional ~/.config/zai/token" "from-config-file" "zai:_zai_key"

fresh_home
mkdir -p "$tmp/home/.zai"
printf 'from-dot-zai\n' >"$tmp/home/.zai/token"
expect "falls back to ~/.zai/token" "from-dot-zai" "zai:_zai_key"

# The vendor documents Z_AI_API_KEY; this tool has always read ZAI_TOKEN. A
# user who followed z.ai's own docs used to get "no token configured".
fresh_home
Z_AI_API_KEY=from-vendor-env expect "accepts the vendor's Z_AI_API_KEY spelling" \
    "from-vendor-env" "zai:_zai_key"

fresh_home
ZAI_TOKEN=from-native-env Z_AI_API_KEY=from-vendor-env \
    expect "prefers this tool's own ZAI_TOKEN over the vendor spelling" \
    "from-native-env" "zai:_zai_key"

# glm-acp-agent --setup is where a lot of people paste the coding-plan key.
fresh_home
mkdir -p "$tmp/home/.config/glm-acp-agent"
printf '{"z_ai_api_key": "from-acp-agent"}\n' >"$tmp/home/.config/glm-acp-agent/credentials.json"
expect "reads the glm-acp-agent credentials file" "from-acp-agent" "zai:_zai_key"

mkdir -p "$tmp/home/.config/zai"
printf 'from-config-file\n' >"$tmp/home/.config/zai/token"
expect "an explicit token still beats the borrowed one" "from-config-file" "zai:_zai_key"

fresh_home
mkdir -p "$tmp/home/.config/glm-acp-agent"
printf 'not json at all\n' >"$tmp/home/.config/glm-acp-agent/credentials.json"
expect "a corrupt credentials file is empty, not an exception" "" "zai:_zai_key"

fresh_home
mkdir -p "$tmp/home/.config/glm-acp-agent"
printf '{"z_ai_api_key": null}\n' >"$tmp/home/.config/glm-acp-agent/credentials.json"
expect "a null key is treated as absent" "" "zai:_zai_key"

# ── Moonshot / Kimi ─────────────────────────────────────────────────────────

fresh_home
expect "no Moonshot credential yields an empty key" "" "moonshot:_moonshot_key"

fresh_home
KIMI_API_KEY=from-kimi-env expect "still accepts the KIMI_API_KEY spelling" \
    "from-kimi-env" "moonshot:_moonshot_key"

fresh_home
MOONSHOT_API_KEY=from-moonshot-env KIMI_API_KEY=from-kimi-env \
    expect "prefers MOONSHOT_API_KEY over KIMI_API_KEY" \
    "from-moonshot-env" "moonshot:_moonshot_key"

fresh_home
mkdir -p "$tmp/home/.config/moonshot"
printf 'from-moonshot-file\n' >"$tmp/home/.config/moonshot/api-key"
KIMI_API_KEY=from-kimi-env expect "an environment key outranks the file" \
    "from-kimi-env" "moonshot:_moonshot_key"

fresh_home
mkdir -p "$tmp/home/.config/kimi"
printf 'from-kimi-file\n' >"$tmp/home/.config/kimi/api-key"
expect "reads ~/.config/kimi/api-key" "from-kimi-file" "moonshot:_moonshot_key"

# ── GitHub Copilot ──────────────────────────────────────────────────────────
#
# Copilot is the one provider that borrows a login it did not write: the editor
# plugins' apps.json, the Copilot CLI's directory, and `gh auth token`. A stub
# gh on PATH stands in for the real one — the token it prints lives in the
# system keyring on a real install, so there is no file to plant instead.

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

# gh_stub <token>, or no argument for "gh is installed but not logged in".
gh_stub() {
    if [ $# -eq 0 ]; then
        printf '#!/bin/sh\nexit 1\n' >"$fake_bin/gh"
    else
        printf '#!/bin/sh\nprintf %%s\\\\n "%s"\n' "$1" >"$fake_bin/gh"
    fi
    chmod +x "$fake_bin/gh"
}

# copilot_token — prints "<token>" or "<token>|<username>", so precedence and
# the username a borrowed login carries are both visible.
copilot_token() {
    HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" PATH="$fake_bin:$PATH" \
        PYTHONPATH="$repo/package/contents/tools" python3 -c "
from aiusage.providers.copilot import _github_token
token, user = _github_token()
print(token + ('|' + user if user else ''))"
}

# expect_copilot <description> <expected>
expect_copilot() {
    local description="$1" expected="$2" got
    checks=$((checks + 1))
    got="$(copilot_token)"
    if [ "$got" != "$expected" ]; then
        printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$description" "$expected" "$got" >&2
        failures=$((failures + 1))
    fi
}

fresh_home
gh_stub
expect_copilot "no GitHub login anywhere yields an empty token" ""

fresh_home
gh_stub "from-gh-cli"
expect_copilot "falls back to the gh CLI" "from-gh-cli"

# The Copilot CLI keeps its token in the keyring but its login in config.json,
# which saves the /user request the billing endpoint would otherwise need.
mkdir -p "$tmp/home/.copilot"
cat >"$tmp/home/.copilot/config.json" <<'JSON'
// User settings belong in settings.json.
{"lastLoggedInUser": {"host": "https://github.com", "login": "octocat"}}
JSON
expect_copilot "picks up the Copilot CLI login next to the gh token" "from-gh-cli|octocat"

fresh_home
gh_stub "from-gh-cli"
mkdir -p "$tmp/home/.config/github-copilot"
cat >"$tmp/home/.config/github-copilot/apps.json" <<'JSON'
{"github.com:Iv1.b507a08c87ecfe98": {"user": "octocat", "oauth_token": "from-apps-json"}}
JSON
expect_copilot "prefers the editor plugin login over the gh CLI" "from-apps-json|octocat"

# Enterprise and dotcom logins sit side by side; the usage endpoints are
# dotcom-only, so github.com has to win regardless of key order.
fresh_home
gh_stub
mkdir -p "$tmp/home/.config/github-copilot"
cat >"$tmp/home/.config/github-copilot/hosts.json" <<'JSON'
{"ghe.example.com:Iv1.aaa": {"user": "ghe-user", "oauth_token": "from-enterprise"},
 "github.com:Iv1.bbb": {"user": "octocat", "oauth_token": "from-dotcom"}}
JSON
expect_copilot "prefers the github.com login over an enterprise one" "from-dotcom|octocat"

# "github.company.com" starts with the ten characters of "github.com", so the
# host has to be compared whole and not as a prefix.
fresh_home
gh_stub
mkdir -p "$tmp/home/.config/github-copilot"
cat >"$tmp/home/.config/github-copilot/hosts.json" <<'JSON'
{"github.company.com:Iv1.aaa": {"user": "ghe-user", "oauth_token": "from-lookalike-host"},
 "github.com:Iv1.bbb": {"user": "octocat", "oauth_token": "from-dotcom"}}
JSON
expect_copilot "does not mistake github.company.com for github.com" "from-dotcom|octocat"

fresh_home
gh_stub "from-gh-cli"
mkdir -p "$tmp/home/.config/github-copilot"
printf 'from-token-file\n' >"$tmp/home/.config/github-copilot/token"
expect_copilot "an explicit token file outranks every borrowed login" "from-token-file"

fresh_home
gh_stub "from-gh-cli"
GITHUB_TOKEN=from-env expect_copilot "the environment outranks the gh CLI" "from-env"

fresh_home
gh_stub
mkdir -p "$tmp/home/.config/github-copilot"
printf 'not json at all\n' >"$tmp/home/.config/github-copilot/apps.json"
expect_copilot "a corrupt apps.json is empty, not an exception" ""

# ── Muse ────────────────────────────────────────────────────────────────────
#
# Muse has no credential to resolve: the provider makes no request, so it reads
# presence and identity only and never touches the stored tokens. What must
# hold is that a missing or broken store is "not logged in" rather than a
# traceback, and that the model comes from the CLI's settings.

fresh_home
MUSE_AUTH_PATH="$tmp/nope.json" expect "a missing auth store means no login" \
    "False" "muse:auth_presence"

fresh_home
printf '{"providers": {"meta": {"mechanism": "oauth"}}}' >"$tmp/muse-auth.json"
MUSE_AUTH_PATH="$tmp/muse-auth.json" expect "detects the meta login" \
    "True" "muse:auth_presence"

fresh_home
printf 'not json' >"$tmp/muse-auth.json"
MUSE_AUTH_PATH="$tmp/muse-auth.json" expect "a corrupt auth store is no login, not an exception" \
    "False" "muse:auth_presence"

fresh_home
printf '{"providers": {}}' >"$tmp/muse-auth.json"
MUSE_AUTH_PATH="$tmp/muse-auth.json" expect "an auth store without meta is no login" \
    "False" "muse:auth_presence"

# The model is whatever the CLI is set to — never a name pinned in our source.
fresh_home
printf '{"schema_version": 1, "provider": "meta", "model": "muse-spark-9.9"}' >"$tmp/muse-settings.json"
MUSE_SETTINGS_PATH="$tmp/muse-settings.json" expect "reads the model from the CLI settings" \
    "muse-spark-9.9" "muse:configured_model"

fresh_home
MUSE_SETTINGS_PATH="$tmp/nope.json" expect "no settings file means no model claim" \
    "" "muse:configured_model"

# ── Claude admin key, OpenAI key, Grok key ──────────────────────────────────
#
# These three resolve their credential through the shared resolve_key() rather
# than their own file readers. That is the right factoring, but it moved code
# that decides whether a tab renders a number or "no token configured", and the
# contract tests cannot see a wrong precedence — so the order is pinned here.

CLAUDE_IMPORT="from aiusage.providers.claude_credentials import get_claude_credentials"
CLAUDE_EXPR="get_claude_credentials().get('claudeAdminApiKey', '')"
OPENAI_IMPORT="from aiusage.providers.openai_credentials import get_openai_credentials"
OPENAI_EXPR="get_openai_credentials().get('openaiApiKey', '')"
GROK_IMPORT="from aiusage.providers.grok import _resolve_api_key"
GROK_EXPR="_resolve_api_key()"

fresh_home
expect_expr "no Claude admin key anywhere yields an empty key" "" "$CLAUDE_IMPORT" "$CLAUDE_EXPR"

fresh_home
printf 'from-config-file\n' >"$tmp/home/.config/claude-admin-api-key"
mkdir -p "$tmp/home/.claude"
printf 'from-dot-claude\n' >"$tmp/home/.claude/admin-api-key"
expect_expr "prefers ~/.config/claude-admin-api-key over ~/.claude" \
    "from-config-file" "$CLAUDE_IMPORT" "$CLAUDE_EXPR"

fresh_home
mkdir -p "$tmp/home/.claude"
printf 'from-dot-claude\n' >"$tmp/home/.claude/admin-api-key"
expect_expr "falls back to ~/.claude/admin-api-key" \
    "from-dot-claude" "$CLAUDE_IMPORT" "$CLAUDE_EXPR"

fresh_home
printf 'from-config-file\n' >"$tmp/home/.config/claude-admin-api-key"
CLAUDE_ADMIN_API_KEY=from-env expect_expr "the environment outranks the file" \
    "from-env" "$CLAUDE_IMPORT" "$CLAUDE_EXPR"

fresh_home
WIDGET_CLAUDE_ADMIN_KEY=from-widget CLAUDE_ADMIN_API_KEY=from-env \
    expect_expr "the widget field outranks the environment" \
    "from-widget" "$CLAUDE_IMPORT" "$CLAUDE_EXPR"

# A key pasted with a stray newline used to reach urllib and raise with the
# credential in the traceback; every source is cleaned the same way now.
fresh_home
CLAUDE_ADMIN_API_KEY='  sk-with-space
' expect_expr "an environment key is whitespace-cleaned like a file one" \
    "sk-with-space" "$CLAUDE_IMPORT" "$CLAUDE_EXPR"

fresh_home
printf 'from-config-openai\n' >"$tmp/home/.config/openai-api-key"
mkdir -p "$tmp/home/.openai"
printf 'from-dot-openai\n' >"$tmp/home/.openai/api-key"
expect_expr "prefers ~/.config/openai-api-key over ~/.openai" \
    "from-config-openai" "$OPENAI_IMPORT" "$OPENAI_EXPR"

fresh_home
printf 'from-config-openai\n' >"$tmp/home/.config/openai-api-key"
OPENAI_API_KEY=from-env expect_expr "OPENAI_API_KEY outranks the file" \
    "from-env" "$OPENAI_IMPORT" "$OPENAI_EXPR"

fresh_home
WIDGET_OPENAI_API_KEY=from-widget OPENAI_API_KEY=from-env \
    expect_expr "the widget field outranks OPENAI_API_KEY" \
    "from-widget" "$OPENAI_IMPORT" "$OPENAI_EXPR"

# xAI renamed the product; both spellings are accepted, xai first.
fresh_home
XAI_API_KEY=from-xai GROK_API_KEY=from-grok \
    expect_expr "XAI_API_KEY outranks GROK_API_KEY" "from-xai" "$GROK_IMPORT" "$GROK_EXPR"

fresh_home
WIDGET_GROK_API_KEY=from-widget XAI_API_KEY=from-xai \
    expect_expr "either widget spelling outranks the environment" \
    "from-widget" "$GROK_IMPORT" "$GROK_EXPR"

fresh_home
WIDGET_XAI_API_KEY=from-widget-xai WIDGET_GROK_API_KEY=from-widget-grok \
    expect_expr "the xai widget spelling wins over the grok one" \
    "from-widget-xai" "$GROK_IMPORT" "$GROK_EXPR"

fresh_home
mkdir -p "$tmp/home/.config/xai" "$tmp/home/.config/grok"
printf 'from-xai-file\n' >"$tmp/home/.config/xai/api-key"
printf 'from-grok-file\n' >"$tmp/home/.config/grok/api-key"
expect_expr "prefers ~/.config/xai/api-key over the grok one" \
    "from-xai-file" "$GROK_IMPORT" "$GROK_EXPR"

if [ "$failures" -eq 0 ]; then
    printf 'ok — %d credential checks passed\n' "$checks"
else
    printf '%d of %d credential checks failed\n' "$failures" "$checks" >&2
    exit 1
fi
