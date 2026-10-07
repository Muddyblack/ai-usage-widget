"""Resolve a GitHub credential and read Copilot premium-request usage.

Two things make this provider different from every other HTTP one here.

Discovery: a Copilot user almost never has a GITHUB_TOKEN exported. What they
do have is one of the editor/CLI logins already sitting on disk — the same
"look for the tool's own config directory" trick this package uses for Claude
(~/.claude/.credentials.json) and Codex (~/.codex/auth.json). So the resolver
walks the Copilot plugin config (apps.json/hosts.json), the Copilot CLI's own
directory, and finally asks `gh auth token`, before giving up and reporting
"no token configured".

Endpoint: /users/{u}/settings/billing/premium_request/usage needs a token with
billing scope, which none of those borrowed logins has. The endpoint the
editors themselves use — /copilot_internal/user — answers any Copilot login
with a quota snapshot, and carries the real reset date instead of our guess of
"the first of next month". It is undocumented, so the billing endpoint stays as
the fallback for tokens that do carry the scope.
"""

import json
import os
import shutil
import subprocess

from .. import paths
from ..http import as_json, clean_credential, error_json, fetch_json, http_error_json, resolve_key

# Sent by the Copilot editor plugins; /copilot_internal rejects a request that
# does not identify an editor.
_EDITOR_HEADERS = {
    "Editor-Version": "vscode/1.99.0",
    "Editor-Plugin-Version": "copilot-chat/0.26.0",
    "User-Agent": "GitHubCopilotChat/0.26.0",
}


def _config_home():
    return paths.config_home()


def _windows_plugin_dir():
    """The Copilot plugins keep their login under %LOCALAPPDATA% on Windows,
    not under %APPDATA% where config_home() points."""
    return [os.path.join(paths.data_home(), "github-copilot")] if paths.IS_WINDOWS else []


def _plugin_dirs():
    """Where the Copilot plugins and the Copilot CLI keep their login. The
    plugins write under $XDG_CONFIG_HOME when it is set and under ~/.config
    when it is not, and the two disagree often enough to be worth checking
    both."""
    dirs = []
    for path in (
        os.path.join(_config_home(), "github-copilot"),
        os.path.expanduser("~/.config/github-copilot"),
        *_windows_plugin_dir(),
        os.path.expanduser("~/.copilot"),
    ):
        if path not in dirs:
            dirs.append(path)
    return dirs


def _oauth_from_apps_json(path):
    """apps.json / hosts.json is a map of "<host>:<app id>" to a login record:

        {"github.com:Iv1.b507a08c87ecfe98": {"user": "octocat",
                                             "oauth_token": "gho_..."}}

    Enterprise hosts appear under the same shape, so github.com wins when both
    are present — the usage endpoints here are dotcom-only. The host is the
    segment before the first colon and is compared whole: a prefix test would
    accept github.company.com, whose first ten characters are "github.com".
    """
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return "", ""
    if not isinstance(data, dict):
        return "", ""

    fallback = ("", "")
    for key, entry in data.items():
        if not isinstance(entry, dict):
            continue
        token = entry.get("oauth_token")
        if not isinstance(token, str) or token == "":
            continue
        user = entry.get("user") if isinstance(entry.get("user"), str) else ""
        if isinstance(key, str) and key.split(":", 1)[0] == "github.com":
            return token, user
        if fallback == ("", ""):
            fallback = (token, user)
    return fallback


