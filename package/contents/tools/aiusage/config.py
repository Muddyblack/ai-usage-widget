"""Shared settings (provider toggles + API keys).

The Hyprland shell writes the settings file; the Plasma widget passes the same
values through WIDGET_* environment variables. Environment always wins.
"""

import json
import os

from . import paths

ALL_PROVIDERS = [
    "claude",
    "antigravity",
    "openai",
    "kiro",
    "mistral",
    "openrouter",
    "ollama",
    "selfhosted",
    "grok",
    "zai",
    "copilot",
    "deepseek",
    "kimi",
    "muse",
    "cursor",
    "cline",
    "opencode",
]

# Providers that stay off until explicitly enabled: most need a token the user
# has to paste, so defaulting them on would only produce error rows. Muse,
# Cursor and Cline need no token at all — they are opt-in because a machine
# without the tool installed should not grow a tab for it.
OPT_IN_PROVIDERS = {"zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "opencode", "ollama", "selfhosted"}

_KEY_EXPORTS = [
    ("WIDGET_CLAUDE_ADMIN_KEY", "claudeAdmin"),
    ("WIDGET_OPENAI_API_KEY", "openai"),
    ("WIDGET_MISTRAL_API_KEY", "mistral"),
    ("WIDGET_OPENROUTER_API_KEY", "openrouter"),
    ("WIDGET_OLLAMA_API_KEY", "ollama"),
    ("WIDGET_SELFHOSTED_KEY", "selfhosted"),
    ("WIDGET_GROK_API_KEY", "grok"),
    ("WIDGET_ZAI_TOKEN", "zai"),
    ("WIDGET_GITHUB_TOKEN", "github"),
    ("WIDGET_MUSE_API_KEY", "muse"),
    ("WIDGET_DEEPSEEK_API_KEY", "deepseek"),
    ("WIDGET_MOONSHOT_API_KEY", "moonshot"),
]


def config_path():
    # The name predates the Windows frontend, which shares the same file and
    # format — renaming it would orphan every existing Hyprland config.
    return os.environ.get(
        "AI_USAGE_CONFIG",
        os.path.join(paths.config_home(), paths.APP_DIR, "hyprland-settings.json"),
    )


def cache_dir():
    return os.environ.get(
        "AI_USAGE_CACHE_DIR",
        os.path.join(paths.cache_home(), paths.APP_DIR),
    )


def status_ttl():
    try:
        return int(os.environ.get("AI_USAGE_STATUS_TTL", "300"))
    except ValueError:
        return 300


def load_settings():
    path = config_path()
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def cfg_key(cfg, key):
    return (cfg.get("keys") or {}).get(key) or ""


def apply_widget_env(cfg):
    """Export WIDGET_* variables from the settings file, but only when the
    caller (environment) has not already provided one."""
    for var, key in _KEY_EXPORTS:
        if os.environ.get(var):
            continue
        value = cfg_key(cfg, key)
        if value:
            os.environ[var] = value

    if not os.environ.get("WIDGET_COPILOT_QUOTA"):
        quota = cfg.get("copilotQuota", (cfg.get("keys") or {}).get("copilotQuota", 300))
        try:
            quota = int(quota)
        except (TypeError, ValueError):
            quota = 300
        os.environ["WIDGET_COPILOT_QUOTA"] = str(quota)

    if not os.environ.get("WIDGET_MUSE_QUOTA"):
        os.environ["WIDGET_MUSE_QUOTA"] = "1" if cfg.get("museQuota", False) is True else "0"

    for var, key in (("WIDGET_SELFHOSTED_ENDPOINT", "selfhostedEndpoint"), ("WIDGET_SELFHOSTED_ENGINE", "selfhostedEngine")):
        if not os.environ.get(var) and cfg.get(key):
            os.environ[var] = str(cfg[key])


def muse_quota_enabled():
    """Muse's live quota costs one small model call per TTL, so it is OFF until
    the user asks for it.

    The provider contract says reading a statistic must not cost the user, and
    Meta exposes this snapshot only on a billed Responses stream — no free
    endpoint, no local copy, and the event arrives last so the stream cannot be
    cut short. Opt-in is the only default that honours the contract: out of the
    box the Muse tab reads local files and spends nothing."""
    return os.environ.get("WIDGET_MUSE_QUOTA", "0").strip().lower() not in ("0", "false", "no", "off")


def provider_enabled(cfg, provider_id):
    providers = cfg.get("providers") or {}
    value = providers.get(provider_id)
    if provider_id in OPT_IN_PROVIDERS:
        return value is True
    return value is not False
