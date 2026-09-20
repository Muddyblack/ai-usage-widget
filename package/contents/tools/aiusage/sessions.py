"""Local agent sessions across supported CLIs.

Returns a redacted list for the Sessions tab. Titles and workspace folder
names are fine; absolute paths, raw session IDs, and transcript contents never
leave here. Claude Code writes no separate summary, so its row title is a
clipped preview of that session's own *opening* prompt (from `history.jsonl`,
one line per turn — the first one only), produced by `_clip_title()`. The raw
prompt stays in the backend. Antigravity titles can contain the first user
prompt or an editor artifact heading. Clipped title previews are shortened,
not scrubbed of secrets, and may contain sensitive prompt or artifact text in
the local UI; the full prompt is never exposed. Cline's own `prompt` field
looks similar but is not: providers/cline.py explains why it stays untouched.

Each resumable entry also carries an opaque ``openKey`` (a digest of
provider + session id) so the frontends can re-open exactly that session in
the user's terminal *without* ever learning where it lives: the key is handed
back to ``get-ai-usage --open-session <key>``, which re-scans
(``collect_open_targets()``), resolves the key to the private resume
coordinates (session id, cwd, CLI argv), and spawns the terminal itself.
Keys are validated against a fresh scan at open time, so a stale listing
simply fails closed.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import time
import urllib.parse
from collections.abc import Sequence

from . import billing, pricing
from .contract import epoch_of, num
from .providers import antigravity_sessions, opencode
from .providers.cline import get_cline_sessions
from .providers.grok import grok_home
from .providers.muse import sessions_root as muse_sessions_root
from .providers.openai_credentials import codex_home
from .session_cache import SessionCache
from .session_index import (
    SessionQueryResult,
    SessionRow,
    normalize_source_ids,
    source_descriptors,
)

# Cap so a machine with years of logs stays snappy on a tab open.
_MAX_SESSIONS = 60
_SEARCH_FIELDS = ("provider", "title", "sessionName", "state", "detail")
# A session touched within this window is treated as active.
_ACTIVE_WITHIN_SEC = 15 * 60


def _basename(path):
    if not isinstance(path, str) or not path:
        return ""
    return os.path.basename(path.rstrip("/\\"))


# How much of a session's own title (Claude Code's first prompt, Cline's task
# text) shows inline. Neither CLI writes a separate short summary to disk, so
# the row shows a clipped preview.
_TITLE_PREVIEW_LEN = 60


def _format_tokens(n):
    """``1947411`` -> ``"1.95M"``; matches the K/M formatting every frontend's
    own ``formatTokens()`` already uses for the stats views, so a session
    row's count reads the same way rather than as a wall of raw digits."""
    n = float(n or 0)
    if n >= 1_000_000:
        return f"{n / 1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(int(n))


def _clip_title(text):
    """One line, collapsed whitespace, clipped to ``_TITLE_PREVIEW_LEN``."""
    if not isinstance(text, str):
        return ""
    flat = " ".join(text.split())
    if len(flat) <= _TITLE_PREVIEW_LEN:
        return flat
    return flat[:_TITLE_PREVIEW_LEN].rstrip() + "…"


def _state(last_activity, ended=False):
    if ended:
        return "idle"
    age = time.time() - last_activity
    if age < 0:
        return "idle"
    return "active" if age <= _ACTIVE_WITHIN_SEC else "idle"


def _entry(provider, title, last_activity, *, state="", session_name="", detail="", session_id="", full_title="", source=""):
    activity = int(last_activity or 0)
    if activity <= 0:
        return None
    entry = {
        "provider": provider,
        "title": title or provider,
        "sessionName": session_name or "",
        "state": state or _state(activity),
        "lastActivityAt": activity,
        "detail": detail or "",
        # Opaque resume handle — "" when this provider has no known resume
        # command (Muse) or the session id could not be established.
        "openKey": _open_key(source or provider, session_id) if session_id else "",
        "costStatus": "unavailable",
    }
    if source:
        entry["source"] = source
    # Only carried when the row's title was clipped, so a frontend can offer
    # to expand it; omitted rather than duplicating what's already the title.
    if full_title and full_title != entry["title"]:
        entry["fullTitle"] = full_title
    return entry


