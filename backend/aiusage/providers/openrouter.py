"""Resolve OpenRouter API key and fetch usage/credits.

Ported from tools/sh/get-openrouter-usage.
"""

import os

from ..http import as_json, error_json, fetch_json, http_error_json, resolve_key


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

    result = fetch_json(
        "https://openrouter.ai/api/v1/key",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        timeout=8,
        fixture_path=os.environ.get("OPENROUTER_RESPONSE_FILE"),
    )
    if result.status != 200:
        return http_error_json("OpenRouter", result.status, "Invalid API key (401)")

    body = as_json(result.body)
    if body is None:
        return error_json("OpenRouter invalid JSON")
    d = body.get("data") if isinstance(body.get("data"), dict) else body
    return {
        "hasKey": True,
        "keyValid": True,
        "label": d.get("label") or "",
        "usageUSD": d.get("usage") or 0,
        "limitUSD": d.get("limit"),
        "limitRemainingUSD": d.get("limit_remaining"),
        "isFreeTier": d.get("is_free_tier") or False,
        "rateLimit": d.get("rate_limit") or {},
    }
