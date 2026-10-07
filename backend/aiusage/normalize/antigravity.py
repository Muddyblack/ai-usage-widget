from ..contract import epoch_of, flat_window, jround, monthly_window, num, pct_clamp, provider_base, provider_error


def _family(m):
    name = (m.get("label") or m.get("modelId") or "").lower()
    return "gemini" if ("gemini" in name or "google" in name) else "external"


def _avg(values):
    return (sum(values) / len(values)) if values else 0


def normalize_antigravity(raw):
    now = raw["now"]
    res = raw["inputs"].get("usage") or {}

    if not isinstance(res, dict) or not res:
        return provider_error("antigravity", "Antigravity", "#4285f4", now, "Antigravity not configured", {})

    if res.get("error") is not None:
        first_line = (res["error"] or "").split("\n")[0]
        if "Antigravity is not running" in first_line:
            first_line = "Antigravity is not running in IDE"
        return provider_error("antigravity", "Antigravity", "#4285f4", now, first_line, {})

    models = []
    for m in res.get("models") or []:
        rem = m.get("remainingPercentage")
        rem = rem if isinstance(rem, (int, float)) and not isinstance(rem, bool) else None
        models.append(
            {
                "modelId": m.get("modelId") or "unknown",
                "displayName": m.get("label") or m.get("modelId") or "unknown",
                "hasQuota": rem is not None,
                "usedPct": pct_clamp((1 - rem) * 100) if rem is not None else 0,
                "resetTime": m.get("resetTime") or "",
                "resetAt": epoch_of(m.get("resetTime") or ""),
                "isExhausted": m.get("isExhausted") is True,
                "family": _family(m),
            }
        )

    quoted = [m for m in models if m["hasQuota"]]
    pct = _avg([m["usedPct"] for m in quoted])
    g = [m for m in quoted if m["family"] == "gemini"]
    e = [m for m in quoted if m["family"] == "external"]
    gpct = _avg([m["usedPct"] for m in g])
    epct = _avg([m["usedPct"] for m in e])
    reset_ats = [m["resetAt"] for m in models if m["resetAt"] > 0]
    earliest = min(reset_ats) if reset_ats else 0

    groups = []
    for key in ("gemini", "external"):
        group = [m for m in models if m["family"] == key]
        if not group:
            continue
        group_quoted = [m for m in group if m["hasQuota"]]
        group_resets = [m["resetAt"] for m in group if m["resetAt"] > 0]
        groups.append(
            {
                "key": key,
                "label": "Gemini Models" if key == "gemini" else "Claude & GPT Models",
                "usedPct": _avg([m["usedPct"] for m in group_quoted]),
                "resetAt": min(group_resets) if group_resets else 0,
                "isExhausted": any(m["isExhausted"] for m in group),
                "models": sorted(m["modelId"] for m in group),
            }
        )

    credits = res.get("promptCredits") or {}
    plan = res.get("planType") or ("LOCAL" if res.get("method") == "local" else "CLOUD")

    r = provider_base("antigravity", "Antigravity", "#4285f4", now)
    r["summary"] = {"pct": pct, "text": f"{jround(pct)}%", "detail": plan, "hasChart": True}
    quota_windows = []
    for grp in groups:
        detail = ""
        if grp["key"] == "gemini" and num(credits.get("monthly")) > 0:
            detail = f"{num(credits.get('available'))} / {num(credits.get('monthly'))} credits"
        qw = flat_window(grp["key"], grp["label"], grp["usedPct"], grp["resetAt"], detail, True)
        qw["color"] = "#4285f4" if grp["key"] == "gemini" else "#34a853"
        quota_windows.append(qw)
    r["quotaWindows"] = quota_windows
    r["slots"] = [
        {
            "pct": gpct,
            "color": "#4285f4",
            "text": None,
            "tooltip": f"Gemini (Google) quota: {jround(gpct)}%" + (f"\nPlan: {plan}" if plan != "" else ""),
        },
        {
            "pct": epct,
            "color": "#34a853",
            "text": None,
            "tooltip": f"External models quota: {jround(epct)}%" + (f"\nPlan: {plan}" if plan != "" else ""),
        },
    ]
    r["chartWindows"] = monthly_window("antigravity", "ag", False)
    history_values = {"ag": pct}
    if g:
        history_values["agg"] = gpct
    if e:
        history_values["age"] = epct
    r["historyValues"] = history_values
    r["details"] = {
        "email": res.get("email") or "",
        "planType": plan,
        "promptCreditsMonthly": num(credits.get("monthly")),
        "promptCreditsAvailable": num(credits.get("available")),
        "pct": pct,
        "googlePct": gpct,
        "externalPct": epct,
        "resetAt": earliest,
        "models": {
            m["modelId"]: {
                "displayName": m["displayName"],
                "usedPct": m["usedPct"],
                "resetTime": m["resetTime"],
                "resetAt": m["resetAt"],
                "isExhausted": m["isExhausted"],
                "hasQuota": m["hasQuota"],
            }
            for m in models
        },
        "groups": groups,
    }
    return r
