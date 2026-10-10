"""Kilo credit balance and Kilo Pass usage.

Kilo's web app talks to its backend over tRPC, and a CLI login or an API key
reaches the same procedures: ``user.getCreditBlocks`` (prepaid credit) and
``kiloPass.getState`` (the subscription period). Both go out as one GET batch.

The credential is, in order: the widget setting / ``$KILO_API_KEY``, then the
token the ``kilo`` CLI stored at ``~/.local/share/kilo/auth.json`` (key
``kilo.access``). A key that is refused falls back to the CLI login, so a stale
setting does not hide a working login.
"""

import json
import os
import urllib.parse

from .. import paths, sources
from ..contract import epoch_of, finite_number
from ..http import as_json, clean_credential, fetch_json, http_error_text, resolve_key
from ..messages import tr

_BASE = "https://app.kilo.ai/api/trpc"
_PROCEDURES = ("user.getCreditBlocks", "kiloPass.getState")
_TIERS = {"tier_19": "Starter", "tier_49": "Pro", "tier_199": "Expert"}
_RESET_KEYS = ("nextBillingAt", "nextRenewalAt", "renewsAt", "renewAt")


def _cli_token():
    for path in _cli_auth_files():
        try:
            with open(path, encoding="utf-8") as f:
                data = as_json(f.read())
        except OSError:
            continue
        entry = data.get("kilo") if isinstance(data, dict) else None
        token = clean_credential(entry.get("access")) if isinstance(entry, dict) else ""
        if token:
            return token
    return ""


def _url():
    batch = {str(i): {"json": None} for i in range(len(_PROCEDURES))}
    return f"{_BASE}/{','.join(_PROCEDURES)}?" + urllib.parse.urlencode({"batch": "1", "input": json.dumps(batch, separators=(",", ":"))})


def _payload(entry):
    """tRPC wraps a result as {"result": {"data": {"json": ...}}}."""
    data = ((entry or {}).get("result") or {}).get("data") if isinstance(entry, dict) else None
    if isinstance(data, dict):
        return data.get("json") if "json" in data else data
    return None


def _usd(value, divisor=1.0):
    number = finite_number(value)
    return None if number is None else number / divisor


def parse_credits(payload):
    """(used, total) USD from the credit blocks, or None."""
    if not isinstance(payload, dict):
        return None
    blocks = payload.get("creditBlocks")
    if isinstance(blocks, list) and blocks:
        total = sum(_usd(b.get("amount_mUsd"), 1e6) or 0 for b in blocks if isinstance(b, dict))
        remaining = sum(_usd(b.get("balance_mUsd"), 1e6) or 0 for b in blocks if isinstance(b, dict))
        return {"used": max(0.0, total - remaining), "total": total, "remaining": remaining}
    balance = _usd(payload.get("totalBalance_mUsd"), 1e6)
    if balance is not None:
        return {"used": 0.0, "total": balance, "remaining": balance}
    return None


def parse_pass(payload):
    """The Kilo Pass period, or None for an account without one."""
    if not isinstance(payload, dict):
        return None
    sub = payload.get("subscription")
    if not isinstance(sub, dict):
        return None
    used = _usd(sub.get("currentPeriodUsageUsd")) or 0.0
    base = _usd(sub.get("currentPeriodBaseCreditsUsd")) or 0.0
    bonus = _usd(sub.get("currentPeriodBonusCreditsUsd")) or 0.0
    tier = sub.get("tier") if isinstance(sub.get("tier"), str) else ""
    reset = next((sub[k] for k in _RESET_KEYS if sub.get(k)), None)
    if isinstance(reset, (int, float)) and reset > 10_000_000_000:
        reset = reset / 1000
    return {
        "tier": _TIERS.get(tier, tier) or "Kilo Pass",
        "used": used,
        "total": base + bonus,
        "bonus": bonus,
        "resetAt": epoch_of(reset),
    }


def _fetch(token):
    fixture = os.environ.get("KILO_USAGE_RESPONSE_FILE")
    return fetch_json(
        _url(),
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json", "User-Agent": "ai-usage-widget/kilo"},
        timeout=15,
        fixture_path=fixture,
    )


def _own_key():
    return resolve_key("WIDGET_KILO_API_KEY", "KILO_API_KEY")


def _cli_auth_files():
    explicit = os.environ.get("KILO_AUTH_PATH")
    return [explicit] if explicit else [os.path.join(base, "kilo", "auth.json") for base in paths.data_home_dirs()]


SOURCES = (
    sources.Source("key", "api", tr("API key"), tr("A key from settings or $KILO_API_KEY"), lambda: bool(_own_key())),
    sources.Source("cli", "cli", tr("Kilo CLI"), tr("The login `kilo auth login` stored"), lambda: any(os.path.isfile(p) for p in _cli_auth_files())),
)

_TOKENS = {"key": lambda: _own_key(), "cli": lambda: _cli_token()}


def get_kilo_usage():
    # A refused key falls back to the CLI login (unless the user chose one).
    tokens = [(token, source) for source in sources.candidates("kilo", tuple(_TOKENS)) if (token := _TOKENS[source]())]
    if not tokens:
        return {}
    result, source = None, ""
    for candidate, label in tokens:
        result, source = _fetch(candidate), label
        if result.status not in (401, 403):
            break
    if result.status != 200:
        return {"error": http_error_text(result.status), "source": source}
    body = as_json(result.body)
    if not isinstance(body, list) or not body:
        return {"error": "unexpected response", "source": source}
    credits = parse_credits(_payload(body[0]))
    kilo_pass = parse_pass(_payload(body[1])) if len(body) > 1 else None
    if credits is None and kilo_pass is None:
        return {"error": "unexpected response", "source": source}
    return {"credits": credits, "pass": kilo_pass, "source": source}
