from ..contract import compact_tokens, flat_window, money, provider_base, provider_error
from ..stats import opencode_stats

ACCENT = "#B7B1B1"


def _period_text(period):
    text = f"{compact_tokens(period.get('tokens'))} tokens · {period.get('sessions', 0)} session"
    if period.get("sessions") != 1:
        text += "s"
    if period.get("cost", 0) > 0:
        text += f" · {money(period.get('cost'), 'USD')}"
    return text


def normalize_opencode(raw):
    now = raw["now"]
    usage = raw["inputs"].get("usage") or {}
    stats = opencode_stats(usage, now)
    if not stats.get("available"):
        return provider_error("opencode", "OpenCode", ACCENT, now, "OpenCode: no local sessions yet", {"stats": stats, "source": "local SQLite"})

    periods = stats.get("periods") or []
    recent = next((period for period in periods if period.get("key") == "7d"), periods[-1] if periods else {})
    r = provider_base("opencode", "OpenCode", ACCENT, now)
    r["summary"] = {"pct": 0, "text": compact_tokens(recent.get("tokens")), "detail": "last 7 days · local sessions", "hasChart": False}
    r["quotaWindows"] = [flat_window(period.get("key"), period.get("label"), 0, 0, _period_text(period), False) for period in periods]
    r["slots"] = [{"pct": 0, "color": ACCENT, "text": compact_tokens(recent.get("tokens")), "tooltip": "OpenCode local usage\n" + "\n".join(f"{p.get('label')}: {_period_text(p)}" for p in periods)}]
    r["details"] = {
        "stats": stats,
        "periods": periods,
        "source": "local SQLite",
        "costStatus": stats.get("costStatus", "unavailable"),
        "costProvenance": "local ledger and exact model catalog where available",
    }
    return r
