"""Claude Code's login, wherever the platform it runs on keeps it.

Linux and Windows: ``~/.claude/.credentials.json``. macOS: the login Keychain,
because Claude Code migrated the login there and deletes the file as it goes —
so on a Mac the file, when one is still around, is usually a stale copy from
before that migration or from a session where the Keychain was locked. Both are
read there and the fresher of the two wins.

Nothing here ever refreshes a token. Anthropic allows one live refresh token
per client, so a refresh from this widget would sign the user out of Claude
Code itself; an expired login is reported as expired and left alone.
"""

import hashlib
import os
import time

from .. import keychain, paths
from ..http import as_json, resolve_key

# The generic-password item Claude Code writes on macOS, in the login keychain
# and under the account name of the user running it.
KEYCHAIN_SERVICE = "Claude Code-credentials"


def claude_config_dir():
    """``$CLAUDE_CONFIG_DIR`` when set, else ``~/.claude`` — the directory
    Claude Code keeps its login, settings and projects under."""
    return os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")


def keychain_service():
    """The Keychain service name for this config directory.

    Claude Code keys the item to ``CLAUDE_CONFIG_DIR`` so that two config
    directories are two logins, appending a digest of the variable *as written*
    — an unexpanded ``~/...`` hashes as the tilde string. With the variable
    unset the plain name is used.
    """
    raw = os.environ.get("CLAUDE_CONFIG_DIR") or ""
    if not raw:
        return KEYCHAIN_SERVICE
    return f"{KEYCHAIN_SERVICE}-{hashlib.sha256(raw.encode('utf-8')).hexdigest()[:8]}"


def _keychain_credentials():
    """The login Keychain's copy on macOS, else None."""
    if not paths.IS_MACOS:
        return None
    try:
        account = os.environ.get("USER") or os.getlogin()
    except OSError:
        return None
    if not account:
        return None
    # The derived name first; the plain one after it, because the way the
    # digest is derived is not documented and an install that keyed the item
    # differently should still be found. With no CLAUDE_CONFIG_DIR the two are
    # the same name and the second lookup never happens.
    for service in dict.fromkeys([keychain_service(), KEYCHAIN_SERVICE]):
        parsed = as_json(keychain.password(service, account))
        if isinstance(parsed, dict):
            return parsed
    return None


def _file_credentials():
    """``.credentials.json`` under the config directory, else None."""
    path = os.path.join(claude_config_dir(), ".credentials.json")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            parsed = as_json(f.read())
    except OSError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _expires_at(creds):
    """``claudeAiOauth.expiresAt`` in epoch milliseconds, 0 when unreadable.

    Written by another program and read verbatim, so nothing guarantees the
    shape: a missing or non-numeric value sorts as the oldest.
    """
    oauth = (creds or {}).get("claudeAiOauth")
    if not isinstance(oauth, dict):
        return 0.0
    try:
        return float(oauth.get("expiresAt"))
    except (TypeError, ValueError):
        return 0.0


def _pick(candidates):
    """The credential document to trust, of the ones this platform yielded.

    Only macOS ever has two. Preferring the file there would report "token
    expired" at a user whose Keychain holds a working token, and preferring the
    Keychain outright would miss the login of a session that could not write to
    it — so whichever is still valid wins, the later expiry breaks a tie
    between two valid ones, and the Keychain wins an exact tie.
    """
    candidates = [c for c in candidates if isinstance(c, dict) and c]
    if not candidates:
        return {}
    now_ms = time.time() * 1000
    unexpired = [c for c in candidates if _expires_at(c) > now_ms]
    return max(unexpired or candidates, key=_expires_at)


def get_claude_credentials():
    oauth_creds = _pick([_keychain_credentials(), _file_credentials()])

    admin_key = resolve_key(
        "WIDGET_CLAUDE_ADMIN_KEY",
        "CLAUDE_ADMIN_API_KEY",
        # paths.config_home() first so $XDG_CONFIG_HOME is honoured, as it is
        # everywhere else in this package; the plain ~/.config after it, for a
        # key file written before that was true.
        os.path.join(paths.config_home(), "claude-admin-api-key"),
        os.path.expanduser("~/.config/claude-admin-api-key"),
        os.path.join(claude_config_dir(), "admin-api-key"),
    )

    if oauth_creds:
        if admin_key:
            return {**oauth_creds, "claudeAdminApiKey": admin_key}
        return oauth_creds
    if admin_key:
        return {"claudeAdminApiKey": admin_key}
    return {}
