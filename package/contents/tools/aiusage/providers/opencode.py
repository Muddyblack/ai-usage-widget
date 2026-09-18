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

from .. import billing, paths

_MAX_ROWS = 60
_QUERY_TIMEOUT_SECONDS = 2.0
_REQUIRED_COLUMNS = {"id", "title", "directory", "time_created", "time_updated"}
_MESSAGE_COLUMNS = {"id", "session_id", "data"}
_V2_MESSAGE_COLUMNS = {"id", "session_id", "type", "seq", "data"}
_PART_COLUMNS = {"id", "message_id", "data"}
_MAX_USAGE_ROWS = 240
SQLiteValue = str | int | float | None


@dataclass(frozen=True, slots=True)
class OpenCodeSession:
    session_id: str
    title: str
    directory: str
    created_at: int
    last_activity: int
    database_path: str
    usage: tuple[billing.UsageBucket, ...] = ()


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


def _table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in connection.execute(f"PRAGMA table_info({table})").fetchall() if len(row) > 1}


def _usage_schema(connection: sqlite3.Connection) -> tuple[bool, bool, bool]:
    message = _table_columns(connection, "message")
    v2_message = _table_columns(connection, "session_message")
    part = _table_columns(connection, "part")
    return _MESSAGE_COLUMNS <= message, _V2_MESSAGE_COLUMNS <= v2_message, _PART_COLUMNS <= part


def _seconds(value: SQLiteValue) -> int:
    if type(value) not in (int, float) or not math.isfinite(value):
        return 0
    number = float(value)
    if number >= 100_000_000_000:
        number /= 1000
    return int(number)


def _text(value: SQLiteValue) -> str:
    return value if type(value) is str else ""


