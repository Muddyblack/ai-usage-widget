#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
set -euo pipefail

# get-codex-stats used to be a standalone awk+jq script; the aggregation now
# lives in aiusage.providers.codex_stats, called in-process by get-ai-usage.
# This test drives that function directly via python3 instead of a CLI.

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export PYTHONPATH="$repo/package/contents/tools"
export XDG_CACHE_HOME="$tmp/cache"
export CODEX_CONFIG_FILE="$tmp/config.toml"
export CODEX_SESSIONS_DIR="$tmp/sessions"

run() {
    python3 -B -c "from aiusage.providers.codex_stats import get_codex_stats; import json; print(json.dumps(get_codex_stats()))"
}

# No sessions directory at all -> empty object, like the other helpers.
test "$(run)" = '{}'

day="$CODEX_SESSIONS_DIR/2026/07/19"
mkdir -p "$day"

# Two tool calls, two prompts, cumulative usage in the final token_count event.
cat >"$day/rollout-a.jsonl" <<'EOF'
{"timestamp":"2026-07-19T08:00:00.000Z","type":"session_meta","payload":{"id":"a"}}
{"timestamp":"2026-07-19T08:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high"}}
{"timestamp":"2026-07-19T08:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}
{"timestamp":"2026-07-19T08:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"shell"}}
{"timestamp":"2026-07-19T08:00:04.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch"}}
{"timestamp":"2026-07-19T08:00:05.000Z","type":"event_msg","payload":{"type":"user_message","message":"more"}}
{"timestamp":"2026-07-19T08:00:06.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400,"last_token_usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2},"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}}
{"timestamp":"2026-07-19T09:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
EOF

# Second session, different model, so the per-model split is exercised.
cat >"$day/rollout-b.jsonl" <<'EOF'
{"timestamp":"2026-07-19T10:00:00.000Z","type":"session_meta","payload":{"id":"b"}}
{"timestamp":"2026-07-19T10:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.5","effort":"medium"}}
{"timestamp":"2026-07-19T10:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"hey"}}
{"timestamp":"2026-07-19T10:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400,"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":15}}}}
EOF

actual="$(run)"

jq -e '.totalSessions == 2'   <<<"$actual" >/dev/null
jq -e '.totalMessages == 3'   <<<"$actual" >/dev/null
jq -e '.totalToolCalls == 2'  <<<"$actual" >/dev/null
jq -e '.totalTokens == 135'   <<<"$actual" >/dev/null
jq -e '.firstSessionDate == "2026-07-19"' <<<"$actual" >/dev/null
jq -e '.modelUsage["gpt-5.6-sol"].totalTokens == 120' <<<"$actual" >/dev/null
jq -e '.modelUsage["gpt-5.6-sol"].cachedInput == 40'  <<<"$actual" >/dev/null
jq -e '.modelUsage["gpt-5.5"].sessions == 1'          <<<"$actual" >/dev/null
# rollout-a spans 08:00:00 -> 09:00:00
jq -e '.longestSession.duration == 3600000' <<<"$actual" >/dev/null
jq -e '.dailyActivity[0].toolCallCount == 2' <<<"$actual" >/dev/null
# Latest rollout by start time is b, so its model/effort win.
jq -e '.model == "gpt-5.5" and .effortLevel == "medium"' <<<"$actual" >/dev/null

# A rollout line larger than the bounded prefix must not break extraction.
python3 - "$day/rollout-c.jsonl" <<'PY'
import sys
big = "x" * 2_000_000
with open(sys.argv[1], "w") as f:
    f.write('{"timestamp":"2026-07-19T11:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.4","effort":"low"}}\n')
    f.write('{"timestamp":"2026-07-19T11:00:01.000Z","type":"response_item","payload":{"type":"function_call_output","output":"%s"}}\n' % big)
    f.write('{"timestamp":"2026-07-19T11:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":7,"cached_input_tokens":0,"output_tokens":3,"reasoning_output_tokens":0,"total_tokens":10}}}}\n')
PY

rm -rf "$XDG_CACHE_HOME"
actual="$(run)"
jq -e '.totalSessions == 3' <<<"$actual" >/dev/null
jq -e '.modelUsage["gpt-5.4"].totalTokens == 10' <<<"$actual" >/dev/null

# Cache is reused until a rollout is newer than it.
cached="$(run)"
test "$cached" = "$actual"

echo "get-codex-stats: all assertions passed"
