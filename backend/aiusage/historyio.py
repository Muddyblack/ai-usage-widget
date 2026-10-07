"""Every access to the shared usage-history file, for every frontend.

tools/sh/history-io hands each command here whenever it finds an interpreter,
and the Windows frontend runs this module directly, so the shared file has one
owner in code whichever frontend is running. The shell script keeps only the
degraded paths for a machine with no Python at all.

  python -m aiusage.historyio autosave [--stdin]  union the payload into the file; it wins
  python -m aiusage.historyio seed [--stdin]      the same, but the file keeps its own values
  python -m aiusage.historyio autoload            the file for startup restore; drop it if corrupt
  python -m aiusage.historyio export              copy the file to a timestamped snapshot
  python -m aiusage.historyio import              the newest readable copy

The payload is $WIDGET_HISTORY_JSON, or stdin with --stdin — Windows caps one
environment variable at 32767 characters, which a large batch passes.

Output is one JSON object on stdout, exactly as the shell tool prints it:
{"ok":true,"path":…} | {"ok":true,"data":[…]} | {"ok":true,"empty":true} |
{"error":…}. The exit status is 0 whenever an object was printed, errors
included, so the shell falls back to its own code only when Python itself
could not run.

See the shell script and tests/history-io.test.sh for why each rule is there;
the rules are unchanged, only the language is.
"""

import glob
import json
import os
import sys
import time

from . import history, paths

LATEST_NAME = "usage-history-latest.json"
LOCK_NAME = ".usage-history.lock"
SNAPSHOT_GLOB = "usage-history-*.json"
# Kept out of SNAPSHOT_GLOB, or a reader would take a reservation for the
# newest snapshot, find it empty, call it corrupt and remove it.
EXPORT_PREFIX = ".usage-history-export.tmp."


def _dumps(obj):
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)


def _error(message):
    return _dumps({"error": message})


def _latest(directory):
    return os.path.join(directory, LATEST_NAME)


# ── Locking ──────────────────────────────────────────────────────────────────
# The shell tool locks the same file with flock(1), and fcntl.flock takes the
# same kind of lock, so a Python save and a shell save still exclude each
# other. Windows gets a byte-range lock on the same file.

if paths.IS_WINDOWS:
    import msvcrt

    def _try_lock(fh):
        fh.seek(0)
        msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)

    def _unlock(fh):
        try:
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass

else:
    import fcntl

    def _try_lock(fh):
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _unlock(fh):
        # Closing the file releases a flock; nothing to do first.
        pass


def _lock_wait():
    # Overridable so the tests do not have to sit out the real wait.
    try:
        return max(0.0, float(os.environ.get("WIDGET_HISTORY_LOCK_WAIT", "5")))
    except ValueError:
        return 5.0


def _acquire(path, wait):
    """The open, locked lock file — or None when it could not be taken within
    `wait` seconds. Merging anyway would race the holder: both sides read, both
    merge, and the second rename drops the first one's points."""
    try:
        fh = open(path, "a+b")
    except OSError:
        return None
    deadline = time.monotonic() + wait
    while True:
        try:
            _try_lock(fh)
            return fh
        except OSError:
            if time.monotonic() >= deadline:
                fh.close()
                return None
            time.sleep(0.05)


def _release(fh):
    _unlock(fh)
    fh.close()


# ── Reading ──────────────────────────────────────────────────────────────────


def _resolve_src(directory):
    """Which file to read: an explicit path, then the latest file, then the
    newest timestamped snapshot."""
    explicit = os.environ.get("WIDGET_HISTORY_IMPORT_PATH") or ""
    if explicit and os.path.isfile(explicit):
        return explicit
    latest = _latest(directory)
    if os.path.isfile(latest):
        return latest
    snapshots = glob.glob(os.path.join(glob.escape(directory), SNAPSHOT_GLOB))
    if not snapshots:
        return ""
    try:
        return max(snapshots, key=os.path.getmtime)
    except OSError:
        return ""


