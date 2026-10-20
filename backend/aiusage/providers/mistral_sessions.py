"""Read Mistral Vibe session metadata without writing to it."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

from ..contract import epoch_of, finite_number
from ..messages import tr

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
    title = data.get("title") or tr("Mistral Vibe")
    if not isinstance(title, str):
        title = tr("Mistral Vibe")
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


def _load_json(path: Path):
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            return json.load(stream)
    except (OSError, ValueError):
        return None


def _unified_state_path(directory: Path) -> Path | None:
    """Locate the newest projection-state.json of a unified (Vibe 2.x) session."""
    current = _load_json(directory / "CURRENT")
    generation = current.get("generation") if isinstance(current, dict) else None
    if isinstance(generation, str) and generation:
        candidate = directory / "generations" / generation / "projection-state.json"
        if candidate.is_file():
            return candidate
    try:
        candidates = sorted((directory / "generations").glob("*/projection-state.json"))
    except OSError:
        return None
    return candidates[-1] if candidates else None


def _unified_session(meta_path: Path) -> dict | None:
    """Return the public session snapshot of a unified-store session."""
    state_path = _unified_state_path(meta_path.parent)
    state = _load_json(state_path) if state_path else None
    snapshot = state.get("snapshot") if isinstance(state, dict) else None
    session = snapshot.get("session") if isinstance(snapshot, dict) else None
    return session if isinstance(session, dict) else None


def _read_unified(meta_path: Path) -> MistralSession | None:
    data = _load_json(meta_path)
    session = _unified_session(meta_path)
    if not isinstance(data, dict) or session is None:
        return None
    session_id = data.get("session_id") or meta_path.parent.name
    if not isinstance(session_id, str) or not session_id:
        return None
    usage = session.get("tokenUsage") if isinstance(session.get("tokenUsage"), dict) else {}
    title = data.get("title") or session.get("title") or session.get("preview") or ""
    if not isinstance(title, str):
        title = ""
    environment = data.get("environment") if isinstance(data.get("environment"), dict) else {}
    project = environment.get("working_directory") or data.get("origin_directory") or ""
    if not isinstance(project, str):
        project = ""
    project = project.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
    config = data.get("config") if isinstance(data.get("config"), dict) else {}
    model = config.get("active_model") or ""
    if not isinstance(model, str):
        model = ""
    updated = _number(session.get("updatedAt")) / 1000
    try:
        mtime = int(meta_path.stat().st_mtime)
    except OSError:
        mtime = 0
    activity = max(epoch_of(data.get("start_time")), epoch_of(data.get("end_time")), int(updated), mtime)
    if activity <= 0:
        return None
    return MistralSession(
        session_id,
        title.strip() or tr("Mistral Vibe"),
        project,
        model,
        activity,
        int(_number(usage.get("inputTokens"))),
        int(_number(usage.get("outputTokens"))),
        int(_number(usage.get("cachedInputTokens"))),
        None,
    )


def _meta_paths(root: Path) -> tuple[list[Path], list[Path]]:
    try:
        return list(root.glob("*/meta.json")), list(root.glob("unified/*/meta.json"))
    except OSError:
        return [], []


def unified_documents() -> list[dict]:
    """Unified-store sessions shaped like legacy meta.json documents."""
    _legacy, unified = _meta_paths(_root() / "logs" / "session")
    documents = []
    for path in unified:
        data = _load_json(path)
        session = _unified_session(path)
        if not isinstance(data, dict) or session is None:
            continue
        usage = session.get("tokenUsage") if isinstance(session.get("tokenUsage"), dict) else {}
        prompt = int(_number(usage.get("inputTokens")))
        completion = int(_number(usage.get("outputTokens")))
        documents.append(
            {
                "title": data.get("title") or session.get("title") or session.get("preview"),
                "start_time": data.get("start_time"),
                "git_branch": data.get("git_branch"),
                "environment": data.get("environment"),
                "stats": {
                    "session_cost": 0,
                    "session_prompt_tokens": prompt,
                    "session_completion_tokens": completion,
                    "session_total_llm_tokens": int(_number(usage.get("totalTokens"))) or prompt + completion,
                },
            }
        )
    return documents


def _discover(*, include_all=False) -> list[MistralSession]:
    legacy, unified = _meta_paths(_root() / "logs" / "session")
    records = [record for path in legacy if (record := _read(path)) is not None]
    records += [record for path in unified if (record := _read_unified(path)) is not None]
    records.sort(key=lambda record: (-record.last_activity, record.session_id))
    return records if include_all else records[:_MAX_SESSIONS]


def read_recent_sessions(*, include_all=False) -> list[MistralSession]:
    return _discover(include_all=include_all)


def read_session_targets() -> list[MistralSession]:
    return _discover(include_all=True)


def session_records() -> list[tuple[str, int, int]]:
    """Return metadata-only records used by the session cache fingerprint."""
    legacy, unified = _meta_paths(_root() / "logs" / "session")
    paths = legacy + unified
    for path in unified:
        state = _unified_state_path(path.parent)
        if state is not None:
            paths.append(state)
    records = []
    for path in paths:
        try:
            stat = path.stat()
        except OSError:
            continue
        records.append((str(path), stat.st_mtime_ns, stat.st_size))
    return records