def _with_usage_cost(entry, provider, buckets):
    if entry is None:
        return None
    catalog = pricing.cached_catalog()
    providers = {bucket.provider for bucket in buckets if bucket.provider}
    rates = {rate_provider: catalog.get(rate_provider, {}) for rate_provider in providers or {provider}}
    return {**entry, **billing.aggregate_session_usage(buckets, rates)}


def _cline_catalog_identity(provider, model):
    provider = pricing._safe_namespace(provider)
    if not provider or not isinstance(model, str) or not model:
        return None
    if provider != "cline":
        return (provider, model) if "/" not in model else None
    native_provider, separator, native_model = model.partition("/")
    native_provider = pricing._safe_namespace(native_provider)
    if not native_provider or not separator or not native_model or "/" in native_model:
        return None
    return native_provider, native_model


def _open_key(provider, session_id):
    """Opaque handle: ``sha256(provider:id)``.

    Content-addressed rather than positional, so concurrent refreshes that add
    or drop a session cannot shift the key onto a different conversation — a
    key either resolves to the same session or fails closed.
    """
    if not provider or not session_id:
        return ""
    digest = hashlib.sha256(f"{provider}:{session_id}".encode()).hexdigest()
    return digest


def _cline_entries(*, include_all=False):
    raw = get_cline_sessions().get("sessions") or []
    ids = _cline_ids()
    if not include_all:
        raw = raw[-_MAX_SESSIONS:]
        ids = ids[-_MAX_SESSIONS:]
    out = []
    for index, s in enumerate(raw):
        ended = num(s.get("endedAt")) > 0
        last = num(s.get("endedAt")) or num(s.get("startedAt"))
        title = s.get("workspace") or s.get("model") or "Cline"
        bits = []
        tokens = num(s.get("input")) + num(s.get("output"))
        if tokens > 0:
            bits.append(f"{_format_tokens(tokens)} tok")
        model = s.get("model") or ""
        if model and model != title:
            bits.append(model)
        session_id = ids[index] if index < len(ids) else ""
        catalog_identity = _cline_catalog_identity(s.get("provider"), model)
        usage = []
        token_values = (num(s.get("input")), num(s.get("output")), num(s.get("cacheRead")), num(s.get("cacheWrite")))
        if sum(token_values) > 0 and catalog_identity is not None:
            rate_provider, rate_model = catalog_identity
            usage.append(
                billing.UsageBucket(
                    rate_provider,
                    rate_model,
                    session_id,
                    input_tokens=token_values[0],
                    output_tokens=token_values[1],
                    cache_read_tokens=token_values[2],
                    cache_write_tokens=token_values[3],
                )
            )
        out.append(
            _with_usage_cost(
                _entry(
                    "cline",
                    title,
                    last,
                    state=_state(last, ended=ended),
                    session_name=s.get("provider") or "",
                    detail=" · ".join(bits),
                    session_id=session_id,
                ),
                catalog_identity[0] if catalog_identity is not None else "",
                usage,
            )
        )
    return [e for e in out if e]


def _cline_ids():
    """Cline session ids (recorded session_id), oldest first.

    Mirrors get_cline_sessions()' ordering (sorted by startedAt) so index i
    here is index i there. Keeps the redacted entry dict free of ids.
    """
    root = os.environ.get("CLINE_SESSIONS_DIR") or os.path.expanduser("~/.cline/data/sessions")
    try:
        entries = os.listdir(root)
    except OSError:
        return []
    by_start = []
    for name in entries:
        try:
            with open(os.path.join(root, name, name + ".json"), encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict):
            continue
        started = epoch_of(data.get("started_at") or "")
        if started <= 0:
            continue
        # Resume wants the id the CLI itself recorded, not the dir name.
        session_id = data.get("session_id") if isinstance(data.get("session_id"), str) and data.get("session_id") else name
        by_start.append((started, name, session_id))
    by_start.sort(key=lambda item: (item[0], item[1]))
    return [sid for _started, _name, sid in by_start]


