"""OpenCode account-mode detection and Go quota collection.

OpenCode stores API credentials in ``$XDG_DATA_HOME/opencode/auth.json`` (or
``~/.local/share/opencode/auth.json``) as a top-level provider map. Two
provider ids matter here: ``opencode`` (Zen) and ``opencode-go`` (Go). Only
entries with ``type == "api"`` and a non-empty string ``key`` are valid
credentials.

Mode selection is deterministic: Go wins whenever a valid ``opencode-go``
entry exists, otherwise the provider is Zen. Zen has no public account-level
usage API, so Zen mode stays local-only; Go mode reads the authoritative
account endpoint.

The key is held privately inside this module and never returned, logged, or
included in exceptions or output.
"""

import json
import os

from ..http import as_json, clean_credential, fetch_json, http_error_text

GO_USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
_GO_TIMEOUT_SECONDS = 12


def _auth_path():
    # OpenCode uses xdg-basedir on every OS, including Windows. Our native
    # paths.data_home() would point at AppData there and miss its auth file.
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data_home, "opencode", "auth.json")


def _read_auth():
    try:
        with open(_auth_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _valid_key(entry):
    """The cleaned API key for a provider entry, or "" when it is not a valid
    ``{type: "api", key: <non-empty string>}`` credential."""
    if not isinstance(entry, dict):
        return ""
    if entry.get("type") != "api":
        return ""
    key = entry.get("key")
    if not isinstance(key, str):
        return ""
    key = clean_credential(key)
    if not key or any(ord(ch) < 32 or ord(ch) == 127 for ch in key):
        return ""
    try:
        key.encode("latin-1")
    except UnicodeEncodeError:
        return ""
    return key


def account_mode():
    """``"go"`` when a valid ``opencode-go`` API key exists, else ``"zen"``."""
    auth = _read_auth()
    if not isinstance(auth, dict):
        return "zen"
    if _valid_key(auth.get("opencode-go")):
        return "go"
    return "zen"


def get_go_usage():
    """Fetch the Go account usage endpoint.

    Returns ``(goUsage, goError)``: ``goUsage`` is the parsed JSON object on a
    200 response, else ``None``; ``goError`` is a stable short string (``""``
    on success). A Go failure never falls back to Zen and never reports a
    fabricated zero — the caller keeps mode ``"go"`` and surfaces the error.
    """
    auth = _read_auth()
    if not isinstance(auth, dict):
        return None, ""
    key = _valid_key(auth.get("opencode-go"))
    if not key:
        return None, ""
    result = fetch_json(
        GO_USAGE_URL,
        headers={"Authorization": f"Bearer {key}"},
        timeout=_GO_TIMEOUT_SECONDS,
        fixture_path=os.environ.get("OPENCODE_GO_USAGE_RESPONSE_FILE"),
    )
    if result.status != 200:
        return None, http_error_text(result.status)
    body = as_json(result.body)
    if not isinstance(body, dict):
        return None, "parse error"
    return body, ""
