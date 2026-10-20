"""Windsurf plan quota, read from the editor's own state database.

Windsurf caches its plan in the VS Code-style ``state.vscdb`` (an SQLite file)
under the key ``windsurf.settings.cachedPlanInfo``. Opening it read-only costs
no request and needs no login. The cache is only rewritten while Windsurf is
running, so the figures can be stale; ``recordedAt`` says how stale.
"""

import json
import os
import sqlite3

from .. import paths
from ..contract import epoch_of, finite_number

_KEY = "windsurf.settings.cachedPlanInfo"


def _db_path():
    explicit = os.environ.get("WINDSURF_STATE_DB")
    if explicit:
        return explicit
    return paths.first_file([os.path.join(base, "Windsurf", "User", "globalStorage", "state.vscdb") for base in paths.electron_app_data_dirs()])


def _decode(value):
    if isinstance(value, bytes):
        # ASCII in UTF-16 is also valid UTF-8 (full of NULs), so check for those first.
        for encoding in ("utf-16-le", "utf-8") if b"\x00" in value else ("utf-8", "utf-16-le"):
            try:
                value = value.decode(encoding)
                break
            except UnicodeDecodeError:
                continue
        else:
            return None
    if not isinstance(value, str):
        return None
    try:
        parsed = json.loads(value.strip().strip("\x00"))
    except ValueError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _read_plan(path):
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)
    except sqlite3.Error:
        return None
    try:
        row = conn.execute("SELECT value FROM ItemTable WHERE key = ?", (_KEY,)).fetchone()
    except sqlite3.Error:
        return None
    finally:
        conn.close()
    return _decode(row[0]) if row else None


def _count(block, key):
    return finite_number(block.get(key), minimum=0) if isinstance(block, dict) else None


def _pool(block, total_key, used_key, remaining_key):
    """(used, total) of a counted allowance, whichever half Windsurf wrote."""
    total = _count(block, total_key)
    if not total:
        return None
    used = _count(block, used_key)
    if used is None:
        remaining = _count(block, remaining_key)
        if remaining is None:
            return None
        used = total - remaining
    return {"used": min(max(used, 0.0), total), "total": total}


def _remaining_to_used(value):
    value = finite_number(value, minimum=0, maximum=100)
    return None if value is None else 100.0 - value


def get_windsurf_usage():
    path = _db_path()
    if not os.path.isfile(path):
        return {}
    plan = _read_plan(path)
    if plan is None:
        return {"error": "no plan cached yet — open Windsurf once"}
    quota = plan.get("quotaUsage") if isinstance(plan.get("quotaUsage"), dict) else {}
    usage = plan.get("usage") if isinstance(plan.get("usage"), dict) else {}
    ends = finite_number(plan.get("endTimestamp"), minimum=0)
    try:
        recorded = os.path.getmtime(path)
    except OSError:
        recorded = 0
    result = {
        "plan": plan.get("planName") if isinstance(plan.get("planName"), str) else "",
        # endTimestamp is milliseconds; the quota reset stamps are seconds.
        "expiresAt": int(ends / 1000) if ends else 0,
        "dailyUsedPct": _remaining_to_used(quota.get("dailyRemainingPercent")),
        "weeklyUsedPct": _remaining_to_used(quota.get("weeklyRemainingPercent")),
        "dailyResetAt": epoch_of(finite_number(quota.get("dailyResetAtUnix"), minimum=0) or 0),
        "weeklyResetAt": epoch_of(finite_number(quota.get("weeklyResetAtUnix"), minimum=0) or 0),
        # Older caches carry message/flow-action counters instead of percents.
        "messages": _pool(usage, "messages", "usedMessages", "remainingMessages"),
        "flowActions": _pool(usage, "flowActions", "usedFlowActions", "remainingFlowActions"),
        "recordedAt": recorded,
    }
    return result
