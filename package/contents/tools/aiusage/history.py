"""The on-disk half of the shared usage history.

Both frontends keep the rolling series in
``~/.local/share/ai-usage-widget/usage-history-latest.json``. Whoever is running
writes it on every poll, and neither can assume it still holds what it last put
there: the other frontend may have been recording in the meantime, and a second
Plasma widget instance is a writer too. So a save is a union against what is
already on disk, not an overwrite.

The union cannot tell which of two values for a key is the newer reading, so it
gives the payload precedence — safe only because a payload is the caller's own
new readings. A caller offering a series it merely restored passes
``--keep-existing``, and the file keeps its own values instead.

The rules here mirror ``package/contents/code/UsageHistory.js`` — the frontends
apply the same union in QML when they restore at startup. ``tests/shared-code.test.js``
replays a shared fixture through both implementations and compares the JSON byte
for byte, so the two cannot drift apart unnoticed.
"""

import json
import math
import os
import re
import sys
import time

from . import paths

# Mirrors DEFAULT_LIMIT in UsageHistory.js — see the note there.
DEFAULT_LIMIT = 10000

# A timestamp written as a string is only read back when it is a plain decimal.
# float() would also take "1_0" and "nan"; JS's Number() would take "0x10" and
# "Infinity". Neither set is the other's, so both sides accept just this.
_DECIMAL_RE = re.compile(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\Z")


def point_time(point):
    """A point's timestamp as a finite number, or None when it is unusable.

    The file is written by whichever frontend ran last and can be hand-edited, so
    a null, a stray string or a truncated value has to be dropped here rather
    than reaching a chart axis. Integral values stay ints so the JSON matches
    what the QML side would have written.
    """
    if not isinstance(point, dict):
        return None

    t = point.get("t")
    if isinstance(t, str):
        if not _DECIMAL_RE.match(t.strip()):
            return None
        t = float(t)
    # bool is an int subclass in Python; JS would reject `true` as a timestamp.
    if isinstance(t, bool) or not isinstance(t, (int, float)):
        return None
    if math.isnan(t) or math.isinf(t):
        return None
    if isinstance(t, float) and t.is_integer():
        t = int(t)

    return t


def _assign_values(dst, src):
    """Copy every series value of `src` onto `dst`, keeping `t`, dropping nulls.

    A provider that failed reports its keys as null; writing those in would erase
    the last good reading instead of leaving a gap in the chart.
    """
    for key, value in src.items():
        if key == "t":
            continue
        if value is not None:
            dst[key] = value
    return dst


def union(base, overlay, limit=None):
    """Combine two independently recorded series, ascending and trimmed.

    Points sharing a timestamp are combined key by key with `overlay` winning, so
    a point holding only `w` and one holding only `cp` end up as one complete
    point. Repeats within one side fold the same way.
    """
    by_time = {}
    for points in (base, overlay):
        for point in points or []:
            t = point_time(point)
            if t is None:
                continue
            _assign_values(by_time.setdefault(t, {"t": t}), point)

    out = [by_time[t] for t in sorted(by_time)]
    cap = limit or DEFAULT_LIMIT
    return out[-cap:] if len(out) > cap else out


def normalize(points, limit=None):
    """Accept the current points and the legacy weekly-only shape, and trim."""
    out = []
    for point in points or []:
        t = point_time(point)
        if t is None:
            continue

        q = _assign_values({"t": t}, point)
        # Legacy weekly-only points carried the value as `v`.
        if "w" not in q and point.get("v") is not None:
            q["w"] = point["v"]
        q.pop("v", None)
        out.append(q)

    cap = limit or DEFAULT_LIMIT
    return out[-cap:] if len(out) > cap else out


def _read(path):
    """The series on disk, or None when there is nothing usable there.

    Missing is a fresh start and unparseable is corruption the merge heals by
    writing over it. Any other OSError is raised instead: the file is there and
    holds something, and reporting it empty would replace a whole series with one
    save's worth.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (FileNotFoundError, ValueError):
        return None
    return data if isinstance(data, list) else None


def replace(tmp, path):
    """os.replace(), retried for a moment on Windows.

    POSIX renames over a file that someone has open. Windows refuses with a
    PermissionError instead, for as long as any reader holds the file — which
    is only ever for the few milliseconds a load takes, so waiting that out is
    enough."""
    attempts = 40 if paths.IS_WINDOWS else 1
    for attempt in range(attempts):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            if attempt == attempts - 1:
                raise
            time.sleep(0.05)


def save(path, incoming, limit=None, keep_existing=False):
    """Union `incoming` into the file at `path` and write the result back.

    `incoming` takes precedence as the caller's own new readings; `keep_existing`
    flips that, and the file keeps its own values for anything it already has.

    Returns the merged series. The caller holds the lock; the write itself goes
    through a temp file and a rename so a reader without the lock still sees a
    whole file rather than a half-written one.
    """
    stored = normalize(_read(path) or [], limit)
    fresh = normalize(incoming, limit)
    merged = union(fresh, stored, limit) if keep_existing else union(stored, fresh, limit)
    if merged == stored:
        return merged

    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    # Hand-rolled rather than tempfile.mkstemp: importing tempfile costs about as
    # much as everything else this process does, and the pid already makes the
    # name unique among concurrent savers. The dot prefix keeps it out of the
    # usage-history-*.json glob that resolve_src uses for timestamped exports.
    tmp = os.path.join(directory, f".usage-history.tmp.{os.getpid()}")
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(merged, fh, separators=(",", ":"))
        # A rename is atomic, so a reader without the lock sees the whole old
        # file or the whole new one, never a half-written array.
        replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

    return merged


def main(argv):
    # `save <path> [limit] [--keep-existing]` — series in on stdin, merged one out
    # as the tool's usual {"ok":true,"data":…} envelope.
    keep_existing = "--keep-existing" in argv
    argv = [arg for arg in argv if arg != "--keep-existing"]
    if len(argv) < 2 or argv[0] != "save":
        print(json.dumps({"error": "usage: history save <path> [limit] [--keep-existing]"}))
        return 1

    path = argv[1]
    limit = int(argv[2]) if len(argv) > 2 and argv[2] else DEFAULT_LIMIT
    try:
        incoming = json.loads(sys.stdin.read() or "[]")
    except ValueError:
        print(json.dumps({"error": "history payload was not JSON"}))
        return 1
    if not isinstance(incoming, list):
        print(json.dumps({"error": "history payload was not an array"}))
        return 1

    try:
        merged = save(path, incoming, limit, keep_existing)
    except OSError as exc:
        # Reading the file is part of the save, so this covers both halves.
        print(json.dumps({"error": f"could not update {path}: {exc}"}))
        return 1

    print(json.dumps({"ok": True, "data": merged}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
