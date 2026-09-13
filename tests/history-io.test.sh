#!/usr/bin/env bash
# The backend is gettext-translated; pin the locale so English assertions hold.
export LC_ALL=C.UTF-8
export LANGUAGE=
set -euo pipefail

# tools/sh/history-io owns the usage-history file that the Plasma widget and the
# Quickshell panel both read and write. The two never coordinate — and a second
# Plasma widget instance is a third writer — so a save has to merge with what is
# already on disk rather than replace it, and a reader must never catch a
# half-written file (the loader here *deletes* anything that does not parse).
#
# The union gives the payload precedence, so what a payload may hold is the whole
# contract. `autosave` carries readings the caller just took, on points only it
# writes, and asserts them. `seed` carries a series the caller restored — its
# config, a snapshot the user imported — which can predate what is on disk, and
# only fills in what the file lacks. Both comparisons happen here, inside the
# lock, because a caller weighing them against its own copy of the file may be
# weighing them against a value the other frontend has already replaced.
# tests/shared-code.test.js drives both frontends through this tool.

repo="$(cd "$(dirname "$0")/.." && pwd)"
tool="$repo/package/contents/tools/sh/history-io"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export XDG_DATA_HOME="$tmp/data"
dir="$XDG_DATA_HOME/ai-usage-widget"
latest="$dir/usage-history-latest.json"

fail() { printf 'history-io: %s\n' "$1" >&2; exit 1; }
save() { WIDGET_HISTORY_JSON="$1" "$tool" autosave; }

# ── autosave writes, autoload reads it straight back ────────────────────────
save '[{"t":1,"w":40}]' >/dev/null
[ -f "$latest" ] || fail "autosave did not create $latest"
out="$("$tool" autoload)"
[ "$out" = '{"ok":true,"data":[{"t":1,"w":40}]}' ] || fail "autoload round trip returned $out"

# ── a save unions with the file instead of overwriting it ───────────────────
# The other frontend recorded t=2 while this one was not looking; saving a
# series that predates it must not roll it back.
save '[{"t":2,"za":60}]' >/dev/null
out="$(save '[{"t":1,"w":40},{"t":3,"cp":7}]')"
[ "$out" = '{"ok":true,"data":[{"t":1,"w":40},{"t":2,"za":60},{"t":3,"cp":7}]}' ] \
  || fail "autosave did not union with the file: $out"
[ "$(cat "$latest")" = '[{"t":1,"w":40},{"t":2,"za":60},{"t":3,"cp":7}]' ] \
  || fail "the merged series did not land on disk"

# The caller gets the merged series back, which is how both frontends converge
# on the same data without either of them re-reading on a timer.
out="$(save '[{"t":1,"s":11}]')"
[ "$out" = '{"ok":true,"data":[{"t":1,"w":40,"s":11},{"t":2,"za":60},{"t":3,"cp":7}]}' ] \
  || fail "a same-timestamp save did not merge key by key: $out"

# ── a seed fills in, where a save overrides ─────────────────────────────────
# Same merge, opposite precedence. The file here holds w:40 at t=1, which the
# other frontend recorded; a seed carrying an older w:11 for it must not win.
out="$(WIDGET_HISTORY_JSON='[{"t":1,"w":11},{"t":5,"s":1}]' "$tool" seed)"
[ "$out" = '{"ok":true,"data":[{"t":1,"w":40,"s":11},{"t":2,"za":60},{"t":3,"cp":7},{"t":5,"s":1}]}' ] \
  || fail "seed overrode the file instead of filling it in: $out"

# A reading still asserts itself over the same point.
out="$(save '[{"t":1,"w":12}]')"
[ "$out" = '{"ok":true,"data":[{"t":1,"w":12,"s":11},{"t":2,"za":60},{"t":3,"cp":7},{"t":5,"s":1}]}' ] \
  || fail "autosave stopped taking precedence: $out"

# A seed the file already has everywhere changes nothing.
before="$(cat "$latest")"
WIDGET_HISTORY_JSON='[{"t":1,"w":99},{"t":2,"za":1}]' "$tool" seed >/dev/null
[ "$(cat "$latest")" = "$before" ] || fail "a redundant seed rewrote the file: $(cat "$latest")"

# ── a save that cannot merge leaves the file alone ──────────────────────────
# Writing the payload over the file instead would drop everything the other
# frontend recorded — and report success while doing it. The caller still holds
# its batch, so saying so costs one poll; guessing costs the file.
held="$(cat "$latest")"
out="$(PYTHON3=false WIDGET_HISTORY_JSON='[{"t":4,"w":50}]' "$tool" autosave 2>/dev/null)"
case "$out" in
  '{"error"'*) ;;
  *) fail "a broken interpreter reported $out" ;;