def _muse_entries(*, include_all=False):
    root = muse_sessions_root()
    if not os.path.isdir(root):
        return []
    out = []
    try:
        for dirpath, dirnames, filenames in os.walk(root):
            # Skip the folded view cache; the live session.jsonl is enough.
            dirnames[:] = [d for d in dirnames if d != ".msp-view-v1"]
            if "session.jsonl" not in filenames:
                continue
            path = os.path.join(dirpath, "session.jsonl")
            try:
                st = os.stat(path)
            except OSError:
                continue
            workspace = ""
            model = ""
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    for i, line in enumerate(f):
                        if i > 40:
                            break
                        try:
                            row = json.loads(line)
                        except ValueError:
                            continue
                        if not isinstance(row, dict):
                            continue
                        cwd = row.get("cwd") or row.get("workspace") or ""
                        if isinstance(cwd, str) and cwd and not workspace:
                            workspace = _basename(cwd)
                        m = row.get("model") or ""
                        if isinstance(m, str) and m and not model:
                            model = m
                        if workspace and model:
                            break
            except OSError:
                pass
            title = workspace or _basename(dirpath) or "Muse"
            out.append(
                _entry(
                    "muse",
                    title,
                    st.st_mtime,
                    session_name=model,
                    detail=model if model and model != title else "",
                )
            )
            if not include_all and len(out) >= _MAX_SESSIONS:
                break
    except OSError:
        return []
    return out


def _codex_entries(*, include_all=False):
    sessions = os.environ.get("CODEX_SESSIONS_DIR") or os.path.join(codex_home(), "sessions")
    if not os.path.isdir(sessions):
        return []
    files = []
    for root, _dirs, names in os.walk(sessions):
        for name in names:
            if name.endswith(".jsonl"):
                path = os.path.join(root, name)
                try:
                    files.append((os.path.getmtime(path), path))
                except OSError:
                    continue
    files.sort(reverse=True)
    out = []
    for mtime, path in files if include_all else files[:_MAX_SESSIONS]:
        cwd = ""
        model = ""
        # The codex CLI's own cumulative counter — the last ``token_count``
        # event in the file, not a re-derivation from message content. Only
        # this numeric total is read; nothing else past the first 80 lines is.
        total_tokens = 0
        session_id = _codex_id_from_path(path)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f):
                    if i <= 80 and ('"cwd"' in line or '"model"' in line or "turn_context" in line) and not (cwd and model):
                        try:
                            row = json.loads(line)
                        except ValueError:
                            row = None
                        if isinstance(row, dict):
                            payload = row.get("payload") if isinstance(row.get("payload"), dict) else row
                            if not cwd:
                                raw = payload.get("cwd") or ""
                                if isinstance(raw, str):
                                    cwd = _basename(raw)
                            if not model:
                                raw = payload.get("model") or ""
                                if isinstance(raw, str):
                                    model = raw
                    if '"token_count"' in line:
                        try:
                            row = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(row, dict):
                            payload = row.get("payload") if isinstance(row.get("payload"), dict) else row
                            info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
                            usage = info.get("total_token_usage") if isinstance(info.get("total_token_usage"), dict) else {}
                            tokens = num(usage.get("total_tokens"))
                            if tokens > 0:
                                total_tokens = tokens  # last one wins — it's cumulative
        except OSError:
            pass
        title = cwd or "Codex"
        bits = []
        if total_tokens > 0:
            bits.append(f"{_format_tokens(total_tokens)} tok")
        if model:
            bits.append(model)
        out.append(
            _with_usage_cost(
                _entry(
                    "openai",
                    title,
                    mtime,
                    session_name="Codex",
                    detail=" · ".join(bits),
                    session_id=session_id,
                ),
                "openai",
                _codex_session_usage(path, session_id, model),
            )
        )
    return out


def _codex_id_from_path(path):
    """Session id from a rollout filename: ``rollout-…-<uuid>.jsonl``.

    The uuid is the last five dash-separated fields of the stem, which keeps
    it distinct from the timestamp prefix (also dash-laden). Legacy rollouts
    without a uuid tail return "" — those sessions show in the tab but carry
    no resume button.
    """
    stem = os.path.basename(path)[: -len(".jsonl")]
    match = re.search(
        r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$",
        stem,
    )
    return match.group(1) if match else ""


