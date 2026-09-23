"""Aggregate lifetime Codex usage from ~/.codex/sessions rollouts into a stats
blob shaped like Claude's ~/.claude/stats-cache.json.

Results are cached per normalized sessions home and only recomputed when the
rollout store's shared source fingerprint changes. The cache is keyed by an
opaque digest of the canonical sessions and config paths, so two different
``CODEX_HOME`` values can never share statistics.
"""

import datetime
import hashlib
import hmac
import itertools
import json
import os
import re
import tempfile

from .. import paths
from ..contract import _parse_utc
from ..session_manifest import source_fingerprint
from .openai_credentials import codex_home

_DATE_RE = re.compile(r".*/(\d{4})/(\d{2})/(\d{2})/[^/]*$")
_TOML_KEY_RE_CACHE = {}
_CACHE_VERSION = 2


def _field(text, key):
    marker = f'"{key}":"'
    i = text.find(marker)
    if i < 0:
        return ""
    start = i + len(marker)
    j = text.find('"', start)
    return text[start:j] if j >= 0 else ""


def _num_field(text, key):
    marker = f'"{key}":'
    i = text.find(marker)
    if i < 0:
        return 0
    chunk = text[i + len(marker) : i + len(marker) + 24]
    out = ""
    for c in chunk:
        if c.isdigit():
            out += c
        else:
            break
    return int(out) if out else 0


def _grep_toml(path, key):
    if not os.path.isfile(path):
        return ""
    pattern = _TOML_KEY_RE_CACHE.get(key)
    if pattern is None:
        pattern = re.compile(r"^\s*" + re.escape(key) + r'\s*=\s*"([^"]*)"')
        _TOML_KEY_RE_CACHE[key] = pattern
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = pattern.match(line)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return ""


def _iter_jsonl_files(sessions_dir):
    for root, _dirs, files in os.walk(sessions_dir):
        for name in files:
            if name.endswith(".jsonl"):
                yield os.path.join(root, name)


def _cache_key(sessions, config_file):
    """Opaque identity for one normalized Codex home.

    The canonical sessions path and config file path are joined and hashed so
    only the digest ever reaches disk — never the paths themselves. Two
    different ``CODEX_HOME`` values resolve to different sessions/config paths
    and therefore different cache files.
    """
    normalized = "\0".join(os.path.normcase(os.path.realpath(os.path.abspath(os.path.expanduser(path)))) for path in (sessions, config_file))
    return hashlib.sha256(os.fsencode(normalized)).hexdigest()


def _shared_fingerprint(files, config_file):
    """One opaque digest over every rollout file plus the config file.

    Each record is the task-10 ``SourceFingerprint`` triple (opaque source id,
    mtime_ns, size), so the shared digest changes when a rollout is added,
    removed, renamed, or rewritten — and stays stable when nothing changed.
    Raises ``OSError`` if a listed rollout disappears mid-walk; the caller then
    treats the store as changed and rescans.
    """
    records = []
    for path in files:
        stat = os.stat(path)
        fp = source_fingerprint(path, stat.st_mtime_ns, stat.st_size)
        records.append((fp.source_id, fp.mtime_ns, fp.size))
    try:
        stat = os.stat(config_file)
        fp = source_fingerprint(config_file, stat.st_mtime_ns, stat.st_size)
        records.append((fp.source_id, fp.mtime_ns, fp.size))
    except OSError:
        pass
    records.sort()
    encoded = json.dumps(records, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _read_cache(path, key, fingerprint):
    """Return the cached stats only when home and fingerprint both match."""
    try:
        with open(path, encoding="utf-8") as fh:
            payload = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(payload, dict) or payload.get("version") != _CACHE_VERSION:
        return None
    stored_home = payload.get("home")
    if not isinstance(stored_home, str) or not hmac.compare_digest(stored_home, key):
        return None
    stored_fingerprint = payload.get("fingerprint")
    if not isinstance(stored_fingerprint, str) or not hmac.compare_digest(stored_fingerprint, fingerprint):
        return None
    stats = payload.get("stats")
    return stats if isinstance(stats, dict) else None


def _write_cache(path, key, fingerprint, stats):
    payload = {"version": _CACHE_VERSION, "home": key, "fingerprint": fingerprint, "stats": stats}
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".codex-stats-", dir=directory)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, separators=(",", ":"))
            os.replace(temporary, path)
        except OSError:
            try:
                os.unlink(temporary)
            except OSError:
                pass
            raise
    except OSError:
        pass


def _secs(iso):
    if not iso:
        return 0
    v = _parse_utc(re.sub(r"\.\d+Z$", "Z", iso))
    return v if v is not None else 0


