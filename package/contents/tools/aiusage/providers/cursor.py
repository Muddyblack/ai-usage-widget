"""Cursor plan usage, read with the login cursor-agent or the Cursor IDE stored.

cursor-agent keeps its session in $XDG_CONFIG_HOME/cursor/auth.json; the IDE
keeps the same bearer token in its state.vscdb under cursorAuth/accessToken.
Either one answers the two dashboard RPCs the CLI's own /usage screen calls —
GetCurrentPeriodUsage and GetPlanInfo, Connect protocol with a JSON body — so
the IDE is not required.

Both response bodies are handed to the normalizer as they arrive; neither
carries a credential. The token is only read, never refreshed: cursor-agent
owns that, and its tokens are long-lived.
"""

import base64
import json
import os
import sqlite3
import time

from .. import keychain, paths
from ..contract import num
from ..http import as_json, clean_credential, fetch_json, http_error_text

_API = "https://api2.cursor.sh/aiserver.v1.DashboardService"


def _config_home():
    return paths.config_home()


# What `cursor-agent login` writes into the macOS login Keychain.
_AGENT_KEYCHAIN_SERVICE = "cursor-access-token"
_AGENT_KEYCHAIN_ACCOUNT = "cursor-user"


def _agent_token_from(path):
    if not path or not os.path.isfile(path):
        return ""
    try:
        with open(path, encoding="utf-8") as f:
            data = as_json(f.read())
    except OSError:
        return ""
    return clean_credential(data.get("accessToken")) if isinstance(data, dict) else ""


def _agent_token():
    """cursor-agent's login.

    The CLI writes $XDG_CONFIG_HOME/cursor/auth.json on Linux and Windows. On
    macOS it puts the token in the login Keychain instead and leaves only
    identity behind in ~/.cursor/, so the file lookup alone found nothing
    there — unless AGENT_CLI_CREDENTIAL_STORE=file was set, which makes it
    write ~/.cursor/auth.json as well. All three are read, the Keychain first
    on macOS so a config directory shared with a Linux machine cannot answer
    with that machine's stale token."""
    explicit = os.environ.get("CURSOR_AUTH_PATH")
    if explicit:
        return _agent_token_from(explicit)

    token = clean_credential(keychain.password(_AGENT_KEYCHAIN_SERVICE, _AGENT_KEYCHAIN_ACCOUNT))
    if token:
        return token
    for path in (os.path.join(_config_home(), "cursor", "auth.json"), os.path.expanduser("~/.cursor/auth.json")):
        token = _agent_token_from(path)
        if token:
            return token
    return ""


def _ide_token():
    path = os.environ.get("CURSOR_IDE_DB") or paths.first_file(
        [os.path.join(base, "Cursor", "User", "globalStorage", "state.vscdb") for base in paths.electron_app_data_dirs()]
    )
    if not os.path.isfile(path):
        return ""
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)
    except sqlite3.Error:
        return ""
    try:
        row = conn.execute("SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'").fetchone()
    except sqlite3.Error:
        return ""
    finally:
        conn.close()
    if not row or row[0] is None:
        return ""
    value = row[0].decode("utf-8", "replace") if isinstance(row[0], bytes) else str(row[0])
    return clean_credential(value.strip().strip('"'))


def _cursor_token():
    """(token, source) — cursor-agent first, the IDE second."""
    token = _agent_token()
    if token:
        return token, "cli"
    token = _ide_token()
    if token:
        return token, "ide"
    return "", ""


def _jwt_expiry(token):
    try:
        payload = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        return num(claims.get("exp"))
    except (IndexError, ValueError, AttributeError, TypeError):
        return 0


def _call(method, token, fixture_env, body=None):
    return fetch_json(
        f"{_API}/{method}",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "User-Agent": "kde-ai-usage/cursor",
        },
        timeout=12,
        fixture_path=os.environ.get(fixture_env),
        data=json.dumps(body or {}).encode(),
    )


