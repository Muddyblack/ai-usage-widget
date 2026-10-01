"""Untested Junie local activity, shared by every frontend."""

from ..stats import opencode_stats
from .local_activity import normalize_local_activity

def normalize_junie(raw):
    usage = raw["inputs"].get("usage")
    usage = usage if isinstance(usage, dict) else {}
    stats = opencode_stats(usage, raw["now"], billed_providers=None)
    r = normalize_local_activity(raw["now"], stats, provider_id="junie", label="Junie", accent="#48e054", mode="local", source="local Junie events")
    r["summary"]["hasChart"] = False
    r["details"]["untested"] = True
    r["summary"]["detail"] += " · untested"
    sessions = usage.get("sessions")
    sessions = [row for row in sessions if isinstance(row, dict)] if isinstance(sessions, list) else []
    r["details"]["sessionCount"] = len(sessions)
    if not stats.get("available"):
        r["error"] = "Junie (untested): no recorded token usage yet. Run a session using /account or junie --provider google."
        r["summary"]["detail"] = r["error"]
        r["slots"][0]["tooltip"] = r["summary"]["detail"]
    else:
        incomplete = any(
            bucket.get("tokensComplete") is False
            for row in sessions
            if isinstance(row.get("usage"), list)
            for bucket in row["usage"]
            if isinstance(bucket, dict)
        )
        r["details"]["tokensPartial"] = incomplete
    return r
