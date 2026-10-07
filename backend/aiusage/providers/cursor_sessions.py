"""Read Cursor Agent chat metadata without opening its private databases."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

_MAX_SESSIONS = 60


@dataclass(frozen=True)
class CursorSession:
    session_id: str
    title: str
    project: str
    last_activity: int


def _root() -> Path:
    return Path(os.environ.get("CURSOR_CHATS_DIR") or os.path.expanduser("~/.cursor/chats"))


def _read(path: Path) -> CursorSession | None:
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("hasConversation") is not True:
        return None
    session_id = path.parent.name
    title = data.get("title") or "Cursor"
    cwd = data.get("cwd") or ""
    if not isinstance(title, str) or not isinstance(cwd, str) or not session_id:
        return None
    try:
        updated = int(float(data.get("updatedAtMs") or 0) / 1000)
        created = int(float(data.get("createdAtMs") or 0) / 1000)
        activity = max(updated, created, int(path.stat().st_mtime))
    except (OSError, TypeError, ValueError, OverflowError):
        return None
    if activity <= 0:
        return None
    project = cwd.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
    return CursorSession(session_id, title.strip() or "Cursor", project, activity)


def _discover(*, include_all=False) -> list[CursorSession]:
    try:
        paths = list(_root().glob("*/*/meta.json"))
    except OSError:
        return []
    records = [record for path in paths if (record := _read(path)) is not None]
    records.sort(key=lambda record: (-record.last_activity, record.session_id))
    return records if include_all else records[:_MAX_SESSIONS]


def read_recent_sessions(*, include_all=False) -> list[CursorSession]:
    return _discover(include_all=include_all)


def session_records() -> list[tuple[str, int, int]]:
    try:
        paths = list(_root().glob("*/*/meta.json"))
    except OSError:
        return []
    records = []
    for path in paths:
        try:
            stat = path.stat()
        except OSError:
            continue
        records.append((str(path), stat.st_mtime_ns, stat.st_size))
    return records