# The dashboard's per-request list is paged; a heavy month runs to thousands of
# requests, and the widget polls. Five pages is a whole month for most people —
# past that the stats say they are partial rather than fetch without bound.
_STATS_PAGES = 5
_PAGE_SIZE = 100


def _slim_event(event, conversations):
    """Just what the stats need. The raw event also names the account (email,
    user and team ids) and the conversation; none of that leaves this module —
    a conversation is reduced to a running number, enough to count sessions."""
    usage = event.get("tokenUsage") if isinstance(event.get("tokenUsage"), dict) else {}
    conversation = event.get("conversationId")
    index = conversations.setdefault(conversation, len(conversations)) if isinstance(conversation, str) and conversation else -1
    cents = event.get("chargedCents")
    return {
        "timestamp": num(event.get("timestamp")),
        "model": event.get("model") if isinstance(event.get("model"), str) else "",
        "conversation": index,
        "input": num(usage.get("inputTokens")),
        "output": num(usage.get("outputTokens")),
        "cacheWrite": num(usage.get("cacheWriteTokens")),
        "cacheRead": num(usage.get("cacheReadTokens")),
        "cents": num(cents if cents is not None else usage.get("totalCents")),
    }


def _stats(token, start_ms, now_ms):
    """The two RPCs behind the dashboard's Usage page, for the current billing
    cycle. Both work for a personal account without a team id (verified live;
    GetFilteredUsageEvents rejects the dashboard's teamId -1 with a 401)."""
    window = {"startDate": str(start_ms), "endDate": str(now_ms)}
    agg = _call("GetAggregatedUsageEvents", token, "CURSOR_AGGREGATED_RESPONSE_FILE", window)
    aggregated = as_json(agg.body) if agg.status == 200 else None
    if not isinstance(aggregated, dict):
        return None

    events, conversations, total = [], {}, 0
    for page in range(1, _STATS_PAGES + 1):
        res = _call("GetFilteredUsageEvents", token, "CURSOR_EVENTS_RESPONSE_FILE", {**window, "page": page, "pageSize": _PAGE_SIZE})
        body = as_json(res.body) if res.status == 200 else None
        if not isinstance(body, dict):
            break
        total = int(num(body.get("totalUsageEventsCount")))
        batch = [e for e in body.get("usageEventsDisplay") or [] if isinstance(e, dict)]
        events.extend(_slim_event(e, conversations) for e in batch)
        if len(batch) < _PAGE_SIZE or len(events) >= total:
            break
    return {"aggregated": aggregated, "events": events, "eventCount": max(total, len(events)), "startMs": start_ms}


def get_cursor_usage():
    token, source = _cursor_token()
    if not token:
        return {}
    expires = _jwt_expiry(token)
    if expires and expires <= time.time():
        return {"loggedIn": True, "source": source, "error": "login expired — run cursor-agent login"}

    usage = _call("GetCurrentPeriodUsage", token, "CURSOR_USAGE_RESPONSE_FILE")
    if usage.status in (401, 403):
        return {"loggedIn": True, "source": source, "error": "login rejected — run cursor-agent login"}
    if usage.status != 200:
        return {"loggedIn": True, "source": source, "error": http_error_text(usage.status)}
    body = as_json(usage.body)
    if not isinstance(body, dict):
        return {"loggedIn": True, "source": source, "error": "usage response could not be parsed"}

    # The plan name and the stats are niceties: their failure must not cost
    # the usage numbers.
    plan = _call("GetPlanInfo", token, "CURSOR_PLAN_RESPONSE_FILE")
    plan_body = as_json(plan.body) if plan.status == 200 else None
    now_ms = int(time.time() * 1000)
    start_ms = int(num(body.get("billingCycleStart"))) or now_ms - 30 * 86400 * 1000
    stats = _stats(token, start_ms, now_ms)
    return {
        "loggedIn": True,
        "source": source,
        "usage": body,
        "plan": plan_body if isinstance(plan_body, dict) else {},
        "stats": stats or {},
    }