def _claude_session_usage(path, session_id):
    buckets = []
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for index, line in enumerate(stream):
                if index > 50000:
                    break
                if '"usage"' not in line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(row, dict):
                    continue
                message = row.get("message") if isinstance(row.get("message"), dict) else {}
                usage = message.get("usage") if isinstance(message.get("usage"), dict) else {}
                model = (
                    message.get("model") if isinstance(message.get("model"), str) else row.get("model") if isinstance(row.get("model"), str) else ""
                )
                buckets.append(
                    billing.UsageBucket(
                        "anthropic",
                        model,
                        session_id,
                        num(usage.get("input_tokens")),
                        num(usage.get("output_tokens")),
                        num(usage.get("cache_read_input_tokens")),
                        num(usage.get("cache_creation_input_tokens")),
                        num(usage.get("reasoning_tokens")),
                    )
                )
    except OSError:
        return []
    return buckets


def _codex_usage_bucket(usage, model, session_id):
    if not isinstance(usage, dict):
        return None
    bucket = billing.UsageBucket(
        "openai",
        model,
        session_id,
        num(usage.get("input_tokens")),
        num(usage.get("output_tokens")),
        num(usage.get("cached_input_tokens") or usage.get("cache_read_input_tokens")),
        num(usage.get("cache_write_tokens")),
        num(usage.get("reasoning_output_tokens") or usage.get("reasoning_tokens")),
    )
    return (
        bucket
        if sum((bucket.input_tokens, bucket.output_tokens, bucket.cache_read_tokens, bucket.cache_write_tokens, bucket.reasoning_tokens)) > 0
        else None
    )


def _codex_session_usage(path, session_id, model_hint=""):
    turns = []
    cumulative = None
    model = model_hint
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for index, line in enumerate(stream):
                if index > 50000:
                    break
                if '"token_count"' not in line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(row, dict):
                    continue
                payload = row.get("payload") if isinstance(row.get("payload"), dict) else row
                raw_model = payload.get("model")
                if isinstance(raw_model, str) and raw_model:
                    model = raw_model
                info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
                last = _codex_usage_bucket(info.get("last_token_usage"), model, session_id)
                if last is not None:
                    turns.append(last)
                cumulative = _codex_usage_bucket(info.get("total_token_usage"), model, session_id) or cumulative
    except OSError:
        return []
    return turns or ([cumulative] if cumulative is not None else [])


def _grok_entries(*, include_all=False):
    sessions_dir = os.path.join(grok_home(), "sessions")
    if not os.path.isdir(sessions_dir):
        return []
    out = []
    for root, _dirs, files in os.walk(sessions_dir):
        for name in files:
            if name != "signals.json":
                continue
            path = os.path.join(root, name)
            try:
                st = os.stat(path)
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except (OSError, ValueError):
                continue
            if not isinstance(data, dict):
                continue
            models = data.get("modelsUsed") or []
            model = models[0] if isinstance(models, list) and models else ""
            tokens = num(data.get("contextTokensUsed"))
            detail_bits = []
            if tokens > 0:
                detail_bits.append(f"{_format_tokens(tokens)} tok")
            if model:
                detail_bits.append(str(model))
            # The session dir sits inside the url-encoded cwd ("%2F…"); that
            # parent is the workspace, the dir name itself is the session id.
            session_id = os.path.basename(os.path.dirname(path))
            out.append(
                _entry(
                    "grok",
                    str(model) if model else "Grok",
                    st.st_mtime,
                    session_name="Grok CLI",
                    detail=" · ".join(detail_bits),
                    session_id=session_id if session_id and session_id != "sessions" else "",
                )
            )
            if not include_all and len(out) >= _MAX_SESSIONS:
                return out
    return out


def _opencode_identity(record):
    return f"{record.database_path}\x00{record.session_id}"


def _opencode_records(reader, *, include_all=False):
    selected = {}
    for record in reader(include_all=include_all):
        previous = selected.get(record.session_id)
        if previous is None or (
            record.last_activity,
            record.created_at,
            record.database_path,
        ) > (
            previous.last_activity,
            previous.created_at,
            previous.database_path,
        ):
            selected[record.session_id] = record
    records = sorted(
        selected.values(),
        key=lambda record: (-record.last_activity, record.session_id),
    )
    return records if include_all else records[:_MAX_SESSIONS]


def _provider_costs(buckets):
    """Per-provider cost rollups for a multi-provider OpenCode session."""
    catalog = pricing.cached_catalog()
    by_provider = {}
    for bucket in buckets:
        by_provider.setdefault(bucket.provider, []).append(bucket)
    costs = {}
    for provider, provider_buckets in by_provider.items():
        result = billing.aggregate_session_usage(provider_buckets, {provider: catalog.get(provider, {})})
        if result.get("costStatus") != "unavailable":
            costs[provider] = result
    return costs


