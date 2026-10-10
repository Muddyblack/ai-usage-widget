"""Zed plan and edit-prediction usage (macOS, untested against a live account).

The Zed editor stores its sign-in as an internet-password item in the macOS
login Keychain: the server is ``https://zed.dev`` (or the ``server_url`` /
``credentials_url`` of ``settings.json``), the account is the Zed user id and
the secret is the access token. The widget reads it through ``/usr/bin/security``
— see keychain.py for why — and sends it to Zed's own cloud API, the request the
editor makes itself.

Linux and Windows editors keep the login in the system secret store, which this
package has no safe way to read, so there the provider reports it cannot sign in.
Response field names are read defensively; the plan block is
``plan.plan_v3`` / ``plan.usage.edit_predictions`` / ``plan.subscription_period``.
"""

import os
import re
import subprocess
import urllib.parse

from .. import paths
from ..contract import epoch_of, finite_number
from ..http import as_json, clean_credential, fetch_json, http_error_text

_DEFAULT_SERVER = "https://zed.dev"
_API = "https://cloud.zed.dev/client/users/me"
_ACCOUNT_RE = re.compile(r'"acct"<blob>="([^"]*)"')


def _settings():
    explicit = os.environ.get("ZED_SETTINGS_PATH")
    path = explicit or os.path.join(paths.config_home(), "zed", "settings.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = as_json(re.sub(r"^\s*//.*$", "", f.read(), flags=re.M))
    except OSError:
        return {}
    return data if isinstance(data, dict) else {}


def _server_url(settings):
    for key in ("credentials_url", "server_url"):
        value = settings.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip().rstrip("/")
    return _DEFAULT_SERVER


def _api_url(server):
    host = urllib.parse.urlparse(server).hostname or ""
    if server in (_DEFAULT_SERVER, "https://staging.zed.dev") or host in ("zed.dev", "staging.zed.dev"):
        return _API
    # A custom server answers on its own origin; only HTTPS may carry a token.
    if urllib.parse.urlparse(server).scheme == "https":
        return f"{server}/client/users/me"
    return ""


def _keychain_login(server):
    """(user_id, access_token) from the login Keychain, or ("", "")."""
    if not paths.IS_MACOS:
        return "", ""
    try:
        done = subprocess.run(
            ["/usr/bin/security", "find-internet-password", "-s", server, "-g"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return "", ""
    if done.returncode != 0:
        return "", ""
    account = _ACCOUNT_RE.search(done.stdout)
    secret = re.search(r'^password: "(.*)"$', done.stderr, re.M)
    return (account.group(1) if account else ""), (secret.group(1) if secret else "")


def _plan_label(plan):
    value = plan.get("plan_v3") or plan.get("plan")
    if isinstance(value, dict):
        value = next(iter(value.values()), "") if len(value) == 1 else ""
    return str(value or "").replace("zed_", "").replace("_", " ").title()


def parse_user(body):
    plan = body.get("plan") if isinstance(body, dict) else None
    if not isinstance(plan, dict):
        return None
    predictions = (plan.get("usage") or {}).get("edit_predictions") or {}
    limit = predictions.get("limit")
    unlimited = limit == "unlimited" or (isinstance(limit, dict) and "unlimited" in limit)
    if isinstance(limit, dict):
        limit = limit.get("limited", limit.get("limit"))
    used = finite_number(predictions.get("used"), minimum=0)
    maximum = finite_number(limit, minimum=0)
    period = plan.get("subscription_period") if isinstance(plan.get("subscription_period"), dict) else {}
    return {
        "plan": _plan_label(plan),
        "used": used,
        "limit": None if unlimited else maximum,
        "unlimited": unlimited,
        "resetAt": epoch_of(period.get("ended_at")),
        "overdue": plan.get("has_overdue_invoices") is True,
    }


def get_zed_usage():
    server = _server_url(_settings())
    url = _api_url(server)
    if not url:
        return {"error": "custom server must use https"}
    user_id, token = _keychain_login(server)
    fixture = os.environ.get("ZED_USAGE_RESPONSE_FILE")
    if not fixture and not (user_id and token):
        return {} if paths.IS_MACOS else {"unsupported": True}
    result = fetch_json(
        url,
        headers={"Authorization": f"{user_id} {clean_credential(token)}", "Accept": "application/json", "User-Agent": "ai-usage-widget/zed"},
        timeout=12,
        fixture_path=fixture,
    )
    if result.status != 200:
        return {"error": http_error_text(result.status)}
    parsed = parse_user(as_json(result.body))
    return parsed if parsed is not None else {"error": "unexpected response"}
