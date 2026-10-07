"""Read Mistral Vibe session metadata without writing to it."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

from ..contract import epoch_of, finite_number

_MAX_SESSIONS = 60


@dataclass(frozen=True)
class MistralSession:
    session_id: str
    title: str
    project: str
    model: str
    last_activity: int
    input_tokens: int
    output_tokens: int
    cached_tokens: int
    cost_usd: float | None


def _root() -> Path:
    return Path(os.environ.get("VIBE_HOME") or os.path.expanduser("~/.vibe"))


def _number(value, default=0.0):
    number = finite_number(value, minimum=0)
    return default if number is None else number


def _read(path: Path) -> MistralSession | None:
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            data = json.load(stream)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or not isinstance(data.get("stats"), dict):
        return None

    stats = data["stats"]
    session_id = data.get("session_id") or path.parent.name
    if not isinstance(session_id, str) or not session_id:
        return None
    title = data.get("title") or "Mistral Vibe"
    if not isinstance(title, str):
        title = "Mistral Vibe"
    environment = data.get("environment") if isinstance(data.get("environment"), dict) else {}
    project = environment.get("working_directory") or data.get("origin_directory") or ""
    if not isinstance(project, str):
        project = ""
    project = project.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
    config = data.get("config") if isinstance(data.get("config"), dict) else {}
    model = config.get("active_model") or ""
    if not isinstance(model, str):
        model = ""

    try:
        activity = max(epoch_of(data.get("start_time")), epoch_of(data.get("end_time")), int(path.stat().st_mtime))
    except OSError:
        activity = max(epoch_of(data.get("start_time")), epoch_of(data.get("end_time")))
    if activity <= 0:
        return None
    cost = finite_number(stats.get("session_cost"), minimum=0)
    return MistralSession(
        session_id,
        title.strip() or "Mistral Vibe",
        project,
        model,
        activity,
        int(_number(stats.get("session_prompt_tokens"))),
        int(_number(stats.get("session_completion_tokens"))),
        int(_number(stats.get("session_cached_tokens"))),
        cost,
    )


def _discover(*, include_all=False) -> list[MistralSession]:
    root = _root() / "logs" / "session"
    try:
        paths = list(root.glob("*/meta.json"))
    except OSError:
        return []
    records = [record for path in paths if (record := _read(path)) is not None]
    records.sort(key=lambda record: (-record.last_activity, record.session_id))
    return records if include_all else records[:_MAX_SESSIONS]


def read_recent_sessions(*, include_all=False) -> list[MistralSession]:
    return _discover(include_all=include_all)


def read_session_targets() -> list[MistralSession]:
    return _discover(include_all=True)


def session_records() -> list[tuple[str, int, int]]:
    """Return metadata-only records used by the session cache fingerprint."""
    root = _root() / "logs" / "session"
    try:
        paths = list(root.glob("*/meta.json"))
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
