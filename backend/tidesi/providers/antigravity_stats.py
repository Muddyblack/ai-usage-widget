"""Local Antigravity activity for the Stats view, read from the CLI's session
transcripts (~/.gemini/antigravity-cli/brain/<id>/.system_generated/logs/
transcript.jsonl) and the editor's conversation folders (~/.gemini/antigravity/
brain/<id>/*.md).

A transcript is one JSON object per step: `type` (USER_INPUT, VIEW_FILE,
RUN_COMMAND, SEARCH_WEB, …), `source` (USER_EXPLICIT, MODEL, SYSTEM) and an
ISO `created_at`; some model steps also carry token counts. An editor
conversation has no transcript, only its artifacts, so it counts as a session
on the day it was last written and adds nothing else.

The result has the shape stats.activity_base() reads (the one Claude's
stats-cache.json has), with days and hours in local time. It is cached against
a fingerprint of every transcript's size and mtime, so a poll with nothing new
costs one stat() per file.
"""

import datetime
import hashlib
import json
import os
import tempfile

from .. import paths
from ..contract import epoch_of
from .antigravity_sessions import _home, _session_dirs

_CACHE_VERSION = 1
# The same bounds antigravity_sessions keeps for a transcript.
_MAX_TRANSCRIPT_BYTES = 16 * 1024 * 1024
_MAX_LINE_BYTES = 256 * 1024
# Steps that are the agent doing something, as opposed to its own replies
# (PLANNER_RESPONSE), placeholders (GENERIC) and bookkeeping.
_TOOL_STEPS = {
    "VIEW_FILE",
    "GREP_SEARCH",
    "RUN_COMMAND",
    "CODE_ACTION",
    "LIST_DIRECTORY",
    "SEARCH_WEB",
    "READ_URL_CONTENT",
    "INVOKE_SUBAGENT",
    "GENERATE_IMAGE",
    "FIND",
    "ASK_QUESTION",
}


