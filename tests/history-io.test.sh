#!/usr/bin/env bash
# Exercise only behavior owned by the history-io shell launcher. Merge,
# sanitation, import and cap rules live in tests/python/test_historyio.py.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tool="$repo/package/contents/tools/sh/history-io"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_DATA_HOME="$tmp/data"
dir="$XDG_DATA_HOME/ai-usage-widget"
latest="$dir/usage-history-latest.json"

fail() { printf 'history-io: %s\n' "$1" >&2; exit 1; }

out="$(PYTHON3=/nonexistent/python3 WIDGET_HISTORY_JSON='[{"t":4,"w":50}]' "$tool" autosave)"
[ "$out" = '{"ok":true}' ] || fail "first no-Python save returned $out"
[ "$(cat "$latest")" = '[{"t":4,"w":50}]' ] || fail "first no-Python save wrote the wrong data"

held="$(cat "$latest")"
out="$(PYTHON3=/nonexistent/python3 WIDGET_HISTORY_JSON='[{"t":5,"w":60}]' "$tool" autosave)"
case "$out" in '{"error"'*) ;; *) fail "no-Python merge reported $out" ;; esac
[ "$(cat "$latest")" = "$held" ] || fail "no-Python merge overwrote existing history"

out="$(PYTHON3=false WIDGET_HISTORY_JSON='[{"t":5,"w":60}]' "$tool" autosave 2>/dev/null)"
case "$out" in '{"error"'*) ;; *) fail "broken interpreter reported $out" ;; esac
[ "$(cat "$latest")" = "$held" ] || fail "broken interpreter overwrote existing history"

exec 8>"$dir/.usage-history.lock"
flock 8
out="$(WIDGET_HISTORY_LOCK_WAIT=1 WIDGET_HISTORY_JSON='[{"t":6,"w":70}]' "$tool" autosave)"
case "$out" in '{"error"'*) ;; *) fail "locked save reported $out" ;; esac
[ "$(cat "$latest")" = "$held" ] || fail "save wrote while flock held the lock"

# Exercise the shell fallback against the same flock, with no existing file:
# otherwise refusing to merge would mask a broken lock implementation.
mv "$latest" "$tmp/held.json"
out="$(PYTHON3=/nonexistent/python3 WIDGET_HISTORY_LOCK_WAIT=0 WIDGET_HISTORY_JSON='[{"t":6,"w":70}]' "$tool" autosave)"
case "$out" in *'could not lock'*) ;; *) fail "fallback ignored flock: $out" ;; esac
[ ! -e "$latest" ] || fail "fallback wrote while flock held the lock"
mv "$tmp/held.json" "$latest"

out="$(WIDGET_HISTORY_LOCK_WAIT=0 "$tool" export)"
case "$out" in '{"ok":true,"path"'*) ;; *) fail "export was blocked by flock: $out" ;; esac
exec 8>&-

out="$(WIDGET_HISTORY_JSON='[{"t":6,"w":70}]' "$tool" autosave)"
case "$out" in *'"t":6'*) ;; *) fail "retry after lock release returned $out" ;; esac

echo "history-io: ok"
