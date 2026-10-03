"""Read Junie CLI's local session ledger without running Junie or reading keys.

Schema checked against JetBrains Junie 3419.22: SessionA2uxEvent wraps
LlmResponseMetadataEvent.modelUsage. Each model usage is an additive delta;
input, output, cache input and cache creation are separate token buckets.
The optional cost has no persisted unit or billing route, so it is deliberately
not treated as USD. Live authorization and subscription billing remain untested.
"""

import json
import os
from functools import lru_cache
from pathlib import Path

TOKEN_FIELDS = {
    "inputTokens": "input",
    "outputTokens": "output",
    "cacheInputTokens": "cacheRead",
    "cacheCreateTokens": "cacheWrite",
}


def sessions_root():
    return Path(os.path.expanduser(os.environ.get("JUNIE_HOME") or "~/.junie")) / "sessions"


def _objects(path):
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                try:
                    value = json.loads(line)
                except ValueError:
                    continue
                if isinstance(value, dict):
                    yield value
    except OSError:
        return


def _count(value):
    # JSON floats, booleans and negative counts are not recorded token counts.
    return value if type(value) is int and 0 <= value < 2**63 else None


def _timestamp(value):
    value = _count(value)
    return value / 1000 if value is not None and value < 253402300800000 else 0


def _text(value):
    return value if isinstance(value, str) else ""


def _session_id(value):
    return isinstance(value, str) and value.startswith("session-") and all(c.isascii() and (c.isalnum() or c == "-") for c in value)


@lru_cache(maxsize=256)
def _read_events(path, mtime_ns, size, ctime_ns):
    # Cache only parsed metadata, never prompts, environment variables or blobs.
    usage = []
    last_activity = 0
    state = ""
    for record in _objects(Path(path)):
        at = _timestamp(record.get("timestampMs"))
        last_activity = max(last_activity, at)
        if record.get("kind") == "TaskState":
            state = _text(record.get("state"))
        if record.get("kind") != "SessionA2uxEvent":
            continue
        event = record.get("event")
        if not isinstance(event, dict):
            continue
        state = _text(event.get("state")) or state
        agent = event.get("agentEvent")
        if not isinstance(agent, dict) or agent.get("kind") != "LlmResponseMetadataEvent":
            continue
        models = agent.get("modelUsage")
        if not isinstance(models, list):
            continue
        for model in models:
            if not isinstance(model, dict):
                continue
            counts = {target: _count(model.get(source)) for source, target in TOKEN_FIELDS.items()}
            if not any(value is not None for value in counts.values()):
                continue
            # Null/missing buckets stay visibly partial; no text-length estimates.
            usage.append(
                {
                    "provider": "junie",
                    "model": _text(model.get("model")) or "unknown",
                    **{key: value or 0 for key, value in counts.items()},
                    "timestamp": at,
                    "tokensComplete": all(value is not None for value in counts.values()),
                    "costStatus": "unavailable",
                }
            )
    return usage, last_activity, state


def read_sessions():
    root = sessions_root()
    summaries = {}
    for row in _objects(root / "index.jsonl"):
        sid = row.get("sessionId")
        if _session_id(sid) and _timestamp(row.get("updatedAt")) >= _timestamp(summaries.get(sid, {}).get("updatedAt")):
            summaries[sid] = row
    try:
        directories = sorted(path for path in root.iterdir() if path.is_dir() and not path.is_symlink() and _session_id(path.name))
    except OSError:
        return []
    sessions = []
    for directory in directories:
        metadata = summaries.get(directory.name, {})
        try:
            summary = json.loads((directory / "summary.json").read_text(encoding="utf-8"))
            if isinstance(summary, dict) and summary.get("sessionId") == directory.name:
                if _timestamp(summary.get("updatedAt")) >= _timestamp(metadata.get("updatedAt")):
                    metadata = summary
        except (OSError, ValueError):
            pass
        usage, last_activity, state = [], 0, ""
        try:
            path = directory / "events.jsonl"
            stat = path.stat()
            usage, last_activity, state = _read_events(str(path), stat.st_mtime_ns, stat.st_size, stat.st_ctime_ns)
        except OSError:
            pass
        at = max(last_activity, _timestamp(metadata.get("updatedAt")), _timestamp(metadata.get("createdAt")))
        if at <= 0:
            continue
        sessions.append(
            {
                "id": directory.name,
                "title": _text(metadata.get("taskName")),
                "directory": _text(metadata.get("projectDir")),
                "createdAt": _timestamp(metadata.get("createdAt")),
                "lastActivity": at,
                "state": state or _text(metadata.get("status")),
                "usage": usage,
            }
        )
    return sorted(sessions, key=lambda row: row["lastActivity"], reverse=True)


def usage_snapshot():
    # Match the shared activity stats input, exposing only workspace basenames.
    return {
        "sessions": [{**row, "directory": row["directory"].replace("\\", "/").rstrip("/").rsplit("/", 1)[-1], "title": ""} for row in read_sessions()]
    }
