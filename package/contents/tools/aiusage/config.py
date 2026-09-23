"""Shared settings (provider toggles + API keys).

The Hyprland shell writes the settings file; the Plasma widget passes the same
values through WIDGET_* environment variables. Environment always wins.
"""

import json
import os
import tempfile

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

# Legacy classification: what a missing toggle means in settings that have
# not had the zero-default policy applied (providerDefaultsApplied unset).
OPT_IN_PROVIDERS = {"zai", "copilot", "deepseek", "kimi", "muse", "cursor", "cline", "opencode", "ollama", "selfhosted"}
PROVIDER_DEFAULTS_LATCH = "providerDefaultsApplied"

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


def _legacy_enabled(value, provider_id):
    if provider_id in OPT_IN_PROVIDERS:
        return value is True
    return value is not False


def provider_enabled(cfg, provider_id):
    providers = cfg.get("providers") or {}
    value = providers.get(provider_id)
    # Until the defaults are applied (or when applying them failed), a missing
    # toggle keeps its legacy meaning, so a hand-written or declarative
    # settings file behaves exactly as it did before zero-default.
    if cfg.get(PROVIDER_DEFAULTS_LATCH) is not True:
        return _legacy_enabled(value, provider_id)
    return value is True


def _write_settings(path, settings):
    # A symlink is a managed file (e.g. Home Manager's xdg.configFile into the
    # read-only Nix store): replacing it would clobber the declaration.
    if os.path.islink(path):
        return
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=directory, delete=False) as stream:
            temporary = stream.name
            json.dump(settings, stream, separators=(",", ":"), ensure_ascii=False)
        os.replace(temporary, path)
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def initialize_provider_defaults(detected=None):
    """Apply the shared provider policy once and return the settings.

    Only a fresh install (no settings file) is probed: it starts with every
    provider off except the locally detected ones. An existing file (an
    upgrade, or one seeded by a declarative setup such as Home Manager) keeps
    exactly the providers it already showed: missing toggles are frozen to
    their legacy values and nothing is enabled behind the user's back.
    """
    path = config_path()
    existed = os.path.isfile(path)
    settings = load_settings()
    if settings.get(PROVIDER_DEFAULTS_LATCH) is True:
        return settings

    if existed:
        providers = settings.get("providers")
        providers = dict(providers) if isinstance(providers, dict) else {}
        for provider in ALL_PROVIDERS:
            if not isinstance(providers.get(provider), bool):
                providers[provider] = _legacy_enabled(providers.get(provider), provider)
    else:
        if detected is None:
            from .detect import detect_providers

            detected = detect_providers()
        providers = {provider: provider in detected for provider in ALL_PROVIDERS}
    settings["providers"] = providers
    settings[PROVIDER_DEFAULTS_LATCH] = True
    _write_settings(path, settings)
    return settings
