"""Shared provider normalization primitives.

Every function here is pure: raw provider inputs go in, contract-shaped
pieces come out.
docs/provider-contract.md for the schema these build up.
"""

import calendar
import datetime
import math
import re

SCHEMA_VERSION = 1

# Brand artwork per provider, as a bare filename under contents/icons/. The
# frontends live at different depths, so each resolves the directory itself.
# Every provider funnels through provider_base(), which is why this table can
# stay here instead of being repeated in each normalize module — or, worse, in
# both frontends, where the two copies would drift apart.
# A provider with no artwork yet is simply absent; callers fall back to the
# plain accent dot.
PROVIDER_ICONS = {
    "antigravity": "antigravity-color.svg",
    "claude": "claude-color.svg",
    "cline": "cline.svg",
    "copilot": "githubcopilot.svg",
    "cursor": "cursor.svg",
    "deepseek": "deepseek-color.svg",
    "grok": "grok.svg",
    "kimi": "kimi.svg",
    "kiro": "kiro.svg",
    "mistral": "mistral-color.svg",
    "muse": "muse-color.svg",
    "openai": "openai.svg",
    "ollama": "ollama.svg",
    "opencode": "opencode-color.svg",
    "selfhosted": "local-models.svg",
    "openrouter": "openrouter.svg",
    "zai": "zai.svg",
}

# Each provider's public status page. `feed` names the machine-readable format
# collect.py fetches next to it (see STATUS_FEEDS); a page without one is still
# handed to the frontends as a link. `components` narrows a shared page to the
# provider's own rows — GitHub's page covers all of GitHub, and an Actions
# outage says nothing about Copilot. Providers with no public page are absent.
STATUS_PAGES = {
    "antigravity": {"url": "https://aistudio.google.com/status"},
    "claude": {"url": "https://status.claude.com", "feed": "statuspage"},
    "cline": {"url": "https://status.cline.bot", "feed": "gatus"},
    "copilot": {"url": "https://www.githubstatus.com", "feed": "statuspage", "components": "Copilot"},
    "cursor": {"url": "https://status.cursor.com", "feed": "statuspage"},
    "deepseek": {"url": "https://status.deepseek.com"},
    "grok": {"url": "https://status.x.ai"},
    "kimi": {"url": "https://status.moonshot.cn", "feed": "statuspage"},
    # Mistral and OpenRouter left Statuspage; their summary.json answers 404.
    "mistral": {"url": "https://status.mistral.ai"},
    "openai": {"url": "https://status.openai.com", "feed": "statuspage"},
    "openrouter": {"url": "https://status.openrouter.ai"},
}

STATUS_FEEDS = {"statuspage": "/api/v2/summary.json", "gatus": "/api/v1/endpoints/statuses"}


def num(v):
    if isinstance(v, bool):
        return 0
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, str):
        try:
            return float(v) if ("." in v or "e" in v.lower()) else int(v)
        except ValueError:
            return 0
    return 0


def finite_number(value, *, minimum=None, maximum=None):
    """`value` as a float, or None if it isn't a real (never bool), finite,
    in-range number. Shared guard for external data — pricing rates, provider
    cost/token fields — before it reaches arithmetic."""
    if type(value) not in (int, float):
        return None
    try:
        number = float(value)
    except (OverflowError, ValueError):
        return None
    if not math.isfinite(number):
        return None
    if minimum is not None and number < minimum:
        return None
    if maximum is not None and number > maximum:
        return None
    return number


def pct_clamp(x):
    if x < 0:
        return 0
    if x > 100:
        return 100
    return x


def jround(x):
    """Round halves away from zero, unlike Python's banker's rounding."""
    if x >= 0:
        return math.floor(x + 0.5)
    return math.ceil(x - 0.5)


_TZ_SUFFIX_RE = re.compile(r"(Z|[+-]\d{2}:?\d{2})$")
_FRACTIONAL_SECONDS_RE = re.compile(r"\.\d+")


