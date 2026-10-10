"""Read Pi (and OMP) coding-agent token usage from their local session files.

Both agents write one JSONL transcript per session under
``<agent dir>/sessions/--<cwd>--/<timestamp>_<id>.jsonl``. The first line is a
``session`` header carrying the working directory; later lines are tree entries
with an ISO ``timestamp``. Token counters ride on assistant ``message`` entries
(``message.usage``) and on stand-alone ``usage`` entries.

Nothing is sent anywhere and no key is read. Only counters, model ids and the
workspace folder name leave this module — never prompt text, tool arguments or
absolute paths.

Cost is deliberately left out: Pi records an API-rate price on every turn even
when the model was reached through a subscription login, so showing it as spend
would overstate what the user was billed. The token counts are exact.
"""

import datetime
import json
import os
from functools import lru_cache

_MAX_FILE_BYTES = 64 * 1024 * 1024
_TOKEN_FIELDS = (("input", "input"), ("output", "output"), ("cacheRead", "cacheRead"), ("cacheWrite", "cacheWrite"))
_ENTRIES_WITH_USAGE = ("message", "usage", "compaction", "branch_summary")


def session_roots():
    """Every sessions directory that may hold transcripts, best first."""
    explicit = os.environ.get("PI_CODING_AGENT_SESSION_DIR")
    if explicit:
        return [os.path.expanduser(explicit)]
    roots = []
    agent_dir = os.environ.get("PI_CODING_AGENT_DIR")
    if agent_dir:
        roots.append(os.path.join(os.path.expanduser(agent_dir), "sessions"))
    for default in ("~/.pi/agent/sessions", "~/.omp/agent/sessions"):
        roots.append(os.path.normpath(os.path.expanduser(default)))
    seen = []
    for root in roots:
        if root not in seen:
            seen.append(root)
    return seen


def _transcripts(root):
    for directory, subdirs, files in os.walk(root):
        subdirs[:] = [name for name in subdirs if not os.path.islink(os.path.join(directory, name))]
        for name in files:
            if name.endswith(".jsonl"):
                yield os.path.join(directory, name)


def _count(value):
    # Booleans and negatives are not recorded token counts.
    return int(value) if type(value) in (int, float) and 0 <= value < 2**53 else 0


def _timestamp(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value / 1000 if value > 1e11 else float(value)
    if isinstance(value, str) and value:
        try:
            return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return 0
    return 0


def _text(value):
    return value if isinstance(value, str) else ""


def _bucket(usage, provider, model, at):
    if not isinstance(usage, dict):
        return None
    counts = {target: _count(usage.get(source)) for source, target in _TOKEN_FIELDS}
    if not any(counts.values()):
        return None
    return {
        "provider": _text(provider) or "unknown",
        "model": _text(model) or "unknown",
        **counts,
        "timestamp": at,
        "costStatus": "unavailable",
    }


@lru_cache(maxsize=256)
def _read_file(path, mtime_ns, size):
    """(workspace, usage buckets, last activity) of one transcript."""
    workspace = ""
    last = 0
    buckets = []
    seen = set()
    provider = model = ""
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(entry, dict):
                    continue
                kind = entry.get("type")
                at = _timestamp(entry.get("timestamp"))
                last = max(last, at)
                if kind == "session":
                    cwd = _text(entry.get("cwd")).replace("\\", "/").rstrip("/")
                    workspace = cwd.rsplit("/", 1)[-1]
                    continue
                if kind == "model_change":
                    provider = _text(entry.get("provider")) or provider
                    model = _text(entry.get("modelId")) or model
                    continue
                if kind not in _ENTRIES_WITH_USAGE:
                    continue
                entry_id = entry.get("id")
                if isinstance(entry_id, str):
                    # A forked or resumed session repeats earlier entries.
                    if entry_id in seen:
                        continue
                    seen.add(entry_id)
                if kind == "message":
                    message = entry.get("message")
                    if not isinstance(message, dict) or message.get("role") != "assistant":
                        continue
                    at = _timestamp(message.get("timestamp")) or at
                    bucket = _bucket(message.get("usage"), message.get("provider") or provider, message.get("model") or model, at)
                else:
                    bucket = _bucket(entry.get("usage"), entry.get("provider") or provider, entry.get("model") or model, at)
                if bucket:
                    buckets.append(bucket)
    except OSError:
        pass
    return workspace, buckets, last


def read_sessions():
    sessions = []
    for root in session_roots():
        if not os.path.isdir(root):
            continue
        agent = "omp" if f"{os.sep}.omp{os.sep}" in os.path.normpath(root) else "pi"
        for path in _transcripts(root):
            try:
                stat = os.stat(path)
            except OSError:
                continue
            if stat.st_size > _MAX_FILE_BYTES:
                continue
            workspace, usage, last = _read_file(path, stat.st_mtime_ns, stat.st_size)
            if not usage:
                continue
            sessions.append(
                {
                    "id": os.path.basename(path)[:-6],
                    "title": "",
                    "directory": workspace,
                    "createdAt": min(row["timestamp"] for row in usage if row["timestamp"]) if any(row["timestamp"] for row in usage) else last,
                    "lastActivity": last or stat.st_mtime,
                    "agent": agent,
                    "usage": usage,
                }
            )
    return sorted(sessions, key=lambda row: row["lastActivity"], reverse=True)


def usage_snapshot():
    sessions = read_sessions()
    return {"sessions": sessions, "agents": sorted({row["agent"] for row in sessions})}
