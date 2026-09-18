"""Envelope assembly — fetch a set of providers, wrap them in the outer object.

Split out of __main__ so that every in-process consumer builds the identical
envelope: the JSON backend the QML frontends call, and the terminal frontend in
aiusage.cli. See docs/provider-contract.md for the shape produced here.
"""

import time
from concurrent.futures import ThreadPoolExecutor

from . import config
from .collect import collect
from .contract import SCHEMA_VERSION, provider_error, status_summary
from .normalize import normalize

# Name and accent for a provider whose fetch raised — the ones its normalizer
# uses, which never runs in that case.
_CRASH_LABELS = {
    "claude": ("Claude", "#cc785c"),
    "antigravity": ("Antigravity", "#4285f4"),
    "openai": ("OpenAI", "#10a37f"),
    "kiro": ("Kiro", "#8b5cf6"),
    "mistral": ("Mistral", "#ff7000"),
    "openrouter": ("OpenRouter", "#9333ea"),
    "ollama": ("Ollama Cloud", "#f0f0f0"),
    "selfhosted": ("Local Models", "#38bdf8"),
    "grok": ("Grok", "#e6e6e6"),
    "zai": ("Z.AI", "#126ef4"),
    "copilot": ("Copilot", "#8b5cf6"),
    "deepseek": ("DeepSeek", "#4f8cff"),
    "kimi": ("Kimi", "#1e3a8a"),
    "muse": ("Muse", "#0064e0"),
    "cursor": ("Cursor", "#e6e6e6"),
    "cline": ("Cline", "#e6e6e6"),
}


def enabled(cfg):
    """Provider ids switched on in the shared settings file, in contract order."""
    return [id_ for id_ in config.ALL_PROVIDERS if config.provider_enabled(cfg, id_)]


def crashed(id_, now, exc):
    """The error row for a provider whose collect() or normalize() raised.

    Providers are expected to turn every failure into an error of their own;
    this catches what one missed — a file in a shape nobody planned for, a
    platform difference — so that it costs that provider its tab rather than
    failing the whole envelope, and with it every other provider's."""
    label, accent = _CRASH_LABELS.get(id_, (id_, "#888888"))
    message = f"{label}: internal error ({type(exc).__name__}: {exc})"
    return provider_error(id_, label, accent, now, message, {"status": status_summary(None, id_)})


def build(selected, now=None):
    """Fetch every id in `selected` concurrently and return a full envelope."""
    if now is None:
        now = time.time()

    def fetch_one(id_):
        try:
            return normalize(collect(id_, now))
        except Exception as exc:
            return crashed(id_, now, exc)

    if selected:
        with ThreadPoolExecutor(max_workers=len(selected)) as pool:
            providers = list(pool.map(fetch_one, selected))
    else:
        providers = []

    # `active` is the first healthy provider; frontends fall back to it when the
    # tab they remembered is gone.
    active = ""
    for p in providers:
        if p.get("ok") is True:
            active = p.get("id") or ""
            break
    else:
        if providers:
            active = providers[0].get("id") or ""

    return {"schemaVersion": SCHEMA_VERSION, "updatedAt": int(now), "active": active, "providers": providers}