def _parse_utc(s):
    """Parse strict "%Y-%m-%dT%H:%M:%SZ" input; return None when invalid."""
    try:
        dt = datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return calendar.timegm(dt.timetuple())


def epoch_of(v):
    """ISO-8601 (Z / ±HH:MM / ±HHMM, optional fractional seconds) or an epoch
    number, to epoch seconds. 0 means "no reset known"."""
    if isinstance(v, bool):
        return 0
    if isinstance(v, (int, float)):
        return math.floor(v)
    if not isinstance(v, str) or v == "":
        return 0
    t = _FRACTIONAL_SECONDS_RE.sub("", v)
    m = _TZ_SUFFIX_RE.search(t)
    if not m:
        base = _parse_utc(t + "Z")
        return base if base is not None else 0
    b, z = t[: m.start()], m.group(1)
    if z == "Z":
        base = _parse_utc(b + "Z")
        return base if base is not None else 0
    base = _parse_utc(b + "Z")
    if base is None or base == 0:
        return 0
    off = z.replace(":", "")
    sign = off[0]
    hh, mm = int(off[1:3]), int(off[3:5])
    secs = hh * 3600 + mm * 60
    return base - secs if sign == "+" else base + secs


def reset_text(ts):
    if ts is None or ts <= 0:
        return ""
    dt = datetime.datetime.fromtimestamp(ts)
    return dt.strftime("%b ") + str(dt.day) + dt.strftime(", %H:%M")


def unavailable_window():
    return {"available": False, "pct": 0, "resetAt": 0}


def window_value(pct, reset, active):
    if active is False or not isinstance(pct, (int, float)) or isinstance(pct, bool):
        return unavailable_window()
    return {"available": True, "pct": pct_clamp(pct), "resetAt": epoch_of(reset)}


def quota_window(key, label, w, detail):
    reset_at = w.get("resetAt", 0) or 0
    return {
        "key": key,
        "label": label,
        "pct": w.get("pct", 0) or 0,
        "available": w.get("available", False) or False,
        "resetAt": reset_at,
        "resetText": reset_text(reset_at),
        "detail": detail,
        "showMeter": True,
    }


def flat_window(key, label, pct, reset_at, detail, meter, note=""):
    w = {
        "key": key,
        "label": label,
        "pct": pct_clamp(pct),
        "available": True,
        "resetAt": reset_at,
        "resetText": reset_text(reset_at),
        "detail": detail,
        "showMeter": meter,
    }
    if note:
        # A meterless row spends `detail` on the value itself, leaving nothing
        # beside it. `note` is the aside such a row would otherwise have to
        # cram into the value.
        w["note"] = note
    return w


def chart_window(id_, key, label, size, gran):
    return {
        "id": id_,
        "key": key,
        "label": label,
        "size": size,
        "granularity": gran,
        "raw": False,
        "resets": False,
        "periodMs": 0,
        "resetAt": 0,
    }


def resetting(cw, period, window):
    cw = dict(cw)
    cw["resets"] = True
    cw["periodMs"] = period
    cw["resetAt"] = window.get("resetAt", 0) or 0
    return cw


def rolling_windows(session_id, day_id, weekly_id, session_key, weekly_key, session, weekly, monthly_id=None):
    out = []
    has_session = bool(session and session.get("available"))
    has_weekly = bool(weekly and weekly.get("available"))

    if has_session:
        out.append(resetting(chart_window(session_id, session_key, "5H", 18000000, "5h"), 18000000, session))
        out.append(resetting(chart_window(day_id, session_key, "24H", 86400000, "24h"), 18000000, session))
    elif has_weekly:
        out.append(resetting(chart_window(session_id, weekly_key, "5H", 18000000, "5h"), 604800000, weekly))
        out.append(resetting(chart_window(day_id, weekly_key, "24H", 86400000, "24h"), 604800000, weekly))

    if has_weekly:
        m_id = monthly_id or f"{weekly_id}_30d"
        out.append(resetting(chart_window(weekly_id, weekly_key, "7D", 604800000, "7d"), 604800000, weekly))
        out.append(resetting(chart_window(m_id, weekly_key, "30D", 2592000000, "30d"), 604800000, weekly))
    elif has_session:
        m_id = monthly_id or f"{session_id}_30d"
        out.append(resetting(chart_window(weekly_id, session_key, "7D", 604800000, "7d"), 18000000, session))
        out.append(resetting(chart_window(m_id, session_key, "30D", 2592000000, "30d"), 18000000, session))

    return out