def _num(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def _local(epoch):
    return datetime.datetime.fromtimestamp(epoch)


def _transcripts(root):
    out = []
    for _, folder in _session_dirs(root / "antigravity-cli" / "brain"):
        path = folder / ".system_generated" / "logs" / "transcript.jsonl"
        if path.is_file():
            out.append(path)
    return out


def _editor_sessions(root):
    """(id, last-written epoch) per editor conversation that has artifacts."""
    out = []
    for session_id, folder in _session_dirs(root / "antigravity" / "brain"):
        try:
            stamps = [p.stat().st_mtime for p in folder.glob("*.md")]
        except OSError:
            continue
        if stamps:
            out.append((session_id, int(max(stamps))))
    return out


def _scan(path):
    """One transcript's tally, or None when it holds no recognisable step."""
    first = last = 0
    msgs = tools = searches = 0
    tokens_in = tokens_out = tokens_cache = 0
    try:
        with path.open("rb") as stream:
            remaining = _MAX_TRANSCRIPT_BYTES
            while remaining > 0:
                line = stream.readline(min(_MAX_LINE_BYTES, remaining) + 1)
                if not line or len(line) > _MAX_LINE_BYTES:
                    break
                remaining -= len(line)
                try:
                    row = json.loads(line.decode("utf-8", errors="replace"))
                except ValueError:
                    continue
                if not isinstance(row, dict) or not isinstance(row.get("type"), str):
                    continue
                at = epoch_of(row.get("created_at"))
                if at > 0:
                    first = at if first == 0 else min(first, at)
                    last = max(last, at)
                kind = row["type"]
                if kind == "USER_INPUT":
                    msgs += 1
                elif kind in _TOOL_STEPS:
                    tools += 1
                    if kind == "SEARCH_WEB":
                        searches += 1
                tokens_in += _num(row.get("input_tokens"))
                tokens_out += _num(row.get("output_tokens"))
                tokens_cache += _num(row.get("cache_read_tokens"))
    except OSError:
        return None
    if first == 0:
        return None
    return {
        "start": first,
        "end": last,
        "msgs": msgs,
        "tools": tools,
        "searches": searches,
        "input": tokens_in,
        "output": tokens_out,
        "cacheRead": tokens_cache,
    }


def _build(records):
    daily = {}
    hours = {}
    for r in records:
        start = _local(r["start"])
        day = start.strftime("%Y-%m-%d")
        d = daily.setdefault(day, {"sessions": 0, "msgs": 0, "tools": 0, "tokens": 0})
        d["sessions"] += 1
        d["msgs"] += r["msgs"]
        d["tools"] += r["tools"]
        d["tokens"] += r["input"] + r["output"]
        hours[str(start.hour)] = hours.get(str(start.hour), 0) + 1

    longest = max(records, key=lambda r: r["end"] - r["start"], default=None)
    days = sorted(daily)
    return {
        "version": 1,
        "source": "antigravity-transcripts",
        "lastComputedDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "totalSessions": len(records),
        "totalMessages": sum(r["msgs"] for r in records),
        "totalToolCalls": sum(r["tools"] for r in records),
        "totalWebSearches": sum(r["searches"] for r in records),
        "totalInputTokens": sum(r["input"] for r in records),
        "totalOutputTokens": sum(r["output"] for r in records),
        "totalCachedTokens": sum(r["cacheRead"] for r in records),
        "firstSessionDate": days[0] if days else "",
        "dailyActivity": [
            {"date": d, "sessionCount": daily[d]["sessions"], "messageCount": daily[d]["msgs"], "toolCallCount": daily[d]["tools"]} for d in days
        ],
        "dailyMessages": [{"date": d, "total": daily[d]["msgs"]} for d in days],
        "dailyTokens": [{"date": d, "total": daily[d]["tokens"]} for d in days],
        "longestSession": {
            "duration": (longest["end"] - longest["start"]) * 1000 if longest else 0,
            "messageCount": longest["msgs"] if longest else 0,
        },
        "hourCounts": hours,
    }


def _fingerprint(files, editors):
    digest = hashlib.sha256()
    for path in files:
        stat = path.stat()
        digest.update(f"{path}\0{stat.st_mtime_ns}\0{stat.st_size}\n".encode("utf-8", "surrogateescape"))
    for session_id, stamp in editors:
        digest.update(f"e:{session_id}\0{stamp}\n".encode())
    return digest.hexdigest()


def _cache_path(root):
    key = hashlib.sha256(os.fsencode(os.path.realpath(root))).hexdigest()[:24]
    return os.path.join(paths.cache_home(), "kde-ai-usage", f"antigravity-stats-{key}.json")


def _read_cache(path, fingerprint):
    try:
        with open(path, encoding="utf-8") as fh:
            payload = json.load(fh)
    except (OSError, ValueError):
        return None
    if isinstance(payload, dict) and payload.get("version") == _CACHE_VERSION and payload.get("fingerprint") == fingerprint:
        stats = payload.get("stats")
        return stats if isinstance(stats, dict) else None
    return None


def _write_cache(path, fingerprint, stats):
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".antigravity-stats-", dir=directory)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as fh:
                json.dump({"version": _CACHE_VERSION, "fingerprint": fingerprint, "stats": stats}, fh, separators=(",", ":"))
            os.replace(temporary, path)
        except OSError:
            try:
                os.unlink(temporary)
            except OSError:
                pass
    except OSError:
        pass


def get_antigravity_stats():
    """The stats blob, or {} when Antigravity has left no sessions here."""
    root = _home()
    files = _transcripts(root)
    editors = _editor_sessions(root)
    if not files and not editors:
        return {}

    try:
        fingerprint = _fingerprint(files, editors)
    except OSError:
        fingerprint = None
    cache = _cache_path(root)
    if fingerprint is not None:
        cached = _read_cache(cache, fingerprint)
        if cached is not None:
            return cached

    records = [r for r in (_scan(p) for p in files) if r is not None]
    seen = {p.parent.parent.parent.name for p in files}
    for session_id, stamp in editors:
        # A conversation the CLI also logged is already counted, in full.
        if session_id not in seen:
            records.append({"start": stamp, "end": stamp, "msgs": 0, "tools": 0, "searches": 0, "input": 0, "output": 0, "cacheRead": 0})
    stats = _build(records) if records else {}
    if fingerprint is not None and stats:
        _write_cache(cache, fingerprint, stats)
    return stats
