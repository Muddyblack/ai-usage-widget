"""Local MiMo Code activity; no account quota is inferred from tokens."""

from ..stats import opencode_stats
from .opencode import _normalize_zen


def normalize_mimo(raw):
    stats = opencode_stats(raw["inputs"].get("usage") or {}, raw["now"], billed_providers=None)
    return _normalize_zen(raw["now"], stats, provider_id="mimo", label="MiMo Code", accent="#E8E8E8", mode="local")
