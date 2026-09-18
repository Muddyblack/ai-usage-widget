"""Envelope assembly — fetch a set of providers, wrap them in the outer object.

Split out of __main__ so that every in-process consumer builds the identical
envelope: the JSON backend the QML frontends call, and the terminal frontend in
aiusage.cli. See docs/provider-contract.md for the shape produced here.
"""

import math
import time
from concurrent.futures import ThreadPoolExecutor

from . import config
from .collect import collect
from .contract import SCHEMA_VERSION, provider_error, status_summary
from .normalize import normalize

# Name and accent for a provider whose fetch raised — the ones its normalizer
# uses, which never runs in that case.
_CRASH_LABELS = {
    "claude": ("Claude", "#cc785c"),
    "antigravity": ("Antigravity", "#4285f4"),
    "openai": ("OpenAI", "#10a37f"),
    "kiro": ("Kiro", "#8b5cf6"),
    "mistral": ("Mistral", "#ff7000"),
    "openrouter": ("OpenRouter", "#9333ea"),
    "ollama": ("Ollama Cloud", "#f0f0f0"),
    "grok": ("Grok", "#e6e6e6"),
    "zai": ("Z.AI", "#126ef4"),
    "copilot": ("Copilot", "#8b5cf6"),
    "deepseek": ("DeepSeek", "#4f8cff"),
    "kimi": ("Kimi", "#1e3a8a"),
    "muse": ("Muse", "#0064e0"),
    "cursor": ("Cursor", "#e6e6e6"),
    "cline": ("Cline", "#e6e6e6"),
}


# Shared with the Swift decoder: permit binary-float roundoff only, not a USD mismatch.
_MIXED_COST_REL_TOLERANCE = 1e-9
_MIXED_COST_ABS_TOLERANCE = 1e-12


def _positive_finite(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        number = float(value)
    except (OverflowError, TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number > 0 else None


def _non_negative_finite(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        number = float(value)
    except (OverflowError, TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number >= 0 else None


def enabled(cfg):
    """Provider ids switched on in the shared settings file, in contract order."""
    return [id_ for id_ in config.ALL_PROVIDERS if config.provider_enabled(cfg, id_)]


def _local_spend_group(sessions, provenance):
    totals = {}
    partial = set()
    costs = []
    for session in sessions:
        if not isinstance(session, dict):
            continue
        session_provenance = session.get("costProvenance")
        mixed = session_provenance == "mixed"
        if session_provenance == provenance:
            raw_cost = session.get("costUSD")
        elif mixed:
            parent_cost = _non_negative_finite(session.get("costUSD"))
            breakdown = session.get("costBreakdown")
            if not isinstance(breakdown, dict):
                continue
            actual_cost = _non_negative_finite(breakdown.get("actualUSD"))
            estimated_cost = _non_negative_finite(breakdown.get("estimatedUSD"))
            if (
                parent_cost is None
                or actual_cost is None
                or estimated_cost is None
                or not math.isclose(
                    math.fsum((actual_cost, estimated_cost)),
                    parent_cost,
                    rel_tol=_MIXED_COST_REL_TOLERANCE,
                    abs_tol=_MIXED_COST_ABS_TOLERANCE,
                )
            ):
                continue
            raw_cost = actual_cost if provenance == "actual" else estimated_cost
        else:
            continue
        status = session.get("costStatus")
        provider = session.get("provider")
        cost = _non_negative_finite(raw_cost) if mixed else _positive_finite(raw_cost)
        if status not in ("exact", "partial") or not isinstance(provider, str) or not provider:
            continue
        if provider == "cline" and provenance == "actual":
            continue
        if cost is None:
            continue
        totals[provider] = totals.get(provider, 0) + cost
        costs.append(cost)
        if status == "partial":
            partial.add(provider)

    if not totals:
        return {"costStatus": "unavailable"}

    total = math.fsum(costs)
    if not math.isfinite(total) or any(not math.isfinite(cost) for cost in totals.values()):
        return {"costStatus": "unavailable"}

    return {
        "totalUSD": total,
        "costStatus": "partial" if partial else "exact",
        "costProvenance": provenance,
        "providers": {
            provider: {
                "costUSD": cost,
                "costStatus": "partial" if provider in partial else "exact",
                "costProvenance": provenance,
            }
            for provider, cost in totals.items()
        },
    }


def _local_spend():
    from .sessions import collect_sessions

    try:
        result = collect_sessions()
        sessions = result.get("sessions") or []
    except Exception:  # noqa: BLE001  # noqa: BROAD_EXCEPT_OK
        sessions = []
    if not isinstance(sessions, list):
        sessions = []
    return {
        "actual": _local_spend_group(sessions, "actual"),
        "estimated": _local_spend_group(sessions, "estimated"),
    }


def crashed(id_, now, exc):
    """The error row for a provider whose collect() or normalize() raised.

    Providers are expected to turn every failure into an error of their own;
    this catches what one missed — a file in a shape nobody planned for, a
    platform difference — so that it costs that provider its tab rather than
    failing the whole envelope, and with it every other provider's."""
    label, accent = _CRASH_LABELS.get(id_, (id_, "#888888"))
    message = f"{label}: internal error ({type(exc).__name__}: {exc})"
    return provider_error(id_, label, accent, now, message, {"status": status_summary(None, id_)})


def build(selected, now=None):
    """Fetch every id in `selected` concurrently and return a full envelope."""
    if now is None:
        now = time.time()

    def fetch_one(id_):
        try:
            return normalize(collect(id_, now))
        except Exception as exc:  # noqa: BLE001  # noqa: BROAD_EXCEPT_OK
            return crashed(id_, now, exc)

    if selected:
        with ThreadPoolExecutor(max_workers=len(selected)) as pool:
            providers = list(pool.map(fetch_one, selected))
    else:
        providers = []

    # `active` is the first healthy provider; frontends fall back to it when the
    # tab they remembered is gone.
    active = ""
    for p in providers:
        if p.get("ok") is True:
            active = p.get("id") or ""
            break
    else:
        if providers:
            active = providers[0].get("id") or ""

    return {
        "schemaVersion": SCHEMA_VERSION,
        "updatedAt": int(now),
        "active": active,
        "providers": providers,
        "localSpend": _local_spend(),
    }
