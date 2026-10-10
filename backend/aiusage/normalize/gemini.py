"""Gemini CLI local token activity, shared by every frontend."""

from ..messages import tr
from ..stats import opencode_stats
from .local_activity import normalize_local_activity

ACCENT = "#3186ff"


def normalize_gemini(raw):
    usage = raw["inputs"].get("usage")
    usage = usage if isinstance(usage, dict) else {}
    stats = opencode_stats(usage, raw["now"], billed_providers=None)
    r = normalize_local_activity(
        raw["now"], stats, provider_id="gemini", label="Gemini", accent=ACCENT, mode="local", source="local Gemini CLI chats"
    )
    if not stats.get("available"):
        r["error"] = tr("Gemini: no recorded token usage yet. Run a Gemini CLI session.")
        r["summary"]["detail"] = r["error"]
        return r
    r["summary"]["hasChart"] = False
    return r