def _opencode_entries(*, include_all=False):
    out = []
    for record in _opencode_records(opencode.read_recent_sessions, include_all=include_all):
        title = _clip_title(record.title) or _basename(record.directory) or "OpenCode"
        upstream = {bucket.provider for bucket in record.usage}
        provider = next(iter(upstream)) if len(upstream) == 1 else "opencode"
        entry = _with_usage_cost(
            _entry(
                provider,
                title,
                record.last_activity,
                session_name="via OpenCode",
                detail=_basename(record.directory),
                session_id=_opencode_identity(record),
                source="opencode",
            ),
            "opencode",
            record.usage,
        )
        if entry is None:
            continue
        if len(upstream) == 1:
            entry["billingProvider"] = provider
        else:
            provider_costs = _provider_costs(record.usage)
            if provider_costs:
                entry["providerCosts"] = provider_costs
        out.append(entry)
    return out


def _opencode_targets():
    return [
        {
            "provider": "opencode",
            "id": record.session_id,
            "keyId": _opencode_identity(record),
            "cwd": record.directory,
        }
        for record in _opencode_records(opencode.read_session_targets, include_all=True)
    ]


def _antigravity_entries(*, include_all=False):
    out = []
    for record in antigravity_sessions.read_recent_sessions(include_all=include_all):
        entry = _entry(
            "antigravity",
            _clip_title(record.title) or "Antigravity",
            record.last_activity,
            session_name="Antigravity",
            session_id=record.session_id,
        )
        if entry:
            out.append(entry)
    return out


def _antigravity_targets():
    return [
        {
            "provider": "antigravity",
            "id": record.session_id,
            "keyId": record.session_id,
            "cwd": "",
        }
        for record in antigravity_sessions.read_session_targets()
    ]


def _claude_prompt_titles(root):
    """sessionId -> that session's first prompt, from ``history.jsonl``.

    Claude Code writes no separate summary to disk — the CLI's own
    ``--resume`` picker computes its labels on the fly. This is the opening
    prompt itself (the same text `--resume`'s search matches against), kept
    verbatim so ``_claude_entries()`` can derive the clipped row title.
    """
    path = os.path.join(root, "history.jsonl")
    titles = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f):
                if i > 20000:
                    break
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(row, dict):
                    continue
                sid = row.get("sessionId")
                display = row.get("display")
                if isinstance(sid, str) and sid and isinstance(display, str) and display:
                    # First occurrence wins — the file is append-only in
                    # chronological order, so that is the opening prompt.
                    titles.setdefault(sid, display)
    except OSError:
        return {}
    return titles


def _claude_session_tokens(path):
    """Sum of input/output/cache tokens across a transcript's own ``usage``
    records — the CLI's own per-message counters, never the message text
    itself. Capped generously; an unfinished sum from a huge file still beats
    none."""
    return sum(
        sum(billing._bucket_tokens(bucket)[key] for key in ("input", "output", "cache_read", "cache_write"))
        for bucket in _claude_session_usage(path, "")
    )


def _claude_entries(*, include_all=False):
    """Light scan of Claude Code project folders — mtime only, no transcripts."""
    root = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    projects = os.path.join(root, "projects")
    if not os.path.isdir(projects):
        return []
    prompt_titles = _claude_prompt_titles(root)
    out = []
    try:
        for name in os.listdir(projects):
            project = os.path.join(projects, name)
            if not os.path.isdir(project):
                continue
            project_entries = []
            try:
                for entry in os.listdir(project):
                    if not entry.endswith(".jsonl"):
                        continue
                    try:
                        stamp = os.path.getmtime(os.path.join(project, entry))
                    except OSError:
                        continue
                    project_entries.append((stamp, entry))
            except OSError:
                continue
            if not include_all:
                project_entries = sorted(project_entries, reverse=True)[:1]
            # Project dir names are path-encoded; show a short readable slice.
            folder_title = name.replace("-", "/").strip("/")
            folder_title = _basename(folder_title) or "Claude"
            for newest, newest_entry in project_entries:
                if newest <= 0:
                    continue
                # Resume target: this transcript's file name is the session
                # id claude --resume <id> expects.
                session_id = newest_entry[: -len(".jsonl")]
                full_title = prompt_titles.get(session_id, "")
                title = _clip_title(full_title) or folder_title
                transcript = os.path.join(project, newest_entry)
                buckets = _claude_session_usage(transcript, session_id)
                tokens = sum(
                    sum(billing._bucket_tokens(bucket)[key] for key in ("input", "output", "cache_read", "cache_write")) for bucket in buckets
                )
                bits = []
                if folder_title != title:
                    bits.append(folder_title)
                if tokens > 0:
                    bits.append(f"{_format_tokens(tokens)} tok")
                out.append(
                    _with_usage_cost(
                        _entry(
                            "claude",
                            title,
                            newest,
                            session_name="Claude Code",
                            detail=" · ".join(bits),
                            session_id=session_id,
                            full_title=full_title,
                        ),
                        "anthropic",
                        buckets,
                    )
                )
    except OSError:
        return []
    return out


