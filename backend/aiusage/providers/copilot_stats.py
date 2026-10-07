"""Aggregate lifetime Copilot CLI activity from ~/.copilot/session-store.db.

The CLI keeps its history in a plain SQLite file — sessions, one row per turn,
one row per trajectory (tool/command) event and the files each session touched.
It records no token counts and no model, so this produces the activity half of
the stats blob Claude and Codex fill in (see stats.py); the token tiles simply
have nothing to show.

Everything is aggregated in SQL: a heavy user's store has tens of thousands of
turn rows, and the widget polls.
"""

import datetime
import os
import sqlite3

from ..contract import epoch_of


def _db_path():
    return os.environ.get("COPILOT_SESSION_DB") or os.path.expanduser("~/.copilot/session-store.db")


def _rows(conn, sql):
    """A missing table means an older or newer CLI schema — that costs the one
    metric, never the whole section."""
    try:
        return conn.execute(sql).fetchall()
    except sqlite3.Error:
        return []


def _iso_secs(value):
    """Both timestamp spellings the store uses: the CLI writes
    2026-09-08T10:31:07.741Z, the column default writes 2026-09-08 10:31:07 —
    which epoch_of reads once the separator is the one ISO-8601 expects."""
    if not isinstance(value, str):
        return 0
    return epoch_of(value.replace(" ", "T", 1))


def get_copilot_stats():
    path = _db_path()
    if not os.path.isfile(path):
        return {}
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=2)
    except sqlite3.Error:
        return {}

    try:
        sessions = _rows(conn, "SELECT id, repository, created_at, updated_at FROM sessions")
        if not sessions:
            return {}

        turns_by_day = dict(_rows(conn, "SELECT substr(timestamp, 1, 10) d, count(*) FROM turns GROUP BY d"))
        turns_by_hour = _rows(conn, "SELECT substr(timestamp, 12, 2) h, count(*) FROM turns GROUP BY h")
        turns_by_session = dict(_rows(conn, "SELECT session_id, count(*) FROM turns GROUP BY session_id"))
        # One trajectory event can be reported twice (start and result) under
        # the same tool_call_id, so a call is counted once.
        tools_by_day = dict(
            _rows(
                conn,
                "SELECT substr(created_at, 1, 10) d, count(DISTINCT coalesce(tool_call_id, 'e' || id)) FROM forge_trajectory_events GROUP BY d",
            )
        )
        file_count = next(iter(_rows(conn, "SELECT count(*) FROM session_files")), (0,))[0]
    finally:
        conn.close()

    hour_counts = {h: c for h, c in turns_by_hour if isinstance(h, str) and h.isdigit()}

    sessions_by_day = {}
    repos = {}
    longest = {"duration": 0, "messageCount": 0}
    first_date = ""
    total_messages = 0
    for sid, repository, created_at, updated_at in sessions:
        date = created_at[0:10] if isinstance(created_at, str) else ""
        if date:
            sessions_by_day[date] = sessions_by_day.get(date, 0) + 1
            if first_date == "" or date < first_date:
                first_date = date
        if isinstance(repository, str) and repository != "":
            repos[repository] = repos.get(repository, 0) + 1

        messages = turns_by_session.get(sid, 0)
        total_messages += messages
        ms = max(0, _iso_secs(updated_at) - _iso_secs(created_at)) * 1000
        if ms > longest["duration"]:
            longest = {"duration": ms, "messageCount": messages}

    daily = [
        {
            "date": date,
            "sessionCount": sessions_by_day.get(date, 0),
            "messageCount": turns_by_day.get(date, 0),
            "toolCallCount": tools_by_day.get(date, 0),
        }
        for date in sorted(set(sessions_by_day) | set(turns_by_day) | set(tools_by_day))
    ]

    top_repos = sorted(repos.items(), key=lambda kv: (-kv[1], kv[0]))[:5]

    return {
        "version": 1,
        "source": "copilot-session-store",
        "lastComputedDate": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "totalSessions": len(sessions),
        "totalMessages": total_messages,
        "totalToolCalls": sum(tools_by_day.values()),
        "totalFiles": file_count or 0,
        "firstSessionDate": first_date,
        "dailyActivity": daily,
        "longestSession": longest,
        "hourCounts": hour_counts,
        "totalRepositories": len(repos),
        "topRepositories": [{"name": name, "sessions": count} for name, count in top_repos],
    }
