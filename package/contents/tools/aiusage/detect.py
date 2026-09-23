"""Metadata-only detection of locally evidenced provider tools and logins."""

import glob
import os
import shutil

from . import config, paths

AUTO_DETECT_PROVIDERS = (
    "claude",
    "antigravity",
    "openai",
    "kiro",
    "mistral",
    "grok",
    "muse",
    "cursor",
    "cline",
    "opencode",
)


def _file(path):
    return bool(path) and os.path.isfile(path)


def _directory(path):
    return bool(path) and os.path.isdir(path)


def _has_entries(path):
    if not _directory(path):
        return False
    try:
        with os.scandir(path) as entries:
            return next(entries, None) is not None
    except OSError:
        return False


def _has_files(path):
    if not _directory(path):
        return False
    for _root, _directories, files in os.walk(path):
        if files:
            return True
    return False


def _any_file(candidates):
    return any(_file(path) for path in candidates)


def _claude():
    root = os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")
    return _file(os.path.join(root, ".credentials.json")) or _has_entries(os.path.join(root, "projects"))


def _antigravity():
    root = os.path.expanduser(os.environ.get("ANTIGRAVITY_HOME") or os.environ.get("GEMINI_HOME") or "~/.gemini")
    return (
        _file(os.path.join(root, "google_accounts.json"))
        or _has_files(os.path.join(root, "antigravity-cli", "brain"))
        or _has_files(os.path.join(root, "antigravity", "brain"))
    )


def _openai():
    root = os.path.expanduser(os.environ.get("CODEX_HOME") or "~/.codex")
    return _file(os.path.join(root, "auth.json")) or _has_files(os.path.join(root, "sessions"))


def _kiro():
    cli_db = os.environ.get("KIRO_CLI_DB")
    if _file(cli_db):
        return True
    cli_dbs = [os.path.join(base, "kiro-cli", "data.sqlite3") for base in paths.data_home_dirs()]
    ide_db = os.environ.get("KIRO_IDE_DB")
    ide_dbs = [os.path.join(base, "Kiro", "User", "globalStorage", "state.vscdb") for base in paths.electron_app_data_dirs()]
    return _any_file(cli_dbs) or _file(ide_db) or _any_file(ide_dbs)


def _mistral():
    root = os.path.expanduser(os.environ.get("VIBE_HOME") or "~/.vibe")
    return _has_files(os.path.join(root, "logs", "session"))


def _grok():
    root = os.path.expanduser(os.environ.get("GROK_HOME") or "~/.grok")
    return _file(os.path.join(root, "auth.json")) or _has_files(os.path.join(root, "sessions"))


def _muse():
    auth = os.environ.get("MUSE_AUTH_PATH") or os.path.join(paths.config_home(), "muse", "auth.json")
    if _file(auth):
        return True
    sessions = os.environ.get("MUSE_SESSIONS_DIR")
    if sessions:
        return _has_entries(sessions)
    return any(_has_entries(os.path.join(base, "muse", "sessions")) for base in paths.data_home_dirs())


def _cursor():
    auth = os.environ.get("CURSOR_AUTH_PATH")
    auth_paths = [auth] if auth else [os.path.join(paths.config_home(), "cursor", "auth.json"), os.path.expanduser("~/.cursor/auth.json")]
    chats = os.environ.get("CURSOR_CHATS_DIR") or os.path.expanduser("~/.cursor/chats")
    ide_db = os.environ.get("CURSOR_IDE_DB")
    ide_dbs = [os.path.join(base, "Cursor", "User", "globalStorage", "state.vscdb") for base in paths.electron_app_data_dirs()]
    return _any_file(auth_paths) or _has_files(chats) or _file(ide_db) or _any_file(ide_dbs)


def _cline():
    root = os.environ.get("CLINE_SESSIONS_DIR") or os.path.expanduser("~/.cline/data/sessions")
    return _has_entries(root)


def _opencode():
    explicit = os.environ.get("OPENCODE_DB", "").strip()
    if _file(explicit) or bool(shutil.which("opencode")):
        return True
    for base in paths.data_home_dirs():
        if _has_files(os.path.join(base, "opencode")):
            return True
        for pattern in (os.path.join(base, "opencode*.db"), os.path.join(base, "opencode", "opencode*.db")):
            if any(_file(path) for path in glob.glob(pattern)):
                return True
    return False


_PROBES = {
    "claude": _claude,
    "antigravity": _antigravity,
    "openai": _openai,
    "kiro": _kiro,
    "mistral": _mistral,
    "grok": _grok,
    "muse": _muse,
    "cursor": _cursor,
    "cline": _cline,
    "opencode": _opencode,
}


def detect_providers():
    """Return locally evidenced providers in canonical provider order."""
    allowed = set(AUTO_DETECT_PROVIDERS)
    return [provider for provider in config.ALL_PROVIDERS if provider in allowed and _PROBES[provider]()]