# ── Resume in terminal ────────────────────────────────────────────────────
# The Sessions tab shows one ⧉ button per row that re-opens that exact session
# in the user's own terminal. The frontend never learns where a session lives:
# it only ever sees the opaque ``openKey`` on the entry, and hands it back to
# ``get-ai-usage --open-session <key>``, which re-scans, validates, and spawns
# the terminal itself. That keeps the redaction boundary intact — paths and ids
# stay in this module — while every frontend (KDE, Hyprland, Windows, macOS)
# shares one launcher instead of re-implementing terminal detection four ways.

# provider → CLI binary → how to resume one session id.
# ``cmd`` is argv *after* the binary; ``{id}`` is the store's session id.
_RESUME_SPECS = {
    "claude": {"bin": "claude", "cmd": ["--resume", "{id}"]},
    "openai": {"bin": "codex", "cmd": ["resume", "{id}"]},
    "opencode": {"bin": "opencode", "cmd": ["--session", "{id}"]},
    "antigravity": {"bin": "agy", "cmd": ["--conversation", "{id}"]},
    "grok": {"bin": "grok", "cmd": ["--resume", "{id}"]},
    "cline": {"bin": "cline", "cmd": ["--id", "{id}"]},
    # Muse ships no usable binary here and documents no resume/continue flag
    # — entries stay display-only (openKey "").
}

# Terminals tried in order; ``{cmd}`` is the resume line quoted for sh.
_TERMINAL_TEMPLATES = [
    ("ghostty", ["-e", "sh", "-c", "{cmd}"]),
    ("alacritty", ["-e", "sh", "-c", "{cmd}"]),
    ("kitty", ["sh", "-c", "{cmd}"]),
    ("wezterm", ["start", "--", "sh", "-c", "{cmd}"]),
    ("konsole", ["-e", "sh", "-c", "{cmd}"]),
    ("gnome-terminal", ["--", "sh", "-c", "{cmd}"]),
    ("xfce4-terminal", ["-e", "{cmd}"]),
    ("xterm", ["-e", "sh", "-c", "{cmd}"]),
]


def _matches_query(entry, query):
    needle = query.casefold()
    return any(needle in entry.get(field, "").casefold() for field in _SEARCH_FIELDS if isinstance(entry.get(field), str))


def _collect_all_sessions():
    merged = []
    complete = True
    for collector in (
        _cline_entries,
        _muse_entries,
        _codex_entries,
        _grok_entries,
        _claude_entries,
        _opencode_entries,
        _antigravity_entries,
    ):
        try:
            merged.extend(collector(include_all=True))
        except Exception:
            # One broken store must not blank the whole tab or replace its cache.
            complete = False
    return merged, complete


def collect_sessions(
    query: str = "",
    limit: int | None = None,
    offset: int = 0,
    source_ids: Sequence[str] | None = None,
) -> SessionQueryResult:
    """Return a page from the shared session index without collecting."""
    return SessionCache().query(
        query,
        limit=limit,
        offset=offset,
        source_ids=source_ids,
    )


