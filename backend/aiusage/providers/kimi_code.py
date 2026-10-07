"""Kimi Code plan quota, read with the login the `kimi` CLI already stored.

Kimi Code keeps an OAuth pair in $KIMI_CODE_HOME/credentials/kimi-code.json
(~/.kimi-code by default) and shows plan usage from GET <base>/usages. The
response parsing mirrors the CLI's own parseManagedUsagePayload: a `usage`
summary (a weekly window unless it says otherwise), `limits[]` with their own
windows, and an optional `boosterWallet` of paid extra usage.

Read-only on purpose. The CLI refreshes its short-lived access token itself
and writes the rotated pair back; a second refresher here would race it and
could sign the user out. An expired token is therefore reported, not renewed.
"""

import os
import time

from ..contract import epoch_of, num
from ..http import as_json, clean_credential, fetch_json, http_error_text

# Kimi's wallet amounts are fixed-point: cents × 10^6 (FIXED_POINT_CENTS in
# the CLI).
_FIXED_POINT_CENTS = 1e6

_UNIT_SECONDS = {
    "TIME_UNIT_MINUTE": 60,
    "TIME_UNIT_HOUR": 3600,
    "TIME_UNIT_DAY": 86400,
    "TIME_UNIT_WEEK": 604800,
}


def _kimi_home():
    return os.environ.get("KIMI_CODE_HOME") or os.path.expanduser("~/.kimi-code")


def _base_url():
    return (os.environ.get("KIMI_CODE_BASE_URL") or "https://api.kimi.com/coding/v1").rstrip("/")


def _login():
    """The stored OAuth record, None when Kimi Code was never signed in here."""
    path = os.path.join(_kimi_home(), "credentials", "kimi-code.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            data = as_json(f.read())
    except OSError:
        return {}
    return data if isinstance(data, dict) else {}


def _window_seconds(raw):
    if not isinstance(raw, dict):
        return 0
    return int(num(raw.get("duration"))) * _UNIT_SECONDS.get(raw.get("timeUnit"), 0)


def _row(raw, name="", seconds=0):
    if not isinstance(raw, dict):
        return None
    used, limit = raw.get("used"), raw.get("limit")
    if used is None and limit is None:
        return None
    return {
        "name": name or (raw.get("name") if isinstance(raw.get("name"), str) else ""),
        "seconds": seconds,
        "used": int(num(used)),
        "limit": int(num(limit)),
        "resetAt": epoch_of(raw.get("resetTime") or ""),
    }


def _cents(fixed_point):
    cents = num(fixed_point) / _FIXED_POINT_CENTS
    return 1 if 0 < cents < 1 else round(cents)


def _booster(raw):
    if not isinstance(raw, dict):
        return None
    balance = raw.get("balance")
    if not isinstance(balance, dict) or balance.get("type") != "BOOSTER":
        return None
    amount = num(balance.get("amount"))
    if amount <= 0:
        return None

    def money(key):
        m = raw.get(key)
        return (num(m.get("priceInCents")), m.get("currency") or "") if isinstance(m, dict) else (0, "")

    limit_cents, limit_currency = money("monthlyChargeLimit")
    used_cents, used_currency = money("monthlyUsed")
    return {
        "balanceCents": _cents(balance.get("amountLeft")),
        "totalCents": _cents(amount),
        "monthlyChargeLimitEnabled": raw.get("monthlyChargeLimitEnabled") is True,
        "monthlyChargeLimitCents": limit_cents,
        "monthlyUsedCents": used_cents,
        "currency": limit_currency or used_currency or "USD",
    }


def parse_usage_payload(payload):
    windows = []
    if isinstance(payload.get("limits"), list):
        for item in payload["limits"]:
            if isinstance(item, dict):
                row = _row(item.get("detail"), item.get("name") or "", _window_seconds(item.get("window")))
                if row is not None:
                    windows.append(row)
    summary = _row(payload.get("usage"))
    if summary is not None:
        summary["seconds"] = summary["seconds"] or 604800
        if not any(w["seconds"] == summary["seconds"] and w["used"] == summary["used"] and w["limit"] == summary["limit"] for w in windows):
            windows.append(summary)
    windows.sort(key=lambda w: w["seconds"] or 1 << 30)
    return {"windows": windows, "booster": _booster(payload.get("boosterWallet"))}


def _exhausted_message(data):
    """The 429 Kimi answers once the plan is used up — `resource_exhausted`
    with REASON_QUOTA_EXCEEDED — told apart from plain rate limiting."""
    if not isinstance(data, dict) or data.get("code") != "resource_exhausted":
        return None
    message = data.get("message") or ""
    for detail in data.get("details") or []:
        debug = detail.get("debug") if isinstance(detail, dict) else None
        if not isinstance(debug, dict):
            continue
        localized = debug.get("localizedMessage")
        if isinstance(localized, dict) and localized.get("message"):
            message = localized["message"]
        if debug.get("reason") == "REASON_QUOTA_EXCEEDED":
            return (message or "Plan quota used up").rstrip(".")
    return message.rstrip(".") if "balance" in message.lower() else None


def parse_usage_response(status, body):
    data = as_json(body)
    if status == 200:
        if not isinstance(data, dict):
            return {"loggedIn": True, "error": "Kimi Code usage response could not be parsed"}
        return {"loggedIn": True, "exhausted": False, **parse_usage_payload(data)}
    exhausted = _exhausted_message(data)
    if exhausted is not None:
        return {"loggedIn": True, "exhausted": True, "message": exhausted, "windows": [], "booster": None}
    if status in (401, 403):
        return {"loggedIn": True, "error": "Kimi Code login rejected — run kimi once to refresh it"}
    return {"loggedIn": True, "error": f"Kimi Code {http_error_text(status)}"}


def get_kimi_code_usage():
    login = _login()
    if login is None:
        return {}
    token = clean_credential(login.get("access_token"))
    if not token:
        return {"loggedIn": False, "error": "Kimi Code is not signed in — run kimi and /login"}
    expires = num(login.get("expires_at"))
    if expires > 1e11:  # milliseconds
        expires /= 1000
    if expires and expires <= time.time():
        return {"loggedIn": True, "error": "Kimi Code login expired — run kimi once to refresh it"}

    result = fetch_json(
        f"{_base_url()}/usages",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json", "User-Agent": "kde-ai-usage/kimi"},
        timeout=10,
        fixture_path=os.environ.get("KIMI_CODE_USAGE_RESPONSE_FILE"),
    )
    return parse_usage_response(result.status, result.body)
