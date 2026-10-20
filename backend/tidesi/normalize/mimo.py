"""Local MiMo Code activity; no account quota is inferred from tokens."""

from ..stats import opencode_stats
from .local_activity import normalize_local_activity


def normalize_mimo(raw):
    stats = opencode_stats(raw["inputs"].get("usage") or {}, raw["now"], billed_providers=None)
    return normalize_local_activity(raw["now"], stats, provider_id="mimo", label="MiMo Code", accent="#E8E8E8", mode="local")
