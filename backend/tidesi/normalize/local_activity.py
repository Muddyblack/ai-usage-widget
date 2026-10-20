"""Shared presentation for local token ledgers; no account quota is inferred."""

from ..contract import compact_tokens, flat_window, money, provider_base, provider_error
from ..messages import lines, tr


def _period_text(period):
    return _usage_text(period.get("sessions", 0), period.get("tokens"), period.get("cost", 0))


def _usage_text(count, tokens, cost):
    """ "1.2M tokens · 3 sessions · $0.42" as one translatable sentence."""
    tokens = compact_tokens(tokens)
    if cost > 0:
        if count == 1:
            return tr("%1 tokens · %2 session · %3", tokens, count, money(cost, "USD"))
        return tr("%1 tokens · %2 sessions · %3", tokens, count, money(cost, "USD"))
    if count == 1:
        return tr("%1 tokens · %2 session", tokens, count)
    return tr("%1 tokens · %2 sessions", tokens, count)


def normalize_local_activity(now, stats, *, provider_id="opencode", label="OpenCode", accent="#B7B1B1", mode="zen", source="local SQLite"):
    if not stats.get("available"):
        return provider_error(
            provider_id,
            label,
            accent,
            now,
            tr("%1: no local sessions yet", label),
            {"stats": stats, "source": source, "accountMode": mode},
        )
    periods = stats.get("periods") or []
    recent = next((period for period in periods if period.get("key") == "7d"), periods[-1] if periods else {})
    r = provider_base(provider_id, label, accent, now)
    r["summary"] = {
        "pct": 0,
        "text": compact_tokens(recent.get("tokens")),
        "detail": {
            "zen": "last 7 days · local Zen activity",
            "local": "last 7 days · local activity",
        }.get(mode, "last 7 days · local activity"),
        "hasChart": False,
    }
    r["quotaWindows"] = [flat_window(period.get("key"), period.get("label"), 0, 0, _period_text(period), False) for period in periods]
    r["slots"] = [
        {
            "pct": 0,
            "color": accent,
            "text": compact_tokens(recent.get("tokens")),
            "tooltip": lines(tr("%1 local usage", label), *(tr("%1: %2", p.get("label"), _period_text(p)) for p in periods)),
        }
    ]
    r["details"] = {
        "stats": stats,
        "periods": periods,
        "source": source,
        "accountMode": mode,
        "costStatus": stats.get("costStatus", "unavailable"),
        "costProvenance": "local ledger and exact model catalog where available",
    }
    return r