def _page_sessions(
    merged: Sequence[SessionRow],
    query: str,
    limit: int | None,
    offset: int,
    source_ids: Sequence[str] | None = None,
) -> SessionQueryResult:
    normalized_query = (query or "").strip()
    merged = [s for s in merged if s]
    sources = source_descriptors(entry["provider"] for entry in merged)
    normalized_source_ids = normalize_source_ids(source_ids)
    if normalized_source_ids is not None:
        selected = frozenset(normalized_source_ids)
        merged = [entry for entry in merged if entry["provider"] in selected]
    merged.sort(key=lambda s: s.get("lastActivityAt") or 0, reverse=True)
    matches = [entry for entry in merged if _matches_query(entry, normalized_query)] if normalized_query else merged
    total = len(matches)
    page_limit = _MAX_SESSIONS if limit is None else limit
    page = matches[offset : offset + page_limit]
    has_more = offset + page_limit < total
    return {
        "updatedAt": int(time.time()),
        "sessions": page,
        "total": total,
        "totalExact": True,
        "offset": offset,
        "limit": page_limit,
        "hasMore": has_more,
        "sources": sources,
    }


def refresh_sessions(
    query: str = "",
    limit: int | None = None,
    offset: int = 0,
    source_ids: Sequence[str] | None = None,
) -> SessionQueryResult:
    """Refresh all session providers, then return the requested page."""
    cache = SessionCache()
    direct_rows = cache.refresh(_collect_all_sessions)
    if direct_rows is not None:
        return _page_sessions(direct_rows, query, limit, offset, source_ids)
    return cache.query(
        query,
        limit=limit,
        offset=offset,
        source_ids=source_ids,
    )


def collect_open_targets():
    """Every resumable session, keyed by its opaque handle.

    Internal only — the result carries paths and ids and is never emitted.
    ``collect_sessions()`` publishes just the digest per entry; this re-scan
    is what ``--open-session`` validates a stale or fresh key against.
    """
    targets = {}
    for collector in (
        _codex_targets,
        _grok_targets,
        _claude_targets,
        _cline_targets,
        _opencode_targets,
        _antigravity_targets,
    ):
        try:
            for target in collector():
                key = _open_key(target["provider"], target.get("keyId") or target["id"])
                if key:
                    targets[key] = target
        except Exception:
            # A broken store must not block resuming the others.
            continue
    return targets


def _codex_targets():
    sessions = os.environ.get("CODEX_SESSIONS_DIR") or os.path.join(codex_home(), "sessions")
    if not os.path.isdir(sessions):
        return []
    out = []
    for root, _dirs, names in os.walk(sessions):
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(root, name)
            session_id = _codex_id_from_path(path)
            if not session_id:
                continue
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                continue
            out.append({"provider": "openai", "id": session_id, "mtime": mtime, "cwd": ""})
    return out


def _grok_targets():
    sessions_dir = os.path.join(grok_home(), "sessions")
    if not os.path.isdir(sessions_dir):
        return []
    out = []
    for root, _dirs, files in os.walk(sessions_dir):
        if "signals.json" not in files:
            continue
        session_id = os.path.basename(root)
        if not session_id or session_id == "sessions":
            continue
        try:
            mtime = os.path.getmtime(os.path.join(root, "signals.json"))
        except OSError:
            continue
        # The session dir's parent is the url-encoded workspace ("%2F…").
        cwd = ""
        parent = os.path.basename(os.path.dirname(root.rstrip("/\\")))
        if parent.startswith("%2F"):
            try:
                cwd = urllib.parse.unquote(parent)
            except Exception:
                cwd = ""
        out.append({"provider": "grok", "id": session_id, "mtime": mtime, "cwd": cwd})
    return out


def _claude_targets():
    """Return every Claude transcript as a resume target."""
    root = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    projects = os.path.join(root, "projects")
    if not os.path.isdir(projects):
        return []
    out = []
    try:
        names = os.listdir(projects)
    except OSError:
        return []
    for name in names:
        project = os.path.join(projects, name)
        if not os.path.isdir(project):
            continue
        try:
            entries = os.listdir(project)
        except OSError:
            continue
        for entry in entries:
            if not entry.endswith(".jsonl"):
                continue
            try:
                stamp = os.path.getmtime(os.path.join(project, entry))
            except OSError:
                continue
            out.append(
                {
                    "provider": "claude",
                    "id": entry[: -len(".jsonl")],
                    "mtime": stamp,
                    "cwd": _decode_claude_dir(name),
                }
            )
    return out