esac
[ "$(cat "$latest")" = "$held" ] || fail "a failed merge overwrote the file: $(cat "$latest")"

# Same with no interpreter at all: nothing here can union, so an existing file
# belongs to whoever last merged into it.
out="$(PYTHON3=/nonexistent/python3 WIDGET_HISTORY_JSON='[{"t":4,"w":50}]' "$tool" autosave)"
case "$out" in
  '{"error"'*) ;;
  *) fail "a missing interpreter reported $out" ;;
esac
[ "$(cat "$latest")" = "$held" ] || fail "a missing interpreter overwrote the file"

# ...but with no file there is nothing to lose, and the series is still saved.
mv "$latest" "$latest.held"
out="$(PYTHON3=/nonexistent/python3 WIDGET_HISTORY_JSON='[{"t":4,"w":50}]' "$tool" autosave)"
[ "$out" = '{"ok":true}' ] || fail "a first save with no interpreter returned $out"
[ "$(cat "$latest")" = '[{"t":4,"w":50}]' ] || fail "a first save with no interpreter wrote nothing"
mv "$latest.held" "$latest"

# ── autosave replaces the file atomically ───────────────────────────────────
# A rename means the old inode stays whole until the new file is complete, so a
# reader that opened the path before the write still sees a parseable array.
before="$(stat -c %i "$latest")"
held_expected="$(cat "$latest")"
exec 9<"$latest"
save '[{"t":4,"w":50}]' >/dev/null
held="$(cat <&9)"; exec 9<&-
[ "$before" != "$(stat -c %i "$latest")" ] || fail "autosave wrote in place instead of renaming"
[ "$held" = "$held_expected" ] || fail "a reader mid-write saw a torn file: $held"

# No temp or lock file is left where the timestamped-export glob could find it.
leftovers="$(find "$dir" -name '*.tmp*' -o -name 'usage-history-*.json.*' | wc -l)"
[ "$leftovers" -eq 0 ] || fail "autosave left $leftovers stray files behind"

# ── a save that cannot take the lock does not write ─────────────────────────
# Going ahead would race the holder: both sides read, both merge, and the second
# rename drops the first one's points. The frontend keeps its batch and retries,
# so refusing costs a poll.
held="$(cat "$latest")"
exec 8>"$dir/.usage-history.lock"
flock 8
out="$(WIDGET_HISTORY_LOCK_WAIT=1 WIDGET_HISTORY_JSON='[{"t":98,"w":98}]' "$tool" autosave)"
case "$out" in
  '{"error"'*) ;;
  *) fail "a save that could not lock reported $out" ;;
esac
[ "$(cat "$latest")" = "$held" ] || fail "a save wrote while another process held the lock"

# An export only reads, so a held lock is none of its business.
out="$(WIDGET_HISTORY_LOCK_WAIT=1 "$tool" export)"
case "$out" in
  '{"ok":true,"path"'*) ;;
  *) fail "an export was blocked by a lock it does not need: $out" ;;
esac
[ "$(cat "$latest")" = "$held" ] || fail "an export changed the shared file"
exec 8>&-
# Nothing else has made a timestamped copy yet; drop this one so the export test
# further down still finds its own.
rm -f "$dir"/usage-history-2*.json

# ...and the batch lands on the retry, once the holder is gone.
out="$(save '[{"t":98,"w":98}]')"
case "$out" in
  *'{"t":98,"w":98}'*) ;;
  *) fail "the retry after a lock failure returned $out" ;;
esac

# ── concurrent savers do not lose each other's points ───────────────────────
rm -f "$latest"
for i in $(seq 1 12); do save "[{\"t\":$i,\"w\":$i}]" >/dev/null & done
wait
count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$latest")"
[ "$count" -eq 12 ] || fail "12 concurrent saves left $count points instead of 12"

# ── an empty series never clears the shared file ────────────────────────────
# A fresh install polls before it has restored anything; that must not wipe the
# points the other frontend recorded.
save '[]' >/dev/null
[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$latest")" -eq 12 ] \
  || fail "an empty autosave cleared the file"

# ── a genuinely corrupt file is still dropped ───────────────────────────────
printf '[{"t":1,"w":' > "$latest"
out="$("$tool" autoload)"
[ "$out" = '{"ok":true,"empty":true,"deleted":true}' ] || fail "corrupt autoload returned $out"
[ ! -f "$latest" ] || fail "corrupt file was not removed"

# ...and a save onto a corrupt file starts clean rather than failing.
out="$(save '[{"t":9,"w":90}]')"
[ "$out" = '{"ok":true,"data":[{"t":9,"w":90}]}' ] || fail "save after corruption returned $out"

