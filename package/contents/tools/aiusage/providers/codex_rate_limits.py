"""Drives `codex app-server --stdio` over JSON-RPC to read plan rate limits.

Popen with line-buffered stdin/stdout; a 5s read deadline per phase, and the
child is always reaped.

Replies are read on a helper thread rather than with `selectors`: Windows can
only select() on sockets, never on a pipe, and a thread works the same on both.

Successful replies are cached under the same identity scope as the last-good
snapshot (SHA-256 of the access token plus normalized CODEX_HOME) for a short
TTL, so a repeated refresh inside the TTL does not launch the app-server again.
The cached reply is returned with `_codexSource`/`_codexAge` metadata that the
collector pops before the payload reaches the frontend.
"""

import hmac
import json
import math
import os
import queue
import shutil
import subprocess
import tempfile
import threading
import time

from .. import config, paths
from .codex_last_good import _FIELDS, TTL_SECONDS, _has_limits, identity_key


def _pump(stream, lines):
    """Reader thread: hand every line on, then None for end of stream."""
    try:
        for line in stream:
            lines.put(line)
    except (OSError, ValueError):
        # ValueError: the stream was closed under us during cleanup.
        pass
    finally:
        lines.put(None)


def _read_until_id(lines, want_id, timeout):
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        try:
            line = lines.get(timeout=remaining)
        except queue.Empty:
            return None
        if line is None:
            # Leave the end marker for the next phase, which would otherwise
            # sit out its whole deadline on a stream that has already ended.
            lines.put(None)
            return None
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if isinstance(obj, dict) and obj.get("id") == want_id:
            return obj


def _stop(proc):
    """Terminate the child and everything it started, then reap it.

    On Windows an npm install is codex.cmd, so the child is cmd.exe with node
    and the native server below it. Terminating cmd.exe alone would orphan the
    server on every poll, so the whole tree goes, by pid, while the parent is
    still there to name it."""
    if paths.IS_WINDOWS:
        try:
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(proc.pid)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                **paths.no_window(),
            )
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        try:
            proc.kill()
            proc.wait(timeout=2)
        except Exception:
            pass


def _live_codex_rate_limits():
    """One live `codex app-server` round trip; the raw reply dict."""
    # The resolved path, not the bare name: Popen does not apply PATHEXT, so on
    # Windows "codex" would never find codex.cmd or codex.exe.
    codex = shutil.which("codex")
    if codex is None:
        return {}

    try:
        proc = subprocess.Popen(
            [codex, "app-server", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            **paths.no_window(),
        )
    except OSError:
        return {}

    # Popen fills both pipes because stdin/stdout are PIPE above, but they are
    # Optional on the type level — bind them once so the child is still reaped
    # if that ever fails rather than raising past the cleanup below.
    stdin, stdout = proc.stdin, proc.stdout

    result = {}
    reader = None
    try:
        if stdin is None or stdout is None:
            return {}

        lines = queue.Queue()
        reader = threading.Thread(target=_pump, args=(stdout, lines), daemon=True)
        reader.start()

        initialize = json.dumps(
            {
                "id": 1,
                "method": "initialize",
                "params": {
                    "clientInfo": {"name": "kde-ai-usage", "version": "1"},
                    "capabilities": {"experimentalApi": True},
                },
            }
        )
        try:
            stdin.write(initialize + "\n")
            stdin.flush()
        except (BrokenPipeError, OSError):
            return {}

        if _read_until_id(lines, 1, 5) is not None:
            read_limits = json.dumps({"id": 2, "method": "account/rateLimits/read", "params": None})
            try:
                stdin.write(read_limits + "\n")
                stdin.flush()
            except (BrokenPipeError, OSError):
                read_limits_reply = None
            else:
                read_limits_reply = _read_until_id(lines, 2, 5)
            if read_limits_reply is not None and "result" in read_limits_reply:
                result = read_limits_reply.get("result") or {}
                if isinstance(result, dict) and not result:
                    result = {"_codexNoLimits": True}
    finally:
        try:
            if stdin is not None:
                stdin.close()
        except Exception:
            pass
        _stop(proc)
        # Closing stdout while the reader is blocked in it can deadlock on the
        # stream's lock, so only close it once the reader has seen the end. A
        # grandchild still holding the pipe open leaves the daemon thread
        # parked there, which costs nothing: this process exits right after.
        if reader is not None:
            reader.join(timeout=1)
        if stdout is not None and (reader is None or not reader.is_alive()):
            try:
                stdout.close()
            except Exception:
                pass

    return result


def _cache_path(key):
    return os.path.join(config.cache_dir(), f"codex-rate-limits-{key}.json")


def _read_cache(key):
    """A validated same-identity cache payload, or None."""
    try:
        with open(_cache_path(key), encoding="utf-8") as stream:
            payload = json.load(stream)
    except (OSError, ValueError):
        return None
    if not isinstance(payload, dict) or payload.get("version") != 1:
        return None
    stored_identity = payload.get("identity")
    if not isinstance(stored_identity, str) or not hmac.compare_digest(stored_identity, key):
        return None
    saved_at = payload.get("savedAt")
    data = payload.get("data")
    if isinstance(saved_at, bool) or not isinstance(saved_at, (int, float)) or not math.isfinite(saved_at):
        return None
    if not isinstance(data, dict) or not _has_limits(data):
        return None
    return {"savedAt": float(saved_at), "data": {field: data[field] for field in _FIELDS if field in data}}


def _write_cache(key, saved_at, data):
    path = _cache_path(key)
    payload = {
        "version": 1,
        "identity": key,
        "savedAt": saved_at,
        "data": {field: data[field] for field in _FIELDS if field in data},
    }
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".codex-rate-limits-", dir=directory)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, separators=(",", ":"))
            os.replace(temporary, path)
        except OSError:
            try:
                os.unlink(temporary)
            except OSError:
                pass
    except OSError:
        pass


def get_codex_rate_limits(token="", home="", now=None):
    """Rate limits with a short positive TTL cache.

    A successful app-server reply is cached under the same identity scope as
    the last-good snapshot. A fresh cache hit returns the cached data without
    launching the app-server; the reply carries `_codexSource` ("cached") and
    `_codexAge` metadata that the collector pops. A live reply is "live" with
    age 0; a failed attempt is "unavailable" with no age. Without a token there
    is no identity to scope the cache to, so every call is live.
    """
    checked_at = time.time() if now is None else now
    key = identity_key(token, home) if token else None
    if key is not None:
        cached = _read_cache(key)
        if cached is not None:
            age = checked_at - cached["savedAt"]
            if 0 <= age <= TTL_SECONDS:
                return {**cached["data"], "_codexSource": "cached", "_codexAge": int(age)}

    result = _live_codex_rate_limits()
    if key is not None and _has_limits(result):
        _write_cache(key, checked_at, result)
        return {**result, "_codexSource": "live", "_codexAge": 0}
    return {**result, "_codexSource": "unavailable", "_codexAge": None}
