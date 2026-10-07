"""Shared presentation for local token ledgers; no account quota is inferred."""

from ..contract import compact_tokens, flat_window, money, provider_base, provider_error


def _period_text(period):
    text = f"{compact_tokens(period.get('tokens'))} tokens · {period.get('sessions', 0)} session"
    if period.get("sessions") != 1:
        text += "s"
    if period.get("cost", 0) > 0:
        text += f" · {money(period.get('cost'), 'USD')}"
    return text


def normalize_local_activity(now, stats, *, provider_id="opencode", label="OpenCode", accent="#B7B1B1", mode="zen", source="local SQLite"):
    if not stats.get("available"):
        return provider_error(
            provider_id,
            label,
            accent,
            now,
            f"{label}: no local sessions yet",
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
            "tooltip": f"{label} local usage\n" + "\n".join(f"{p.get('label')}: {_period_text(p)}" for p in periods),
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
