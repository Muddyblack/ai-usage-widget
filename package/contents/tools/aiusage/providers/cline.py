"""Cline CLI: local session statistics.

The Cline CLI writes one JSON record per session to
~/.cline/data/sessions/<id>/<id>.json — provider, model, workspace, start and
end time, and the session's token and cost totals (`metadata.aggregateUsage`,
which includes any sub-agents). Only those fields are kept: the prompt, the
title, the git remote and the transcript beside it are never read into the
result. The `prompt` field looked at first glance like the session's opening
message — it is not: Cline overwrites it as the session runs, so a live
record's `prompt` can hold a rolling snapshot of recent tool output, grep
results and file paths, including from other projects entirely. Reading it
into any result, redacted or not, would be exactly the transcript leak this
module exists to prevent.
"""

import json
import math
import os

from ..contract import epoch_of, num


def _sessions_dir():
    return os.environ.get("CLINE_SESSIONS_DIR") or os.path.expanduser("~/.cline/data/sessions")


def _usage(meta):
    usage = meta.get("aggregateUsage") if isinstance(meta.get("aggregateUsage"), dict) else meta.get("usage")
    usage = usage if isinstance(usage, dict) else {}
    cost = num(usage.get("totalCost", meta.get("totalCost")))
    if type(cost) not in (int, float) or not math.isfinite(cost) or cost <= 0:
        cost = None
    return {
        "input": num(usage.get("inputTokens")),
        "output": num(usage.get("outputTokens")),
        "cacheRead": num(usage.get("cacheReadTokens")),
        "cacheWrite": num(usage.get("cacheWriteTokens")),
        "cost": cost,
    }


def _read_session(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    started = epoch_of(data.get("started_at") or "")
    if started <= 0:
        return None
    meta = data.get("metadata") if isinstance(data.get("metadata"), dict) else {}
    workspace = data.get("workspace_root") or data.get("cwd") or ""
    # The directory name doubles as the fallback id — Cline names each
    # session's folder and file after its own session id.
    fallback_id = os.path.basename(os.path.dirname(path))
    session_id = data.get("session_id") if isinstance(data.get("session_id"), str) and data.get("session_id") else fallback_id
    return {
        "startedAt": started,
        "endedAt": epoch_of(data.get("ended_at") or ""),
        "provider": data.get("provider") if isinstance(data.get("provider"), str) else "",
        "model": data.get("model") if isinstance(data.get("model"), str) else "",
        "workspace": os.path.basename(workspace.rstrip("/\\")) if isinstance(workspace, str) else "",
        "status": data.get("status") if isinstance(data.get("status"), str) else "",
        # Internal only — never returned by get_cline_sessions(), which is
        # the redacted view every stats consumer sees.
        "sessionId": session_id,
        **_usage(meta),
    }


def _read_all_sessions():
    root = _sessions_dir()
    if not os.path.isdir(root):
        return []
    try:
        entries = os.listdir(root)
    except OSError:
        return []
    sessions = []
    for name in entries:
        record = _read_session(os.path.join(root, name, name + ".json"))
        if record is not None:
            sessions.append(record)
    sessions.sort(key=lambda s: (s["startedAt"], s["sessionId"]))
    return sessions


def get_cline_sessions():
    """Every readable session record, oldest first. {} when Cline never ran."""
    sessions = _read_all_sessions()
    if not sessions:
        return {}
    return {"sessions": [{k: v for k, v in s.items() if k != "sessionId"} for s in sessions]}


def get_cline_session_records():
    """Every readable session record with its internal session id attached.

    Internal only — for resolving a Sessions-tab entry to its resume id
    without re-scanning the directory a second time. The id must never be
    forwarded into a redacted result; ``get_cline_sessions()`` is what any
    output-facing consumer should use instead.
    """
    return _read_all_sessions()