def _scan_rollout(path, date):
    start = ""
    lastpre = ""
    tk = None
    mdl = ""
    eff = ""
    tools = 0
    msgs = 0
    first = True
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                pre = line[:200]
                if first:
                    start = _field(pre, "timestamp")
                    first = False
                lastpre = pre
                if '"token_count"' in pre:
                    tk = line[:4000]
                elif '"turn_context"' in pre:
                    ctxline = line[:65536]
                    mdl = _field(ctxline, "model")
                    eff = _field(ctxline, "effort")
                elif '"function_call"' in pre or '"custom_tool_call"' in pre:
                    tools += 1
                elif '"user_message"' in pre:
                    msgs += 1
    except OSError:
        return None

    end = _field(lastpre, "timestamp")
    inp = cin = out = rea = tot = 0
    ctx = 0
    if tk is not None:
        i = tk.find("total_token_usage")
        if i >= 0:
            rest = tk[i : i + 400]
            inp = _num_field(rest, "input_tokens")
            cin = _num_field(rest, "cached_input_tokens")
            out = _num_field(rest, "output_tokens")
            rea = _num_field(rest, "reasoning_output_tokens")
            tot = _num_field(rest, "total_tokens")
        ctx = _num_field(tk, "model_context_window")

    return {
        "date": date,
        "model": mdl or "unknown",
        "effort": eff,
        "start": start,
        "end": end,
        "tools": tools,
        "msgs": msgs,
        "ctx": ctx,
        "usage": {
            "input_tokens": inp,
            "cached_input_tokens": cin,
            "output_tokens": out,
            "reasoning_output_tokens": rea,
            "total_tokens": tot,
        },
    }


def _aggregate(records, cfg_model, cfg_effort):
    s = sorted((r for r in records if r.get("date")), key=lambda r: r["start"])

    model_usage = {}
    for model, group in itertools.groupby(sorted(s, key=lambda r: r["model"]), key=lambda r: r["model"]):
        g = list(group)
        ctxs = [r["ctx"] for r in g if r["ctx"] > 0]
        model_usage[model] = {
            "inputTokens": sum(r["usage"]["input_tokens"] for r in g),
            "cachedInput": sum(r["usage"]["cached_input_tokens"] for r in g),
            "outputTokens": sum(r["usage"]["output_tokens"] for r in g),
            "reasoningTokens": sum(r["usage"]["reasoning_output_tokens"] for r in g),
            "totalTokens": sum(r["usage"]["total_tokens"] for r in g),
            "contextWindow": ctxs[-1] if ctxs else 0,
            "sessions": len(g),
        }

    daily = []
    for date, group in itertools.groupby(sorted(s, key=lambda r: r["date"]), key=lambda r: r["date"]):
        g = list(group)
        daily.append(
            {
                "date": date,
                "sessionCount": len(g),
                "messageCount": sum(r["msgs"] for r in g),
                "toolCallCount": sum(r["tools"] for r in g),
                "totalTokens": sum(r["usage"]["total_tokens"] for r in g),
            }
        )

    longest_candidates = []
    for r in s:
        ms = (_secs(r["end"]) - _secs(r["start"])) * 1000
        if ms > 0:
            longest_candidates.append({"ms": ms, "messageCount": r["msgs"]})
    longest_candidates.sort(key=lambda x: x["ms"])
    longest = longest_candidates[-1] if longest_candidates else {"ms": 0, "messageCount": 0}

    hours = {}
    for r in s:
        if r["start"]:
            h = r["start"][11:13]
            hours[h] = hours.get(h, 0) + 1

    model = cfg_model
    for r in reversed(s):
        if r["model"] not in ("unknown", ""):
            model = r["model"]
            break
    effort = cfg_effort
    for r in reversed(s):
        if r["effort"]:
            effort = r["effort"]
            break

    return {
        "version": 1,
        "source": "codex-sessions",
        "lastComputedDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "totalSessions": len(s),
        "totalMessages": sum(r["msgs"] for r in s),
        "totalTokens": sum(r["usage"]["total_tokens"] for r in s),
        "totalToolCalls": sum(r["tools"] for r in s),
        "firstSessionDate": min((r["date"] for r in s), default=""),
        "model": model,
        "effortLevel": effort,
        "modelUsage": model_usage,
        "dailyActivity": [
            {"date": d["date"], "sessionCount": d["sessionCount"], "messageCount": d["messageCount"], "toolCallCount": d["toolCallCount"]}
            for d in daily
        ],
        "dailyModelTokens": [{"date": d["date"], "total": d["totalTokens"]} for d in daily],
        "longestSession": {"duration": longest["ms"], "messageCount": longest["messageCount"]},
        "hourCounts": hours,
    }


def get_codex_stats():
    sessions = os.environ.get("CODEX_SESSIONS_DIR") or os.path.join(codex_home(), "sessions")
    config_file = os.environ.get("CODEX_CONFIG_FILE") or os.path.join(codex_home(), "config.toml")
    cache_dir = os.path.join(paths.cache_home(), "kde-ai-usage")
    key = _cache_key(sessions, config_file)
    cache_path = os.path.join(cache_dir, f"codex-stats-{key}.json")

    if not os.path.isdir(sessions):
        return {}

    files = list(_iter_jsonl_files(sessions))
    try:
        fingerprint = _shared_fingerprint(files, config_file)
    except OSError:
        fingerprint = None

    cached = None if fingerprint is None else _read_cache(cache_path, key, fingerprint)
    if cached is not None:
        return cached

    cfg_model = _grep_toml(config_file, "model")
    cfg_effort = _grep_toml(config_file, "model_reasoning_effort")

    records = []
    for f in files:
        # The rollout's date lives in its directory names; match on a
        # forward-slash spelling so a Windows path matches too.
        m = _DATE_RE.match(f.replace(os.sep, "/"))
        if not m:
            continue
        date = f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
        rec = _scan_rollout(f, date)
        if rec is not None:
            records.append(rec)

    result = _aggregate(records, cfg_model, cfg_effort)
    _write_cache(cache_path, key, fingerprint, result)

    return result