def _gh_cli_token():
    """`gh auth token` — the token itself lives in the system keyring on most
    installs, so reading ~/.config/gh/hosts.yml is not enough."""
    gh = shutil.which("gh")
    if not gh:
        return ""
    try:
        proc = subprocess.run(
            [gh, "auth", "token", "--hostname", "github.com"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=10,
            **paths.no_window(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if proc.returncode != 0:
        return ""
    return clean_credential(proc.stdout)


def _copilot_cli_login():
    """~/.copilot/config.json records who the Copilot CLI is logged in as, but
    never the token (that is in the keyring). The login still saves a request:
    it is the username the billing endpoint needs."""
    try:
        with open(os.path.expanduser("~/.copilot/config.json"), encoding="utf-8") as f:
            # The file is JSON with a leading // comment banner.
            text = "\n".join(line for line in f if not line.lstrip().startswith("//"))
    except OSError:
        return ""
    data = as_json(text)
    if not isinstance(data, dict):
        return ""
    last = data.get("lastLoggedInUser")
    if isinstance(last, dict) and isinstance(last.get("login"), str):
        return last["login"]
    users = data.get("loggedInUsers")
    if isinstance(users, list):
        for entry in users:
            if isinstance(entry, dict) and isinstance(entry.get("login"), str):
                return entry["login"]
    return ""


def _github_token():
    """(token, username) — the username is whatever the source happened to
    know, "" when it knew none."""
    token = resolve_key(
        "WIDGET_GITHUB_TOKEN",
        ("GITHUB_TOKEN", "GH_TOKEN"),
        os.path.join(_config_home(), "github-copilot", "token"),
        os.path.expanduser("~/.config/github-copilot/token"),
    )
    if token:
        return token, ""

    for directory in _plugin_dirs():
        for name in ("apps.json", "hosts.json"):
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            token, user = _oauth_from_apps_json(path)
            if token:
                return token, user

    token = _gh_cli_token()
    if token:
        return token, _copilot_cli_login()
    return "", ""


def _github_get(url, api_key, fixture_path, extra_headers=None):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "kde-ai-usage/copilot",
    }
    if extra_headers:
        headers.update(extra_headers)
    return fetch_json(url, headers=headers, timeout=10, fixture_path=fixture_path)


def _configured_quota():
    raw = os.environ.get("WIDGET_COPILOT_QUOTA") or os.environ.get("COPILOT_QUOTA") or ""
    try:
        return int(raw)
    except ValueError:
        return 0


def _from_quota_snapshot(body, quota_override):
    """Shape /copilot_internal/user into the provider result, or None when the
    response carries no premium-request quota (older plans, or a token GitHub
    answers with an account stub)."""
    if not isinstance(body, dict):
        return None
    snapshots = body.get("quota_snapshots")
    if not isinstance(snapshots, dict):
        return None
    premium = snapshots.get("premium_interactions")
    if not isinstance(premium, dict) or premium.get("has_quota") is False:
        return None

    entitlement = premium.get("entitlement")
    remaining = premium.get("quota_remaining")
    if remaining is None:
        remaining = premium.get("remaining")
    unlimited = premium.get("unlimited") is True

    if not isinstance(entitlement, (int, float)) or isinstance(entitlement, bool):
        entitlement = 0
    if not isinstance(remaining, (int, float)) or isinstance(remaining, bool):
        remaining = 0

    # The plan entitlement is authoritative; the setting only fills in for a
    # response that reports none (and for the unlimited plans, where there is
    # nothing to fill in).
    quota = quota_override if quota_override > 0 and entitlement <= 0 else entitlement
    used = max(0, entitlement - remaining) if entitlement > 0 else premium.get("credits_used") or 0
    if not isinstance(used, (int, float)) or isinstance(used, bool):
        used = 0

    percent_remaining = premium.get("percent_remaining")
    if isinstance(percent_remaining, (int, float)) and not isinstance(percent_remaining, bool):
        pct = max(0, min(100, 100 - percent_remaining))
    else:
        pct = min(100, (used / quota) * 100) if quota > 0 else 0

    login = body.get("login")
    return {
        "hasKey": True,
        "keyValid": True,
        "username": login if isinstance(login, str) else "",
        "used": round(used, 2),
        "quota": quota,
        "pct": 0 if unlimited else pct,
        "unlimited": unlimited,
        "resetDate": body.get("quota_reset_date") if isinstance(body.get("quota_reset_date"), str) else "",
        "plan": body.get("copilot_plan") if isinstance(body.get("copilot_plan"), str) else "",
        "source": "copilot",
    }


def _billing_usage(api_key, username, quota):
    """The documented endpoint. Needs a token with billing scope, so this is
    where an explicitly configured PAT is spent."""
    if not username:
        user_result = _github_get("https://api.github.com/user", api_key, os.environ.get("COPILOT_USER_RESPONSE_FILE"))
        if user_result.status != 200:
            return http_error_json("GitHub", user_result.status, "Invalid GitHub token")
        user_body = as_json(user_result.body) or {}
        username = user_body.get("login")
        if not isinstance(username, str) or username == "":
            return error_json("GitHub username missing")

    usage_result = _github_get(
        f"https://api.github.com/users/{username}/settings/billing/premium_request/usage",
        api_key,
        os.environ.get("COPILOT_USAGE_RESPONSE_FILE"),
    )
    if usage_result.status != 200:
        return http_error_json(
            "GitHub Copilot",
            usage_result.status,
            "GitHub token cannot read Copilot premium request usage",
        )

    usage_body = as_json(usage_result.body)
    if usage_body is None:
        return error_json("GitHub Copilot invalid JSON")

    items = usage_body if isinstance(usage_body, list) else (usage_body.get("usageItems") or [])
    used = 0
    for item in items:
        q = item.get("grossQuantity") or 0
        if not isinstance(q, (int, float)) or isinstance(q, bool):
            try:
                q = float(q)
            except (TypeError, ValueError):
                q = 0
        used += q

    return {
        "hasKey": True,
        "keyValid": True,
        "username": username,
        "used": used,
        "quota": quota,
        "pct": min(100, (used / quota) * 100) if quota > 0 else 0,
        "source": "billing",
    }


def get_copilot_usage():
    api_key, username = _github_token()
    if not api_key:
        return {}

    quota_override = _configured_quota()

    internal = _github_get(
        "https://api.github.com/copilot_internal/user",
        api_key,
        os.environ.get("COPILOT_INTERNAL_RESPONSE_FILE"),
        _EDITOR_HEADERS,
    )
    if internal.status == 200:
        result = _from_quota_snapshot(as_json(internal.body), quota_override)
        if result is not None:
            return result

    return _billing_usage(api_key, username, quota_override or 300)