def monthly_window(id_prefix, key, raw):
    return [
        {**chart_window(f"{id_prefix}_5h", key, "5H", 18000000, "5h"), "raw": raw},
        {**chart_window(f"{id_prefix}_24h", key, "24H", 86400000, "24h"), "raw": raw},
        {**chart_window(f"{id_prefix}_7d", key, "7D", 604800000, "7d"), "raw": raw},
        {**chart_window(f"{id_prefix}_30d", key, "30D", 2592000000, "30d"), "raw": raw},
    ]


_TOKEN_UNITS = (("B", 1000000000), ("M", 1000000), ("k", 1000))


def compact_tokens(v, decimals=1, units=_TOKEN_UNITS, trim_zeros=True):
    """Token counts run to eight digits; a table cell has room for a few.

    Shared so the providers agree on the shape, parameterised because they
    legitimately disagree on the details: z.ai prints two decimals and an
    uppercase "K" to match the figure on the vendor's own dashboard — this
    number exists to be checked against that page, and a differently rounded
    one invites the reader to wonder which is wrong — while the panel pills
    want the shortest thing that still reads as a count ("30k", not "30.00K").

    `units` is ordered largest first; pass a shorter tuple to opt out of a
    magnitude entirely.
    """
    n = num(v)
    for suffix, limit in units:
        if abs(n) >= limit:
            s = f"{n / limit:.{decimals}f}"
            if trim_zeros and "." in s:
                s = s.rstrip("0").rstrip(".")
            return s + suffix
    return str(int(n))


def money(v, currency):
    cents = jround(v * 100)
    sign = "-" if cents < 0 else ""
    c = abs(cents)
    whole, frac = divmod(c, 100)
    if frac == 0:
        amount = f"{sign}{whole}"
    elif frac % 10 == 0:
        amount = f"{sign}{whole}.{frac // 10}"
    else:
        amount = f"{sign}{whole}.{frac:02d}"
    if currency == "USD":
        return "$" + amount
    if currency == "CNY":
        return "¥" + amount
    if currency in ("", None):
        return amount
    return amount + " " + currency


def empty_status(url=""):
    """An empty indicator with a url is a page that has no feed (or could not
    be fetched): the frontends show it as a plain link."""
    return {"indicator": "", "description": "", "components": [], "incidents": [], "latestUpdate": "", "url": url}


# How a single Statuspage component maps onto the page-wide indicator scale.
_COMPONENT_INDICATOR = {
    "degraded_performance": "minor",
    "under_maintenance": "minor",
    "partial_outage": "major",
    "major_outage": "critical",
}
_INDICATOR_RANK = {"none": 0, "minor": 1, "major": 2, "critical": 3}
_SCOPED_DESCRIPTION = {"none": "operational", "minor": "degraded", "major": "partial outage", "critical": "major outage"}


def status_summary(d, id_=""):
    """Summarise the raw feed collect.py fetched for provider `id_`."""
    page = STATUS_PAGES.get(id_) or {}
    url = page.get("url", "")
    if page.get("feed") == "gatus":
        return _gatus_summary(d, url)
    return _statuspage_summary(d, url, page.get("components", ""))


