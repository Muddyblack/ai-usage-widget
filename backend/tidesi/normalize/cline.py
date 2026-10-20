import datetime

from ..contract import compact_tokens, flat_window, num, provider_base, provider_error
from ..messages import lines, tr
from ..stats import cline_stats
from .local_activity import _usage_text

ACCENT = "#e6e6e6"


def _period(sessions, since):
    """Sessions that started at or after `since`: (count, tokens, cost)."""
    picked = [s for s in sessions if num(s.get("startedAt")) >= since]
    tokens = sum(num(s.get("input")) + num(s.get("output")) + num(s.get("cacheRead")) + num(s.get("cacheWrite")) for s in picked)
    return len(picked), tokens, sum(num(s.get("cost")) for s in picked)


def _describe(count, tokens, cost):
    return _usage_text(count, tokens, cost)


def normalize_cline(raw):
    """Cline's own session logs, read offline. Usage shows recent periods —
    a lifetime token total says little, since a token costs very different
    amounts from model to model — and Stats keeps the all-time breakdown."""
    now = raw["now"]
    res = raw["inputs"].get("usage") or {}
    stats = cline_stats(res, now)
    if not stats.get("available"):
        return provider_error("cline", "Cline", ACCENT, now, tr("Cline: no sessions yet — run cline once"), {"stats": stats})

    sessions = [s for s in res.get("sessions") or [] if isinstance(s, dict)]
    midnight = datetime.datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    periods = [
        ("cline_today", "Today", _period(sessions, midnight)),
        ("cline_7d", "Last 7 days", _period(sessions, now - 7 * 86400)),
        ("cline_30d", "Last 30 days", _period(sessions, now - 30 * 86400)),
    ]
    month_count, month_tokens, _cost = periods[2][2]

    r = provider_base("cline", "Cline", ACCENT, now)
    r["summary"] = {"pct": 0, "text": compact_tokens(month_tokens), "detail": tr("last 30 days"), "hasChart": False}
    r["quotaWindows"] = [flat_window(key, label, 0, 0, _describe(*p), False) for key, label, p in periods]
    r["slots"] = [
        {
            "pct": 0,
            "color": ACCENT,
            "text": compact_tokens(month_tokens),
            "tooltip": lines("Cline", *(tr("%1: %2", label, _describe(*p)) for _key, label, p in periods)),
        }
    ]
    r["details"] = {
        "stats": stats,
        "periods": [{"key": key, "label": label, "sessions": p[0], "tokens": p[1], "cost": p[2]} for key, label, p in periods],
    }
    return r
