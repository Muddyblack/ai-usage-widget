"""Aggregate lifetime Muse Code usage from the CLI's own local files.

This provider never opens a socket, and that is a deliberate design constraint
rather than an accident of implementation.

Muse is the one vendor here whose plan quota cannot be read for free. The
Current/Weekly windows the TUI's `/usage` screen shows arrive only as a
`response.subscription_usage` frame riding a live model call: they are absent
from the MSP wire schema (`muse schema generate-json-schema`), from the view
fold, from `session-index.db` and from the feature-config cache, and the CLI
exposes no `usage`/`status`/`quota` subcommand. Reading them would mean paying
for a model call to be told how much you have spent, which
docs/provider-contract.md says a statistic must not do.

The widget can still show them, but only because the user asked for it: that
half lives in providers/muse_quota.py, off unless WIDGET_MUSE_QUOTA is set.
Keeping it in a separate module is the point — *this* module has no HTTP client
and no credential read at all, so the default path cannot start costing anybody
money by accident. A test asserts it against this module's import graph.

What it reads instead, all written by Muse itself:

  ~/.config/muse/auth.json                     login presence + display identity
  ~/.config/muse/settings.json                 the model currently selected
  ~/.local/share/muse/model-catalog/*.json     every model, its context limit
                                               and its price list
  ~/.local/share/muse/sessions/**/session.jsonl per-session counters
  ~/.local/share/muse/sessions/.msp-view-v1/…  the folded counted-once totals

No model id, context window or price is hardcoded here: they all come from the
catalog the CLI caches on disk, so a new Muse model needs no change to this
file. Prices are what make the spend estimate possible offline — Muse ships its
own price list, which no other provider in this widget does.

Only counters, model ids and workspace folder names ever leave this module: no
prompt text, tool arguments, file contents or absolute paths. Results are cached
and recomputed only when a session file is newer than the cache, mirroring
providers/codex_stats.py.
"""

import datetime
import glob
import json
import os
import re

from .. import config as _config
from .. import paths
from ..billing import price_models
from ..contract import num

_DATE_RE = re.compile(r"/(\d{4})/(\d{2})/(\d{2})/[^/]+/")
_MAX_FILE_BYTES = 64 * 1024 * 1024
_VIEW_DIR = ".msp-view-v1"


def _data_home():
    return paths.data_home()


def _config_home():
    return paths.config_home()


def sessions_root():
    return os.environ.get("MUSE_SESSIONS_DIR") or os.path.join(_data_home(), "muse", "sessions")


def _catalog_dir():
    return os.environ.get("MUSE_CATALOG_DIR") or os.path.join(_data_home(), "muse", "model-catalog")


def _auth_path():
    return os.environ.get("MUSE_AUTH_PATH") or os.path.join(_config_home(), "muse", "auth.json")


def _settings_path():
    return os.environ.get("MUSE_SETTINGS_PATH") or os.path.join(_config_home(), "muse", "settings.json")


