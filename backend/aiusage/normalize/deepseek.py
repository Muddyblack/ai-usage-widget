from ..contract import flat_window, money, monthly_window, num, provider_base, provider_error


def normalize_deepseek(raw):
    now = raw["now"]
    res = raw["inputs"].get("usage") or {}

    if not isinstance(res, dict) or not res:
        return provider_error(
            "deepseek",
            "DeepSeek",
            "#4f8cff",
            now,
            "DeepSeek: no API key configured",
            {"hasKey": False, "keyValid": False},
        )
    if res.get("error") is not None:
        return provider_error(
            "deepseek",
            "DeepSeek",
            "#4f8cff",
            now,
            f"DeepSeek: {res['error']}",
            {"hasKey": res.get("hasKey") is True, "keyValid": res.get("keyValid") is True},
        )

    total = num(res.get("primaryTotal"))
    granted = num(res.get("primaryGranted"))
    topped = num(res.get("primaryToppedUp"))
    currency = res.get("primaryCurrency") or ""
    symbol = "$" if currency == "USD" else ("¥" if currency == "CNY" else "")
    available = res.get("isAvailable") is True

    r = provider_base("deepseek", "DeepSeek", "#4f8cff", now)
    r["summary"] = {
        "pct": 0,
        "text": money(total, currency),
        "detail": "Available for API calls" if available else "Low balance",
        "hasChart": True,
    }
    r["quotaWindows"] = [
        flat_window("deepseek_total", "Total balance", 0, 0, money(total, currency), False),
        flat_window(
            "deepseek_split",
            "Granted / topped up",
            0,
            0,
            f"{money(granted, currency)} / {money(topped, currency)}",
            False,
        ),
    ]
    r["slots"] = [{"pct": 0, "color": "#4f8cff", "text": money(total, currency), "tooltip": f"DeepSeek balance: {money(total, currency)}"}]
    r["chartWindows"] = monthly_window("deepseek", "ds", True)
    r["historyValues"] = {"ds": total}
    r["details"] = {
        "hasKey": res.get("hasKey") is True,
        "keyValid": res.get("keyValid") is True,
        "isAvailable": available,
        "balances": res.get("balances") or [],
        "primaryCurrency": currency,
        "primaryTotal": total,
        "primaryGranted": granted,
        "primaryToppedUp": topped,
        "currency": currency,
        "symbol": symbol,
    }
    return r