def _decode_claude_dir(name):
    """Best-effort cwd from a Claude project dir name ("mnt-projects-foo").

    Claude encodes the cwd by replacing ``/`` with ``-``; a directory whose
    own name contains ``-`` cannot be split back apart, so this is a guess.
    Ambiguous rows still resume — just from $HOME when the guess misses.
    """
    guess = os.path.join("/", name.replace("-", "/"))
    return guess if os.path.isdir(guess) else ""


def _cline_targets():
    root = os.environ.get("CLINE_SESSIONS_DIR") or os.path.expanduser("~/.cline/data/sessions")
    if not os.path.isdir(root):
        return []
    out = []
    try:
        names = os.listdir(root)
    except OSError:
        return []
    for name in names:
        path = os.path.join(root, name, name + ".json")
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict):
            continue
        started = epoch_of(data.get("started_at") or "")
        if started <= 0:
            continue
        cwd = ""
        raw = data.get("workspace_root") or data.get("cwd") or ""
        if isinstance(raw, str):
            cwd = raw
        # The record's session_id may differ from the directory name; the
        # resume flag wants the id the CLI itself recorded.
        session_id = data.get("session_id") if isinstance(data.get("session_id"), str) and data.get("session_id") else name
        out.append({"provider": "cline", "id": session_id, "mtime": started, "cwd": cwd})
    return out


def _resume_argv(provider, session_id):
    """Full argv to resume this session, or None when impossible."""
    spec = _RESUME_SPECS.get(provider)
    if spec is None:
        return None
    binary = shutil.which(spec["bin"])
    if not binary:
        return None
    return [binary] + [part.format(id=session_id) for part in spec["cmd"]]


def _terminal_launch(resume_argv, cwd):
    """Spawn the resume command in the user's terminal, detached.

    Returns (ok, message). $TERMINAL wins, then the known list; if nothing is
    installed the session still resumes — headless in the background — rather
    than the button doing nothing.
    """
    resume_line = " ".join(shlex.quote(part) for part in resume_argv)
    # Keep the window open afterwards: a resumed TUI that exits immediately
    # (or fails) would otherwise vanish before it can be read.
    hold = f'{resume_line}; exec "${{SHELL:-/bin/sh}}"'
    candidates = []
    term_env = (os.environ.get("TERMINAL") or "").strip()
    if term_env:
        try:
            parsed_terminal = shlex.split(term_env, comments=False, posix=True)
        except ValueError:
            parsed_terminal = []
        metacharacters = ";&|<>$`(){}*?[]!\r\n"
        if parsed_terminal and all(not any(char in metacharacters for char in token) for token in parsed_terminal):
            terminal = shutil.which(parsed_terminal[0])
            if terminal:
                candidates.append((terminal, parsed_terminal[1:] + ["-e", "sh", "-c", hold]))
    for binary, template in _TERMINAL_TEMPLATES:
        candidates.append((binary, [part.format(cmd=hold) for part in template]))
    for binary, args in candidates:
        exe = binary if os.path.isabs(binary) else shutil.which(binary)
        if not exe:
            continue
        try:
            subprocess.Popen(
                [exe] + args,
                cwd=cwd or None,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return True, f"opened in {os.path.basename(exe)}"
        except (OSError, ValueError):
            continue
    try:
        subprocess.Popen(
            resume_argv,
            cwd=cwd or None,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True, "resumed in the background (no terminal found)"
    except (OSError, ValueError):
        return False, "could not launch session"


def open_session(open_key):
    """Resume one session (by opaque ``openKey``) in the user's terminal.

    Re-scans first, so a key from an earlier listing either resolves to the
    same session or fails closed. Returns (ok, message); the message is safe
    to show — it names binaries and terminals, never paths.
    """
    key = (open_key or "").strip()
    if not re.fullmatch(r"[0-9a-f]{64}", key):
        return False, "unknown session (stale list — refresh and try again)"
    target = collect_open_targets().get(key)
    if target is None:
        return False, "unknown session (stale list — refresh and try again)"
    provider, session_id = target["provider"], target["id"]
    spec = _RESUME_SPECS.get(provider)
    if spec is None:
        return False, f"{provider} has no resume command here yet"
    argv = _resume_argv(provider, session_id)
    if argv is None:
        return False, f"the {spec['bin']} command was not found (is it on PATH?)"
    cwd = target.get("cwd") or ""
    if cwd and not os.path.isdir(cwd):
        cwd = ""
    return _terminal_launch(argv, cwd)