# ── junk the other frontend must never be handed ────────────────────────────
out="$(save '[{"t":null,"w":1},{"t":"10","w":100},{"t":11,"w":null}]')"
[ "$out" = '{"ok":true,"data":[{"t":9,"w":90},{"t":10,"w":100},{"t":11}]}' ] \
  || fail "save did not sanitize its payload: $out"

# ── export copies the shared file, verbatim and untouched ──────────────────
rm -f "$latest" "$dir"/usage-history-2*.json
save '[{"t":1,"w":40},{"t":3,"w":60}]' >/dev/null
before="$(cat "$latest")"
"$tool" export >/dev/null
stamped="$(find "$dir" -name 'usage-history-2*.json' | head -n1)"
[ -n "$stamped" ] || fail "export wrote no timestamped copy"
[ "$(cat "$stamped")" = "$before" ] || fail "the snapshot is not the shared file: $(cat "$stamped")"
[ "$(cat "$latest")" = "$before" ] || fail "export modified the shared file"

# With nothing saved there is nothing to snapshot.
mv "$latest" "$latest.held"
out="$("$tool" export)"
[ "$out" = '{"error":"no history to export"}' ] || fail "an empty export returned $out"
mv "$latest.held" "$latest"

# ── import falls back to the newest timestamped copy ────────────────────────
rm -f "$latest"
out="$("$tool" import)"
[ "$out" = '{"ok":true,"data":[{"t":1,"w":40},{"t":3,"w":60}]}' ] || fail "import fallback returned $out"

# ── two exports inside one second are two files ─────────────────────────────
# `date` is second-precision, so a name built from it alone would collide and the
# second export would replace the first snapshot.
rm -f "$latest" "$dir"/usage-history-2*.json
save '[{"t":1,"w":11}]' >/dev/null
p1="$("$tool" export)"
p2="$("$tool" export)"
[ "$p1" != "$p2" ] || fail "two exports returned the same path: $p1"
[ "$(find "$dir" -name 'usage-history-2*.json' | wc -l)" -eq 2 ] \
  || fail "the second export replaced the first snapshot"

# The reservation must not leave an empty file behind when the write fails: an
# unreadable snapshot is what import would find and report.
chmod 500 "$dir"
"$tool" export >/dev/null 2>&1 || true
chmod 700 "$dir"
[ "$(find "$dir" -name 'usage-history-2*.json' | wc -l)" -eq 2 ] \
  || fail "a failed export left a stray snapshot behind"

# ── an export in flight stays out of a reader's way ─────────────────────────
# What an export is still filling must not match usage-history-*.json. A reader
# takes the newest match, finds it empty, calls it corrupt and removes it — and
# that `rm -f` carries off the finished snapshot when the write lands in between.
# The real window is microseconds, so hold the rename open to see it.
rm -f "$latest" "$dir"/usage-history-2*.json
save '[{"t":7,"w":70}]' >/dev/null
"$tool" export >/dev/null
real_mv="$(command -v mv)"
mkdir -p "$tmp/slow"
printf '#!/bin/sh\nsleep 2\nexec %s "$@"\n' "$real_mv" > "$tmp/slow/mv"
chmod +x "$tmp/slow/mv"
( PATH="$tmp/slow:$PATH" "$tool" export >/dev/null ) &
export_pid=$!
sleep 1

[ "$(find "$dir" -name 'usage-history-2*.json' -empty | wc -l)" -eq 0 ] \
  || fail "an export in flight is visible under the snapshot glob"
out="$("$tool" autoload)"
[ "$out" = "{\"ok\":true,\"data\":$(cat "$latest")}" ] \
  || fail "an export in flight derailed a reader: $out"

wait "$export_pid"
[ "$(find "$dir" -name 'usage-history-2*.json' | wc -l)" -eq 2 ] \
  || fail "a reader cost the export its snapshot"
[ "$(find "$dir" -name '.usage-history-export*' | wc -l)" -eq 0 ] \
  || fail "an export left its reservation behind"

# ── one cap, stated once ────────────────────────────────────────────────────
# The tool names no limit, so aiusage.history's DEFAULT_LIMIT governs both it and
# the frontends, which read the same constant from UsageHistory.js.
rm -f "$latest"
python3 -c "
import json, sys
json.dump([{'t': i, 'w': i} for i in range(10005)], open(sys.argv[1], 'w'), separators=(',', ':'))
" "$latest"
save '[{"t":99999999,"w":1}]' >/dev/null
n="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$latest")"
[ "$n" -eq 10000 ] || fail "the shared file was capped at $n, expected 10000"
first="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["t"])' "$latest")"
[ "$first" = "6" ] || fail "the cap dropped the wrong end: oldest t=$first"

echo "history-io: ok"
