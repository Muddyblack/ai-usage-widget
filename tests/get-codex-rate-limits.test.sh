#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
set -euo pipefail

# get-codex-rate-limits used to be a standalone bash+jq JSON-RPC client; that
# logic now lives in aiusage.providers.codex_rate_limits, called in-process by
# get-ai-usage. This test drives that function directly via python3 instead of
# a CLI, still faking the `codex` binary on PATH.

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export PYTHONPATH="$repo/package/contents/tools"

run() {
    PATH="$tmp:$PATH" python3 -B -c "from aiusage.providers.codex_rate_limits import get_codex_rate_limits; import json; print(json.dumps(get_codex_rate_limits()))"
}

cat >"$tmp/codex" <<'EOF'
#!/usr/bin/env bash
IFS= read -r initialize
if IFS= read -r -t 0.05 premature; then
    printf '%s\n' '{"id":1,"result":{"userAgent":"test"}}'
    exit 0
fi
printf '%s\n' '{"id":1,"result":{"userAgent":"test"}}'
IFS= read -r read_limits
printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":200}}}}'
EOF
chmod +x "$tmp/codex"

actual="$(run)"
jq -e '.rateLimits.primary.windowDurationMins == 10080 and .rateLimits.primary.usedPercent == 42' <<<"$actual" >/dev/null

cat >"$tmp/codex" <<'EOF'
#!/usr/bin/env bash
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r read_limits
EOF
chmod +x "$tmp/codex"

test "$(run)" = '{}'

echo "get-codex-rate-limits: all assertions passed"
