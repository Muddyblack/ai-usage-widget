"""Resolve a DeepSeek API key and fetch account balance.

Ported from tools/sh/get-deepseek-balance.
"""

import os

from ..contract import num
from ..http import as_json, error_json, fetch_json, http_error_json, resolve_key


def get_deepseek_balance():
    api_key = resolve_key("WIDGET_DEEPSEEK_API_KEY", "DEEPSEEK_API_KEY", os.path.expanduser("~/.config/deepseek/api-key"))
    if not api_key:
        return {}

    result = fetch_json(
        "https://api.deepseek.com/user/balance",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "User-Agent": "kde-ai-usage/deepseek",
        },
        timeout=10,
        fixture_path=os.environ.get("DEEPSEEK_BALANCE_RESPONSE_FILE"),
    )
    if result.status != 200:
        return http_error_json("DeepSeek", result.status, "Invalid DeepSeek API key")

    body = as_json(result.body)
    if body is None:
        return error_json("DeepSeek invalid JSON")

    balances = body.get("balance_infos")
    if not isinstance(balances, list):
        return {"hasKey": True, "keyValid": False, "error": "DeepSeek unexpected response"}

    primary = next((b for b in balances if b.get("currency") == "USD"), balances[0] if balances else {})
    return {
        "hasKey": True,
        "keyValid": True,
        "isAvailable": body.get("is_available") is True,
        "balances": balances,
        "primaryCurrency": primary.get("currency") or "",
        "primaryTotal": num(primary.get("total_balance", "0")),
        "primaryGranted": num(primary.get("granted_balance", "0")),
        "primaryToppedUp": num(primary.get("topped_up_balance", "0")),
    }