def _read_array_or_delete(src):
    """(text, None) for a file that parses as a JSON array, (None, "deleted")
    for one that does not — it is removed, as corruption the next save heals —
    and (None, message) when it could not be read at all. An unreadable file is
    left alone: it holds something, and deleting it might drop a whole series."""
    try:
        with open(src, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        return None, "missing"
    except OSError as exc:
        return None, f"could not read {src}: {exc}"
    try:
        valid = isinstance(json.loads(text), list)
    except ValueError:
        valid = False
    if valid:
        return text.rstrip("\n"), None
    try:
        os.unlink(src)
    except OSError:
        pass
    return None, "deleted"


# ── Commands ─────────────────────────────────────────────────────────────────


def save(directory, payload, keep_existing):
    if payload.strip() in ("", "[]"):
        return _dumps({"ok": True, "empty": True})

    lock_path = os.path.join(directory, LOCK_NAME)
    lock = _acquire(lock_path, _lock_wait())
    if lock is None:
        return _error(f"could not lock {lock_path}")
    try:
        try:
            incoming = json.loads(payload)
        except ValueError:
            return _error("history payload was not JSON")
        if not isinstance(incoming, list):
            return _error("history payload was not an array")

        latest = _latest(directory)
        try:
            merged = history.save(latest, incoming, history.DEFAULT_LIMIT, keep_existing)
        except OSError as exc:
            # A payload that could not be unioned in is never written over the
            # file instead: the caller still holds it and retries.
            return _error(f"could not update {latest}: {exc}")
        return _dumps({"ok": True, "data": merged})
    finally:
        _release(lock)


def autoload(directory):
    src = _resolve_src(directory)
    if not src:
        return _dumps({"ok": True, "empty": True})
    text, problem = _read_array_or_delete(src)
    if problem == "missing":
        return _dumps({"ok": True, "empty": True})
    if problem == "deleted":
        # Corrupt or an unknown format: start fresh, no error for the user.
        return _dumps({"ok": True, "empty": True, "deleted": True})
    if problem:
        return _error(problem)
    # Handed on verbatim rather than re-encoded, so the frontends see the file
    # byte for byte as whoever wrote it left it.
    return '{"ok":true,"data":' + text + "}"


def import_(directory):
    src = _resolve_src(directory)
    if not src:
        return _error(f"no saved history found in {directory}")
    text, problem = _read_array_or_delete(src)
    if problem == "missing":
        return _error(f"no saved history found in {directory}")
    if problem == "deleted":
        return _error("file was unreadable and has been removed")
    if problem:
        return _error(problem)
    return '{"ok":true,"data":' + text + "}"


def export(directory):
    """Copy the shared file to a timestamped snapshot. Needs no lock: a save
    publishes by rename, so this reads one whole version or another."""
    import tempfile

    latest = _latest(directory)
    if not os.path.isfile(latest):
        return _error("no history to export")

    stamp = time.strftime("%Y%m%d-%H%M%S")
    # The name is second-precision, so a reserved token is what keeps two
    # exports in one second apart. The reservation is filled and then
    # published by rename, and removed if anything fails on the way.
    try:
        fd, tmp = tempfile.mkstemp(prefix=EXPORT_PREFIX, dir=directory)
    except OSError:
        return _error(f"could not write to {directory}")
    out = os.path.join(directory, f"usage-history-{stamp}-{tmp.rsplit('.', 1)[-1]}.json")
    try:
        with os.fdopen(fd, "wb") as dst, open(latest, "rb") as src:
            dst.write(src.read())
        history.replace(tmp, out)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return _error(f"could not write {out}")
    return _dumps({"ok": True, "path": out})


def run(command, payload="", directory=None):
    """One command's output line. `payload` is only read by autosave/seed."""
    directory = directory or paths.history_dir()
    try:
        os.makedirs(directory, exist_ok=True)
    except OSError:
        return _error(f"could not write to {directory}")

    if command in ("autosave", "seed"):
        return save(directory, payload, keep_existing=command == "seed")
    if command == "autoload":
        return autoload(directory)
    if command == "export":
        return export(directory)
    if command == "import":
        return import_(directory)
    return _error("unknown command")


def main(argv):
    command = argv[0] if argv else ""
    payload = ""
    if command in ("autosave", "seed"):
        if "--stdin" in argv[1:]:
            payload = sys.stdin.read()
        else:
            payload = os.environ.get("WIDGET_HISTORY_JSON", "")
    sys.stdout.write(run(command, payload) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
