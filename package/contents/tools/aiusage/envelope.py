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
    "selfhosted": ("Local Models", "#38bdf8"),
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


def _local_contribution(provider, cost, status, provenance, source, billing_provider=None):
    if status not in ("exact", "partial") or not isinstance(provider, str) or not provider:
        return None
    if provider == "cline" and provenance == "actual":
        return None
    if cost is None:
        return None
    rollup_provider = billing_provider if source == "opencode" and isinstance(billing_provider, str) and billing_provider else provider
    rollup_source = source.strip().lower() if isinstance(source, str) and source.strip() else ""
    rollup = f"{rollup_provider}::{rollup_source}" if rollup_source else rollup_provider
    return rollup, cost, status


def _local_contributions(session, provenance):
    if not isinstance(session, dict):
        return []
    provider_costs = session.get("providerCosts")
    if isinstance(provider_costs, dict) and provider_costs:
        # Multi-provider OpenCode session: one contribution per upstream
        # provider; the top-level aggregate is skipped so nothing is counted
        # twice.
        contributions = []
        for provider, cost_row in provider_costs.items():
            if not isinstance(cost_row, dict):
                continue
            contributions.extend(_local_contributions({**cost_row, "provider": provider, "source": session.get("source")}, provenance))
        return contributions

    session_provenance = session.get("costProvenance")
    mixed = session_provenance == "mixed"
    if session_provenance == provenance:
        cost = _positive_finite(session.get("costUSD"))
    elif mixed:
        parent_cost = _non_negative_finite(session.get("costUSD"))
        breakdown = session.get("costBreakdown")
        if not isinstance(breakdown, dict):
            return []
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
            return []
        cost = actual_cost if provenance == "actual" else estimated_cost
    else:
        return []
    contribution = _local_contribution(
        session.get("provider"),
        cost,
        session.get("costStatus"),
        provenance,
        session.get("source"),
        billing_provider=session.get("billingProvider"),
    )
    return [contribution] if contribution is not None else []


def _local_spend_group(sessions, provenance):
    totals = {}
    partial = set()
    costs = []
    for session in sessions:
        for rollup, cost, status in _local_contributions(session, provenance):
            totals[rollup] = totals.get(rollup, 0) + cost
            costs.append(cost)
            if status == "partial":
                partial.add(rollup)

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
                **({"source": provider.rsplit("::", 1)[1]} if "::" in provider else {}),
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

    if len(selected) == 1:
        # Avoid starting a worker for the common single-provider case. Apart
        # from being cheaper, this keeps in-process callers on Windows from
        # blocking while ThreadPoolExecutor starts its first thread.
        providers = [fetch_one(selected[0])]
    elif selected:
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
