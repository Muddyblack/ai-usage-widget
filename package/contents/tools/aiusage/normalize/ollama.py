"""Normalize the limit buckets returned by Ollama Cloud's usage API."""

import math

from ..contract import chart_window, flat_window, jround, provider_base, provider_error

ACCENT = "#f0f0f0"
BUCKETS = (("session", "Session (5h)"), ("weekly", "Weekly (7d)"), ("monthly", "Monthly"))


def normalize_ollama(raw):
    now = raw["now"]
    body = raw["inputs"].get("usage") or {}
    if not body:
        return provider_error("ollama", "Ollama Cloud", ACCENT, now, "Ollama Cloud: no API key found in settings, environment, or OpenCode", {})
    if not isinstance(body, dict):
        return provider_error("ollama", "Ollama Cloud", ACCENT, now, "Ollama Cloud: invalid usage response", {})
    if body.get("error"):
        return provider_error("ollama", "Ollama Cloud", ACCENT, now, str(body["error"]), {})
    limits = body.get("limits")
    if not isinstance(limits, dict):
        return provider_error("ollama", "Ollama Cloud", ACCENT, now, "Ollama Cloud: usage response has no limit data", {})

    windows = []
    models = {}
    for key, label in BUCKETS:
        bucket = limits.get(key)
        if not isinstance(bucket, dict):
            continue
        fraction = bucket.get("usage")
        if isinstance(fraction, bool) or not isinstance(fraction, (int, float)) or not math.isfinite(fraction) or fraction < 0:
            continue
        pct = max(0, min(100, fraction * 100))
        windows.append(flat_window(f"ollama_{key}", label, pct, 0, f"{jround(pct)}% used", True))
        rows = bucket.get("models")
        if isinstance(rows, list):
            models[key] = [
                {"name": row["name"], "requestCount": row["request_count"]}
                for row in rows
                if isinstance(row, dict)
                and isinstance(row.get("name"), str)
                and isinstance(row.get("request_count"), int)
                and not isinstance(row["request_count"], bool)
                and row["request_count"] >= 0
            ]
    if not windows:
        return provider_error("ollama", "Ollama Cloud", ACCENT, now, "Ollama Cloud: no recognized usage limits in response", {})

    activity = body.get("activity") if isinstance(body.get("activity"), dict) else {}
    cost = activity.get("cost")
    try:
        cost_value = float(cost) if not isinstance(cost, bool) else -1
    except (TypeError, ValueError, OverflowError):
        cost_value = -1
    cost = str(cost) if math.isfinite(cost_value) and cost_value >= 0 else ""
    primary = windows[0]
    r = provider_base("ollama", "Ollama Cloud", ACCENT, now)
    r["summary"] = {"pct": primary["pct"], "text": f"{jround(primary['pct'])}%", "detail": primary["label"], "hasChart": True}
    r["quotaWindows"] = windows
    r["slots"] = [
        {
            "pct": primary["pct"],
            "color": ACCENT,
            "text": None,
            "tooltip": "Ollama Cloud\n" + "\n".join(f"{w['label']}: {jround(w['pct'])}%" for w in windows),
        }
    ]
    # Never join different limit types in one history series. The endpoint can
    # change between session/weekly and monthly even for the same account.
    by_key = {w["key"]: w for w in windows}
    long_window = by_key.get("ollama_monthly") or by_key.get("ollama_weekly") or primary
    r["chartWindows"] = [
        chart_window("ollama_5h", primary["key"], "5H", 18000000, "5h"),
        chart_window("ollama_24h", primary["key"], "24H", 86400000, "24h"),
        chart_window("ollama_7d", long_window["key"], "7D", 604800000, "7d"),
        chart_window("ollama_30d", long_window["key"], "30D", 2592000000, "30d"),
    ]
    r["historyValues"] = {w["key"]: w["pct"] for w in windows}
    r["details"] = {"models": models, "activityCost": cost, "limitType": primary["key"], "resetUnavailable": True}
    return r