def _finite(value: SQLiteValue) -> float | None:
    if type(value) not in (int, float):
        return None
    try:
        number = float(value)
    except (OverflowError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _nonnegative(value: SQLiteValue) -> float:
    number = _finite(value)
    return number if number is not None and number >= 0 else 0


def _bucket(row, session_id: str) -> billing.UsageBucket | None:
    event_id = _text(row[0])
    message_id = _text(row[1])
    if not event_id or not message_id:
        return None
    provider_cost = _finite(row[3])
    if provider_cost is not None and provider_cost < 0:
        provider_cost = None
    input_tokens = _nonnegative(row[4])
    output_tokens = _nonnegative(row[5])
    cache_read_tokens = _nonnegative(row[6])
    cache_write_tokens = _nonnegative(row[7])
    reasoning_tokens = _nonnegative(row[8])
    token_counts = (input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens)
    if provider_cost == 0 and sum(token_counts) > 0:
        provider_cost = None
    if sum(token_counts) <= 0 and provider_cost is None:
        return None
    return billing.UsageBucket(
        "opencode",
        _text(row[2]),
        session_id,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_read_tokens=cache_read_tokens,
        cache_write_tokens=cache_write_tokens,
        reasoning_tokens=reasoning_tokens,
        provider_cost_usd=provider_cost,
    )


_V1_MESSAGE_QUERY = (
    "SELECT id, id, json_extract(data, '$.modelID'), json_extract(data, '$.cost'), "
    "json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'), "
    "json_extract(data, '$.tokens.cache.read'), json_extract(data, '$.tokens.cache.write'), "
    "json_extract(data, '$.tokens.reasoning') FROM message WHERE session_id = ? "
    "AND json_valid(data) AND json_extract(data, '$.role') = 'assistant' ORDER BY id LIMIT ?"
)
_V2_MESSAGE_QUERY = (
    "SELECT id, id, json_extract(data, '$.model.id'), json_extract(data, '$.cost'), "
    "json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'), "
    "json_extract(data, '$.tokens.cache.read'), json_extract(data, '$.tokens.cache.write'), "
    "json_extract(data, '$.tokens.reasoning') FROM session_message WHERE session_id = ? "
    "AND type = 'assistant' AND json_valid(data) ORDER BY seq, id LIMIT ?"
)
_V1_PART_QUERY = (
    "SELECT p.id, m.id, json_extract(m.data, '$.modelID'), json_extract(p.data, '$.cost'), "
    "json_extract(p.data, '$.tokens.input'), json_extract(p.data, '$.tokens.output'), "
    "json_extract(p.data, '$.tokens.cache.read'), json_extract(p.data, '$.tokens.cache.write'), "
    "json_extract(p.data, '$.tokens.reasoning') FROM part AS p JOIN message AS m ON m.id = p.message_id "
    "WHERE m.session_id = ? AND json_valid(m.data) AND json_valid(p.data) "
    "AND json_extract(m.data, '$.role') = 'assistant' AND json_extract(p.data, '$.type') = 'step-finish' "
    "ORDER BY p.id LIMIT ?"
)


def _read_usage(
    connection: sqlite3.Connection,
    session_id: str,
    deadline: float,
) -> tuple[billing.UsageBucket, ...]:
    v1_message, v2_message, v1_part = _usage_schema(connection)
    if not (v1_message or v2_message):
        return ()

    def query(sql: str) -> list:
        if time.monotonic() >= deadline:
            return []
        try:
            return connection.execute(sql, (session_id, _MAX_USAGE_ROWS)).fetchall()
        except sqlite3.Error:
            return []

    connection.set_progress_handler(lambda: int(time.monotonic() >= deadline), 1000)
    try:
        message_rows = query(_V2_MESSAGE_QUERY) if v2_message else []
        v2_buckets = []
        seen_messages = set()
        for row in message_rows:
            bucket = _bucket(row, session_id)
            if bucket is not None and row[1] not in seen_messages:
                seen_messages.add(row[1])
                v2_buckets.append((row[1], bucket))
        if v2_buckets:
            return tuple(bucket for _, bucket in v2_buckets)
        message_rows = query(_V1_MESSAGE_QUERY) if v1_message else []
        part_rows = query(_V1_PART_QUERY) if v1_part and v1_message else []
    finally:
        connection.set_progress_handler(None, 0)

    message_buckets = []
    seen_messages = set()
    for row in message_rows:
        bucket = _bucket(row, session_id)
        if bucket is not None and row[1] not in seen_messages:
            seen_messages.add(row[1])
            message_buckets.append((row[1], bucket))

    part_buckets = []
    part_message_ids = set()
    seen_parts = set()
    for row in part_rows:
        bucket = _bucket(row, session_id)
        if bucket is not None and row[0] not in seen_parts:
            seen_parts.add(row[0])
            part_message_ids.add(row[1])
            part_buckets.append(bucket)

    return tuple(bucket for message_id, bucket in message_buckets if message_id not in part_message_ids) + tuple(part_buckets)


def _read_database(database_path: str) -> list[OpenCodeSession]:
    try:
        with _connect_readonly(database_path) as connection:
            if not _schema_is_supported(connection):
                return []
            deadline = time.monotonic() + _QUERY_TIMEOUT_SECONDS

            def interrupt_query() -> int:
                return int(time.monotonic() >= deadline)

            connection.set_progress_handler(interrupt_query, 1000)
            try:
                rows = connection.execute(
                    "SELECT id, title, directory, time_created, time_updated FROM session ORDER BY time_updated DESC LIMIT ?",
                    (_MAX_ROWS,),
                ).fetchall()
            finally:
                connection.set_progress_handler(None, 0)
            usage_by_session = {}
            for row in rows:
                session_id = _text(row[0])
                if session_id:
                    usage_by_session[session_id] = _read_usage(connection, session_id, deadline)
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
                usage=usage_by_session.get(session_id, ()),
            )
        )
    return records


def read_recent_sessions() -> list[OpenCodeSession]:
    records: list[OpenCodeSession] = []
    for database_path in discover_database_paths():
        records.extend(_read_database(database_path))
    return records


def read_session_targets() -> list[OpenCodeSession]:
    return read_recent_sessions()