def _statuspage_summary(d, url, only):
    if not isinstance(d, dict) or "status" not in d:
        return empty_status(url)
    incidents = [inc for inc in d.get("incidents") or [] if isinstance(inc, dict) and inc.get("status") != "resolved"]
    rows = [c for c in d.get("components") or [] if isinstance(c, dict) and not c.get("group")]
    status_obj = d.get("status") or {}
    indicator = status_obj.get("indicator") or "none"
    description = status_obj.get("description") or ""
    if only:
        rows = [c for c in rows if str(c.get("name") or "").startswith(only)]
        # A fresh incident often names the product before anyone tags the
        # affected components, so the title counts as well.
        incidents = [
            inc
            for inc in incidents
            if only in str(inc.get("name") or "")
            or any(isinstance(c, dict) and str(c.get("name") or "").startswith(only) for c in inc.get("components") or [])
        ]
        indicator = max((_COMPONENT_INDICATOR.get(c.get("status"), "none") for c in rows), key=_INDICATOR_RANK.get, default="none")
        if indicator == "none" and incidents:
            indicator = "minor"
        description = f"{only} {_SCOPED_DESCRIPTION[indicator]}"
    body = ""
    for inc in incidents:
        updates = inc.get("incident_updates") or []
        b = ((updates[0].get("body") if updates else "") or "").strip()
        if b != "":
            body = b
            break
    components = []
    for c in rows:
        status_val = c.get("status") or ""
        if status_val != "" and status_val != "operational":
            components.append((c.get("name") or "") + " (" + status_val.replace("_", " ") + ")")
    return {
        "indicator": indicator,
        "description": description,
        "components": components,
        "incidents": [inc.get("name") or "" for inc in incidents],
        "latestUpdate": body[0:197] + "…" if len(body) > 200 else body,
        "url": url,
    }


def _gatus_summary(d, url):
    """Gatus lists endpoints with their recent check results, oldest first;
    an endpoint counts as down when its latest check failed."""
    if not isinstance(d, list):
        return empty_status(url)
    checked, down = 0, []
    for e in d:
        results = e.get("results") if isinstance(e, dict) else None
        if not results or not isinstance(results[-1], dict):
            continue
        checked += 1
        if results[-1].get("success") is not True:
            down.append(str(e.get("name") or e.get("key") or "endpoint"))
    if checked == 0:
        return empty_status(url)
    if not down:
        indicator, description = "none", "All Systems Operational"
    elif len(down) == checked:
        indicator, description = "critical", "All checks failing"
    else:
        indicator, description = "major", f"{len(down)} of {checked} checks failing"
    return {
        "indicator": indicator,
        "description": description,
        "components": [name + " (down)" for name in down],
        "incidents": [],
        "latestUpdate": "",
        "url": url,
    }


def provider_base(id_, label, accent, now):
    return {
        "id": id_,
        "label": label,
        "accent": accent,
        "icon": PROVIDER_ICONS.get(id_, ""),
        "ok": True,
        "stale": False,
        "error": "",
        "updatedAt": math.floor(now),
        "summary": {"pct": 0, "text": "", "detail": "", "hasChart": True},
        "quotaWindows": [],
        "chartWindows": [],
        "slots": [],
        "historyValues": {},
        "details": {},
    }


def provider_error(id_, label, accent, now, error, details):
    r = provider_base(id_, label, accent, now)
    r["ok"] = False
    r["stale"] = True
    r["error"] = error
    r["summary"] = {"pct": 0, "text": "unavailable", "detail": error, "hasChart": True}
    r["slots"] = [{"pct": 0, "color": accent, "text": "—", "tooltip": error}]
    r["details"] = details
    return r


def finalize(obj):
    """Recursively collapse integral floats to int ahead of json.dumps."""
    if isinstance(obj, float):
        if math.isfinite(obj) and obj == int(obj):
            return int(obj)
        return obj
    if isinstance(obj, dict):
        return {k: finalize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [finalize(v) for v in obj]
    return obj
