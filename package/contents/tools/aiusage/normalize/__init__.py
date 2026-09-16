from ..contract import provider_error, status_summary
from .antigravity import normalize_antigravity
from .claude import normalize_claude
from .cline import normalize_cline
from .copilot import normalize_copilot
from .cursor import normalize_cursor
from .deepseek import normalize_deepseek
from .grok import normalize_grok
from .kiro import normalize_kiro
from .mistral import normalize_mistral
from .moonshot import normalize_moonshot
from .muse import normalize_muse
from .ollama import normalize_ollama
from .openai import normalize_openai
from .openrouter import normalize_openrouter
from .zai import normalize_zai

_DISPATCH = {
    "claude": normalize_claude,
    "openai": normalize_openai,
    "antigravity": normalize_antigravity,
    "kiro": normalize_kiro,
    "mistral": normalize_mistral,
    "muse": normalize_muse,
    "openrouter": normalize_openrouter,
    "ollama": normalize_ollama,
    "grok": normalize_grok,
    "zai": normalize_zai,
    "copilot": normalize_copilot,
    "deepseek": normalize_deepseek,
    "kimi": normalize_moonshot,
    "cursor": normalize_cursor,
    "cline": normalize_cline,
}


def normalize(raw):
    id_ = raw.get("id")
    fn = _DISPATCH.get(id_)
    if fn is None:
        r = provider_error(id_, id_, "#888888", raw.get("now") or 0, f"unknown provider: {id_}", {})
    else:
        r = fn(raw)
    # Attached here rather than in each normalizer so every provider carries
    # the same block — error states included — and both frontends can draw one
    # status chip from it without a provider table of their own.
    if isinstance(r.get("details"), dict):
        r["details"]["status"] = status_summary((raw.get("inputs") or {}).get("status"), id_)
    return r
