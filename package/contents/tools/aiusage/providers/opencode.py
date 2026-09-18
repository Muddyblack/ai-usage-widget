from __future__ import annotations

import math
import os
import shutil
import sqlite3
import subprocess
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from .. import paths

_MAX_ROWS = 60
_QUERY_TIMEOUT_SECONDS = 2.0
_REQUIRED_COLUMNS = {"id", "title", "directory", "time_created", "time_updated"}


@dataclass(frozen=True)
class OpenCodeSession:
    session_id: str
    title: str
    directory: str
    created_at: int
    last_activity: int
    database_path: str


def _existing_file(value: str) -> str:
    candidate = Path(value).expanduser()
    return str(candidate) if candidate.is_file() else ""


def _cli_database_path() -> str:
    binary = shutil.which("opencode")
    if not binary:
        return ""
    try:
        result = subprocess.run(
            [binary, "db", "path"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if result.returncode != 0:
        return ""
    output = result.stdout.strip().splitlines()
    return _existing_file(output[-1].strip()) if output else ""


def discover_database_paths() -> list[str]:
    explicit = os.environ.get("OPENCODE_DB", "").strip()
    candidates: list[str] = []
    if explicit:
        path = _existing_file(explicit)
        return [path] if path else []
    cli_path = _cli_database_path()
    if cli_path:
        candidates.append(cli_path)
    for base in paths.data_home_dirs():
        for directory in (Path(base), Path(base) / "opencode"):
            candidates.extend(str(path) for path in sorted(directory.glob("opencode*.db")) if path.is_file())
    return list(dict.fromkeys(candidates))


@contextmanager
def _connect_readonly(database_path: str) -> Iterator[sqlite3.Connection]:
    uri = f"{Path(database_path).resolve().as_uri()}?mode=ro"
    connection = sqlite3.connect(uri, uri=True, timeout=1.0)
    try:
        connection.execute("PRAGMA query_only = ON")
        yield connection
    finally:
        connection.close()


def _schema_is_supported(connection: sqlite3.Connection) -> bool:
    columns = {row[1] for row in connection.execute("PRAGMA table_info(session)").fetchall() if len(row) > 1}
    return _REQUIRED_COLUMNS <= columns


def _seconds(value: object) -> int:
    if type(value) not in (int, float) or not math.isfinite(value):
        return 0
    number = float(value)
    if number >= 100_000_000_000:
        number /= 1000
    return int(number)


def _text(value: object) -> str:
    return value if type(value) is str else ""


def _read_database(database_path: str, *, include_all: bool = False) -> list[OpenCodeSession]:
    try:
        with _connect_readonly(database_path) as connection:
            if not _schema_is_supported(connection):
                return []
            deadline = time.monotonic() + _QUERY_TIMEOUT_SECONDS

            def interrupt_query() -> int:
                return int(time.monotonic() >= deadline)

            connection.set_progress_handler(interrupt_query, 1000)
            try:
                query = "SELECT id, title, directory, time_created, time_updated FROM session ORDER BY time_updated DESC"
                if include_all:
                    rows = connection.execute(query).fetchall()
                else:
                    rows = connection.execute(query + " LIMIT ?", (_MAX_ROWS,)).fetchall()
            finally:
                connection.set_progress_handler(None, 0)
    except (OSError, sqlite3.Error, ValueError):
        return []

    records = []
    for row in rows:
        session_id = _text(row[0])
        directory = _text(row[2])
        if not session_id or not directory:
            continue
        records.append(
            OpenCodeSession(
                session_id=session_id,
                title=_text(row[1]),
                directory=directory,
                created_at=_seconds(row[3]),
                last_activity=_seconds(row[4]),
                database_path=database_path,
            )
        )
    return records


def read_recent_sessions(*, include_all: bool = False) -> list[OpenCodeSession]:
    records: list[OpenCodeSession] = []
    for database_path in discover_database_paths():
        records.extend(_read_database(database_path, include_all=include_all))
    return records


def read_session_targets(*, include_all: bool = True) -> list[OpenCodeSession]:
    return read_recent_sessions(include_all=include_all)
