"""Local Kiro activity for the Stats view.

Two sources, both optional:

* kiro-cli sessions, ~/.kiro/sessions/cli/<id>.json. Each finished user turn
  leaves a record in session_state.conversation_metadata.user_turn_metadatas:
  end_timestamp, turn_duration, total_request_count, builtin_tool_uses, model,
  and metering_usage — one {value, unit: "credit"} per request, Kiro's own
  billing unit. The token counts there are recorded as 0, so they are not used.
* Kiro IDE agent runs, <app data>/Kiro/User/globalStorage/kiro.kiroagent/
  <workspace>/<id>.chat, one file per run with metadata.modelId, startTime and
  endTime (epoch ms). The chat inside is cumulative across a conversation's
  runs, so it is not tallied; a run counts as one prompt and one request, and
  runs in one workspace less than 30 minutes apart make one session.

The result has the shape stats.activity_base() reads, with days and hours in
local time, cached against a fingerprint of every source file's size and mtime.
"""

import datetime
import glob
import hashlib
import json
import os
import tempfile

from .. import paths
from ..contract import epoch_of

_CACHE_VERSION = 1
_MAX_FILE_BYTES = 32 * 1024 * 1024
_SESSION_GAP = 30 * 60


def _num(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def _cli_dir():
    home = os.environ.get("KIRO_HOME") or os.path.expanduser("~/.kiro")
    return os.path.join(home, "sessions", "cli")


def _ide_dir():
    explicit = os.environ.get("KIRO_AGENT_DIR")
    if explicit:
        return explicit
    for base in paths.electron_app_data_dirs():
        candidate = os.path.join(base, "Kiro", "User", "globalStorage", "kiro.kiroagent")
        if os.path.isdir(candidate):
            return candidate
    return ""


def _load(path):
    try:
        if os.path.getsize(path) > _MAX_FILE_BYTES:
            return None
        with open(path, encoding="utf-8", errors="replace") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _credits(turn):
    usage = turn.get("metering_usage")
    if not isinstance(usage, list):
        return 0
    return sum(_num(u.get("value")) for u in usage if isinstance(u, dict) and u.get("unit") in ("credit", "credits"))


def _cli_sessions(files):
    """One record per CLI session that finished at least one turn."""
    out = []
    for path in files:
        data = _load(path)
        if data is None:
            continue
        meta = (data.get("session_state") or {}).get("conversation_metadata") or {}
        turns = [t for t in (meta.get("user_turn_metadatas") or []) if isinstance(t, dict)]
        events = []
        for t in turns:
            end = epoch_of(t.get("end_timestamp"))
            if end <= 0:
                continue
            duration = t.get("turn_duration") or {}
            secs = _num(duration.get("secs")) if isinstance(duration, dict) else 0
            events.append(
                {
                    "at": end - secs,
                    "requests": _num(t.get("total_request_count")) or 1,
                    "tools": _num(t.get("builtin_tool_uses")),
                    "credits": _credits(t),
                    "model": t.get("model") if isinstance(t.get("model"), str) else "",
                }
            )
        if not events:
            continue
        start = epoch_of(data.get("created_at")) or min(e["at"] for e in events)
        end = max(epoch_of(data.get("updated_at")), max(e["at"] for e in events))
        out.append({"start": start, "end": end, "events": events})
    return out


def _ide_sessions(files):
    """Agent runs, grouped into sessions per workspace by time."""
    runs = {}
    for path in files:
        data = _load(path)
        if data is None:
            continue
        meta = data.get("metadata") if isinstance(data.get("metadata"), dict) else {}
        start = _num(meta.get("startTime")) / 1000
        end = _num(meta.get("endTime")) / 1000
        if start <= 0:
            try:
                start = os.path.getmtime(path)
            except OSError:
                continue
        runs.setdefault(os.path.basename(os.path.dirname(path)), []).append(
            {
                "at": start,
                "end": max(start, end),
                "requests": 1,
                "tools": 0,
                "credits": 0,
                "model": meta.get("modelId") if isinstance(meta.get("modelId"), str) else "",
            }
        )
    out = []
    for workspace_runs in runs.values():
        workspace_runs.sort(key=lambda r: r["at"])
        current = None
        for run in workspace_runs:
            if current is None or run["at"] - current["end"] > _SESSION_GAP:
                current = {"start": run["at"], "end": run["end"], "events": []}
                out.append(current)
            current["events"].append(run)
            current["end"] = max(current["end"], run["end"])
    return out


def _build(sessions):
    daily = {}
    hours = {}
    models = {}
    for s in sessions:
        for e in s["events"]:
            local = datetime.datetime.fromtimestamp(e["at"])
            day = local.strftime("%Y-%m-%d")
            d = daily.setdefault(day, {"sessions": 0, "prompts": 0, "requests": 0, "tools": 0, "credits": 0})
            d["prompts"] += 1
            d["requests"] += e["requests"]
            d["tools"] += e["tools"]
            d["credits"] += e["credits"]
            hours[str(local.hour)] = hours.get(str(local.hour), 0) + 1
            if e["model"] and e["model"] != "auto":
                m = models.setdefault(e["model"], {"requests": 0, "credits": 0})
                m["requests"] += e["requests"]
                m["credits"] += e["credits"]
        first_day = datetime.datetime.fromtimestamp(s["start"]).strftime("%Y-%m-%d")
        daily.setdefault(first_day, {"sessions": 0, "prompts": 0, "requests": 0, "tools": 0, "credits": 0})["sessions"] += 1

    days = sorted(daily)
    events = [e for s in sessions for e in s["events"]]
    longest = max(sessions, key=lambda s: s["end"] - s["start"], default=None)
    return {
        "version": 1,
        "source": "kiro-sessions",
        "lastComputedDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "totalSessions": len(sessions),
        "totalMessages": len(events),
        "totalRequests": sum(e["requests"] for e in events),
        "totalToolCalls": sum(e["tools"] for e in events),
        "totalCredits": round(sum(e["credits"] for e in events), 4),
        "firstSessionDate": days[0] if days else "",
        "favoriteModel": max(models, key=lambda m: models[m]["requests"]) if models else "",
        "models": models,
        "dailyActivity": [
            {"date": d, "sessionCount": daily[d]["sessions"], "messageCount": daily[d]["prompts"], "toolCallCount": daily[d]["tools"]} for d in days
        ],
        "dailyRequests": [{"date": d, "total": daily[d]["requests"]} for d in days],
        "longestSession": {
            "duration": int((longest["end"] - longest["start"]) * 1000) if longest else 0,
            "messageCount": len(longest["events"]) if longest else 0,
        },
        "hourCounts": hours,
    }


def _fingerprint(files):
    digest = hashlib.sha256()
    for path in files:
        stat = os.stat(path)
        digest.update(f"{path}\0{stat.st_mtime_ns}\0{stat.st_size}\n".encode("utf-8", "surrogateescape"))
    return digest.hexdigest()


def _cache_path(cli_dir, ide_dir):
    key = hashlib.sha256(os.fsencode(os.path.realpath(cli_dir) + "\0" + ide_dir)).hexdigest()[:24]
    return os.path.join(paths.cache_home(), "kde-ai-usage", f"kiro-stats-{key}.json")


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
        descriptor, temporary = tempfile.mkstemp(prefix=".kiro-stats-", dir=directory)
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


def get_kiro_stats():
    """The stats blob, or {} when Kiro has left no finished session here."""
    cli_dir = _cli_dir()
    ide_dir = _ide_dir()
    cli_files = sorted(glob.glob(os.path.join(glob.escape(cli_dir), "*.json")))
    ide_files = sorted(glob.glob(os.path.join(glob.escape(ide_dir), "*", "*.chat"))) if ide_dir else []
    files = cli_files + ide_files
    if not files:
        return {}

    try:
        fingerprint = _fingerprint(files)
    except OSError:
        fingerprint = None
    cache = _cache_path(cli_dir, ide_dir)
    if fingerprint is not None:
        cached = _read_cache(cache, fingerprint)
        if cached is not None:
            return cached

    sessions = _cli_sessions(cli_files) + _ide_sessions(ide_files)
    stats = _build(sessions) if sessions else {}
    if fingerprint is not None and stats:
        _write_cache(cache, fingerprint, stats)
    return stats
