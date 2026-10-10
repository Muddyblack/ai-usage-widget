"""Resolve OpenRouter API key and fetch usage/credits.

Two independent requests, so one failing never hides the other:

* ``/key``     the key's own spend and optional spending cap (daily, weekly and
               monthly spend too, when OpenRouter reports them);
* ``/credits`` the account's purchased credits and total usage, i.e. the real
               balance — a key's cap is not a balance.

Ported from tools/sh/get-openrouter-usage.
"""

import os

from ..contract import finite_number
from ..http import as_json, error_json, fetch_json, http_error_json, resolve_key
from ..messages import tr

_BASE = "https://openrouter.ai/api/v1"
_CREDITS_TIMEOUT = 4


def _data(body):
    if not isinstance(body, dict):
        return {}
    return body.get("data") if isinstance(body.get("data"), dict) else body


def _money(value):
    return finite_number(value, minimum=0)


def _credits(headers):
    """(total credits, total usage) or None. A refusal or a bad body just means
    no balance; the key's own figures are still shown."""
    fixture = os.environ.get("OPENROUTER_CREDITS_RESPONSE_FILE")
    if os.environ.get("OPENROUTER_RESPONSE_FILE") and not fixture:
        # Replaying a recorded /key response must never reach the network.
        return None
    result = fetch_json(f"{_BASE}/credits", headers=headers, timeout=_CREDITS_TIMEOUT, fixture_path=fixture)
    if result.status != 200:
        return None
    d = _data(as_json(result.body))
    total, used = _money(d.get("total_credits")), _money(d.get("total_usage"))
    return None if total is None or used is None else (total, used)


def get_openrouter_usage():
    api_key = resolve_key(
        "WIDGET_OPENROUTER_API_KEY",
        "OPENROUTER_API_KEY",
        os.path.expanduser("~/.config/openrouter/api-key"),
        os.path.expanduser("~/.openrouter/api-key"),
        os.path.expanduser("~/.config/openrouter.key"),
    )
    if not api_key:
        return {}

    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    result = fetch_json(
        f"{_BASE}/key",
        headers=headers,
        timeout=8,
        fixture_path=os.environ.get("OPENROUTER_RESPONSE_FILE"),
    )
    credits = _credits(headers) if result.status in (200, 401, 403) else None
    key_ok = result.status == 200
    body = as_json(result.body) if key_ok else None
    if not key_ok or body is None:
        if credits is None:
            if not key_ok:
                return http_error_json("OpenRouter", result.status, tr("Invalid API key (401)"))
            return error_json(tr("OpenRouter invalid JSON"))
        # The balance answered even though the key lookup did not.
        return {
            "hasKey": True,
            "keyValid": True,
            "keyUnavailable": True,
            "creditsTotalUSD": credits[0],
            "creditsUsedUSD": credits[1],
        }

    d = _data(body)
    out = {
        "hasKey": True,
        "keyValid": True,
        "label": d.get("label") or "",
        "usageUSD": d.get("usage") or 0,
        "limitUSD": d.get("limit"),
        "limitRemainingUSD": d.get("limit_remaining"),
        "limitReset": d.get("limit_reset") or "",
        "isFreeTier": d.get("is_free_tier") or False,
        "rateLimit": d.get("rate_limit") or {},
        "usageDailyUSD": _money(d.get("usage_daily")),
        "usageWeeklyUSD": _money(d.get("usage_weekly")),
        "usageMonthlyUSD": _money(d.get("usage_monthly")),
    }
    if credits is not None:
        out["creditsTotalUSD"], out["creditsUsedUSD"] = credits
    return out