def _read_json(path):
    """None on anything unreadable or malformed. These are other programs'
    files: a corrupt one must cost the provider a field, never the run."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def auth_meta():
    """The CLI login slot (providers.meta), or None when the store is missing,
    unreadable or holds no meta login.

    This module reads only the identity fields from it. The stored api_key is
    for providers/muse_quota.py, the opt-in billed path — which is a separate
    module precisely so that nothing on the free path can reach a credential or
    a socket."""
    doc = _read_json(_auth_path())
    if not isinstance(doc, dict):
        return None
    providers = doc.get("providers")
    if not isinstance(providers, dict):
        return None
    meta = providers.get("meta")
    return meta if isinstance(meta, dict) else None


def auth_presence():
    """Whether a Muse login exists — presence only, never the credential."""
    return auth_meta() is not None


def configured_model():
    """The model the CLI would use on its next run, from its own settings."""
    doc = _read_json(_settings_path())
    if isinstance(doc, dict) and isinstance(doc.get("model"), str):
        return doc["model"]
    return ""


def model_catalog():
    """{model_id: {label, context, output, input$, output$, cached$, currency,
    current, default}} from the catalog the CLI caches after talking to the
    provider. Empty when the CLI has never fetched one.

    The filename hex-encodes provider and profile (`6d657461__p746268` is
    meta/tbh), so the directory is globbed rather than reconstructed.
    """
    catalog = {}
    try:
        files = sorted(glob.glob(os.path.join(_catalog_dir(), "*.json")))
    except OSError:
        return catalog
    for path in files:
        doc = _read_json(path)
        rows = doc.get("rows") if isinstance(doc, dict) else None
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            model_id = row.get("model_id")
            if not isinstance(model_id, str) or model_id == "":
                continue
            cost = row.get("cost") if isinstance(row.get("cost"), dict) else {}
            catalog[model_id] = {
                "label": row.get("display_label") if isinstance(row.get("display_label"), str) else model_id,
                "context": num(row.get("context_limit")),
                "output": num(row.get("output_limit")),
                "input$": num(cost.get("input")),
                "output$": num(cost.get("output")),
                "cached$": num(cost.get("cached")) if cost.get("cached") is not None else None,
                "currency": cost.get("currency") if isinstance(cost.get("currency"), str) else "USD",
                "current": row.get("is_current") is True,
                "default": row.get("is_default") is True,
            }
    return catalog


def _pricing_table(catalog):
    """The {model: {input, output, cached}} shape billing.price_models wants —
    USD per million tokens, exactly as the catalog states them."""
    return {
        name: {"input": row["input$"], "output": row["output$"], "cached": row["cached$"]}
        for name, row in catalog.items()
        if row["input$"] or row["output$"]
    }


def _iter_session_files(root):
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if name != "session.jsonl":
                continue
            path = os.path.join(dirpath, name)
            posix = path.replace(os.sep, "/")
            m = _DATE_RE.search(posix)
            if not m:
                continue
            yield path, f"{m.group(1)}-{m.group(2)}-{m.group(3)}", "/subagent/" in posix


def _scan_file(path):
    """Aggregate one session.jsonl into a record. Pure counters: no prompt
    text, tool arguments or file contents are retained — only event kinds,
    model ids, token numbers and the workspace folder name."""
    calls = []
    configured = []
    tool_calls = 0
    user_msgs = 0
    asst_msgs = 0
    turns = 0
    first_ts = 0
    last_ts = 0
    workspace = ""
    try:
        if os.path.getsize(path) > _MAX_FILE_BYTES:
            return None
    except OSError:
        return None
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return None
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            ts = num(rec.get("recorded_at"))
            if ts > 0:
                ts = ts / 1000000
                if first_ts == 0 or ts < first_ts:
                    first_ts = ts
                if ts > last_ts:
                    last_ts = ts
            payload = rec.get("payload")
            if not isinstance(payload, dict):
                continue
            record = payload.get("record") if isinstance(payload.get("record"), dict) else {}
            if rec.get("payload_type") == "run.model.configured":
                model_id = record.get("model_id") or payload.get("model_id")
                if isinstance(model_id, str) and model_id:
                    configured.append(model_id)
                continue
            if rec.get("payload_type") == "runtime.session.metadata":
                root = record.get("workspace_root")
                if isinstance(root, str) and root:
                    # Folder name only: enough to tell projects apart in the
                    # tab, without putting a filesystem layout in the envelope.
                    workspace = os.path.basename(root.rstrip("/\\")) or root
                continue
            event = payload.get("event")
            if not isinstance(event, dict):
                continue
            kind = event.get("kind")
            if kind == "model_completed":
                usage = event.get("usage")
                usage = usage if isinstance(usage, dict) else {}
                calls.append(
                    {
                        "model": str(event.get("model") or ""),
                        "run": str(payload.get("run_id") or ""),
                        "in": num(usage.get("input_tokens")),
                        "out": num(usage.get("output_tokens")),
                        "cached": num(usage.get("cached_tokens")),
                        "reasoning": num(usage.get("reasoning_tokens")),
                    }
                )
            elif kind == "assistant_tool_calls_committed":
                tool_calls += len(event.get("tool_calls") or [])
            elif kind == "user_prompt_display":
                user_msgs += 1
            elif kind == "assistant_message_committed":
                asst_msgs += 1
            elif kind == "terminal":
                turns += 1
    return {
        "calls": calls,
        "configured": configured,
        "toolCalls": tool_calls,
        "userMsgs": user_msgs,
        "asstMsgs": asst_msgs,
        "turns": turns,
        "firstTs": first_ts,
        "lastTs": last_ts,
        "workspace": workspace,
    }


def _snapshot_tokens(root, session_id):
    """The session's folded counted-once totals, or None.

    `.msp-view-v1/<session>/snapshot-*.json` is the same fold the TUI's
    `/usage` screen prints, and its `tokenUsage` member is the server-derived
    counted-once block — the numbers the wire schema says clients should
    display and sum rather than re-deriving the provider's cache convention.
    Preferring it keeps our per-session figure identical to what `/usage`
    shows; it is absent (null) until a model call reports usage, and then the
    raw per-call sums below stand in.
    """
    try:
        files = glob.glob(os.path.join(root, _VIEW_DIR, session_id, "snapshot-*.json"))
        newest = max(files, key=os.path.getmtime) if files else ""
    except OSError:
        return None
    if not newest:
        return None
    doc = _read_json(newest)
    if not isinstance(doc, dict):
        return None
    state = ((doc.get("view_materialization") or {}) if isinstance(doc.get("view_materialization"), dict) else {}).get("current_state")
    if not isinstance(state, dict):
        return None
    usage = state.get("tokenUsage")
    if not isinstance(usage, dict):
        return None
    total = num(usage.get("totalTokens"))
    prompt = num(usage.get("promptTokens"))
    output = num(usage.get("outputTokens"))
    if total <= 0 and prompt <= 0 and output <= 0:
        return None
    return {"in": prompt, "out": output, "total": total or (prompt + output)}


def _aggregate(records, catalog):
    s = sorted((r for r in records if r.get("date")), key=lambda r: r["start"])

    per_model = {}
    for r in s:
        for call in r["calls"]:
            name = call["model"] or r["model"] or "unknown"
            e = per_model.setdefault(name, {"in": 0, "out": 0, "cached": 0, "reasoning": 0, "sessions": set()})
            e["in"] += call["in"]
            e["out"] += call["out"]
            e["cached"] += call["cached"]
            e["reasoning"] += call["reasoning"]
            e["sessions"].add(r["key"])

    priced = price_models(
        [{"model": name, "input_tokens": e["in"], "output_tokens": e["out"], "cached_tokens": e["cached"]} for name, e in per_model.items()],
        _pricing_table(catalog),
    )

    model_usage = {}
    for name, e in per_model.items():
        # A model that reported no tokens at all is noise, not a row: Muse
        # records completed calls whose usage block never arrived, and an
        # "unknown · 0 in 0 out" line just makes the breakdown look broken.
        if e["in"] + e["out"] + e["cached"] + e["reasoning"] <= 0:
            continue
        row = catalog.get(name) or {}
        model_usage[name] = {
            "inputTokens": e["in"],
            "outputTokens": e["out"],
            "cachedTokens": e["cached"],
            "reasoningTokens": e["reasoning"],
            "totalTokens": e["in"] + e["out"],
            "sessions": len(e["sessions"]),
            # The catalog's real context limit, not the largest prompt observed.
            "contextWindow": row.get("context", 0),
            "costUSD": (priced["models"].get(name) or {}).get("cost_usd", 0),
        }

    daily = {}
    for r in s:
        d = daily.setdefault(r["date"], {"sessions": 0, "msgs": 0, "tools": 0, "out": 0})
        if not r["subagent"]:
            d["sessions"] += 1
        d["msgs"] += r["userMsgs"] + r["asstMsgs"]
        d["tools"] += r["toolCalls"]
        d["out"] += sum(c["out"] for c in r["calls"])

    longest = {"ms": 0, "messageCount": 0}
    for r in s:
        ms = (r["end"] - r["start"]) * 1000 if r["end"] > r["start"] > 0 else 0
        if ms > longest["ms"]:
            longest = {"ms": round(ms), "messageCount": r["userMsgs"] + r["asstMsgs"]}

    hours = {}
    for r in s:
        if r["start"] > 0:
            # UTC, like every other provider's peak-hour bucket.
            h = datetime.datetime.fromtimestamp(r["start"], datetime.timezone.utc).strftime("%H")
            key = h.lstrip("0") or "0"
            hours[key] = hours.get(key, 0) + 1

    workspaces = {}
    for r in s:
        if r["workspace"] and not r["subagent"]:
            workspaces[r["workspace"]] = workspaces.get(r["workspace"], 0) + 1
    top_workspaces = sorted(workspaces.items(), key=lambda kv: (-kv[1], kv[0]))[:5]

    # What the user runs today comes from the CLI's own setting; the logs only
    # answer what past sessions used.
    model = configured_model()
    if not model:
        for r in reversed(s):
            if r["model"]:
                model = r["model"]
                break
    if not model:
        for name, row in catalog.items():
            if row.get("current") or row.get("default"):
                model = name
                break

    currency = ""
    for name in (model, *catalog):
        row = catalog.get(name)
        if row:
            currency = row.get("currency") or "USD"
            break

    return {
        "version": 1,
        "source": "muse-sessions",
        "lastComputedDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "totalSessions": sum(1 for r in s if not r["subagent"]),
        "subagentSessions": sum(1 for r in s if r["subagent"]),
        "totalMessages": sum(r["userMsgs"] + r["asstMsgs"] for r in s),
        "totalTokens": sum(r["tokensTotal"] for r in s),
        "totalInputTokens": sum(r["tokensIn"] for r in s),
        "totalOutputTokens": sum(r["tokensOut"] for r in s),
        "totalCachedTokens": sum(c["cached"] for r in s for c in r["calls"]),
        "totalReasoningTokens": sum(c["reasoning"] for r in s for c in r["calls"]),
        "totalCostUSD": priced["totalCostUSD"],
        "totalToolCalls": sum(r["toolCalls"] for r in s),
        "totalTurns": sum(r["turns"] for r in s),
        "totalModelCalls": sum(len(r["calls"]) for r in s),
        "contextWindow": max([row.get("context", 0) for row in catalog.values()] or [0]),
        "workspaceCount": len(workspaces),
        "topWorkspaces": [{"name": name, "sessions": count} for name, count in top_workspaces],
        "firstSessionDate": min((r["date"] for r in s), default=""),
        "model": model,
        "currency": currency or "USD",
        "modelUsage": model_usage,
        "dailyActivity": [
            {"date": date, "sessionCount": d["sessions"], "messageCount": d["msgs"], "toolCallCount": d["tools"]} for date, d in sorted(daily.items())
        ],
        "dailyModelTokens": [{"date": date, "total": d["out"]} for date, d in sorted(daily.items())],
        "longestSession": {"duration": longest["ms"], "messageCount": longest["messageCount"]},
        "hourCounts": hours,
    }


def _session_record(path, date, subagent, root):
    scanned = _scan_file(path)
    if scanned is None:
        return None
    session_id = os.path.basename(os.path.dirname(path))
    raw_in = sum(c["in"] for c in scanned["calls"])
    raw_out = sum(c["out"] for c in scanned["calls"])
    folded = _snapshot_tokens(root, session_id) if not subagent else None
    return {
        "key": f"{date}:{session_id}",
        "date": date,
        "subagent": subagent,
        "start": scanned["firstTs"],
        "end": scanned["lastTs"],
        "calls": scanned["calls"],
        "model": scanned["configured"][-1] if scanned["configured"] else "",
        "toolCalls": scanned["toolCalls"],
        "userMsgs": scanned["userMsgs"],
        "asstMsgs": scanned["asstMsgs"],
        "turns": scanned["turns"],
        "workspace": scanned["workspace"],
        "tokensIn": folded["in"] if folded else raw_in,
        "tokensOut": folded["out"] if folded else raw_out,
        "tokensTotal": folded["total"] if folded else raw_in + raw_out,
    }


def _input_mtimes(root, files):
    """Every file the cached blob is derived from, not just the session logs.

    Pricing, currency and the context window come from the catalog, the model
    from the CLI's settings, and the counted-once per-session totals from the
    `.msp-view-v1` snapshots. A snapshot or a re-fetched catalog lands without
    any session.jsonl being touched, so keying staleness on the logs alone
    served stale cost and token figures until the next session wrote."""
    for path, _date, _sub in files:
        yield os.path.getmtime(path)
    for path in glob.glob(os.path.join(_catalog_dir(), "*.json")):
        yield os.path.getmtime(path)
    for path in glob.glob(os.path.join(root, _VIEW_DIR, "*", "snapshot-*.json")):
        yield os.path.getmtime(path)
    settings = _settings_path()
    if os.path.isfile(settings):
        yield os.path.getmtime(settings)


def get_muse_stats():
    """The lifetime activity blob, or {} when Muse has never run here."""
    root = sessions_root()
    if not os.path.isdir(root):
        return {}
    try:
        files = list(_iter_session_files(root))
    except OSError:
        return {}
    if not files:
        return {}

    cache_path = os.path.join(_config.cache_dir(), "muse-stats.json")
    if os.path.isfile(cache_path):
        try:
            cache_mtime = os.path.getmtime(cache_path)
            stale = any(mt > cache_mtime for mt in _input_mtimes(root, files))
        except OSError:
            stale = True
        if not stale:
            cached = _read_json(cache_path)
            if isinstance(cached, dict) and cached:
                return cached

    catalog = model_catalog()
    records = [rec for rec in (_session_record(p, d, sub, root) for p, d, sub in files) if rec is not None]
    stats = _aggregate(records, catalog)
    try:
        os.makedirs(_config.cache_dir(), exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as fh:
            json.dump(stats, fh)
    except OSError:
        pass
    return stats


def get_muse_usage():
    slot = auth_meta()
    meta = slot or {}
    stats = get_muse_stats()
    return {
        "hasLogin": slot is not None,
        "email": str(meta.get("user_email") or ""),
        "fullName": str(meta.get("user_full_name") or ""),
        "stats": stats,
    }
