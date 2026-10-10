"""Pi / OMP local token activity, shared by every frontend."""

from ..messages import tr
from ..stats import opencode_stats
from .local_activity import normalize_local_activity


def normalize_pi(raw):
    usage = raw["inputs"].get("usage")
    usage = usage if isinstance(usage, dict) else {}
    stats = opencode_stats(usage, raw["now"], billed_providers=None)
    r = normalize_local_activity(raw["now"], stats, provider_id="pi", label="Pi", accent="#d4d4d8", mode="local", source="local Pi / OMP sessions")
    if not stats.get("available"):
        r["error"] = tr("Pi: no recorded token usage yet. Run a Pi or OMP session.")
        r["summary"]["detail"] = r["error"]
        return r
    r["summary"]["hasChart"] = False
    agents = usage.get("agents") if isinstance(usage.get("agents"), list) else []
    r["details"]["agents"] = [a for a in agents if isinstance(a, str)]
    return r
