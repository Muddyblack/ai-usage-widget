from __future__ import annotations

import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from .. import billing, paths
from ..contract import finite_number

_MAX_ROWS = 60
_QUERY_TIMEOUT_SECONDS = 2.0
_READ_TIMEOUT_SECONDS = 30.0
_REQUIRED_COLUMNS = {"id", "title", "directory", "time_created", "time_updated"}
_MESSAGE_COLUMNS = {"id", "session_id", "data"}
_V2_MESSAGE_COLUMNS = {"id", "session_id", "type", "seq", "data"}
_PART_COLUMNS = {"id", "message_id", "data"}
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


def _provider_id(value: SQLiteValue) -> str:
    provider = _text(value).strip().lower()
    if not provider or len(provider) > 64 or not re.fullmatch(r"[a-z0-9._-]+", provider):
        return ""
    return provider


def _finite(value: SQLiteValue) -> float | None:
    return finite_number(value)


def _nonnegative(value: SQLiteValue) -> float:
    number = finite_number(value, minimum=0)
    return number if number is not None else 0


def _aggregate_bucket(row, session_id: str) -> billing.UsageBucket | None:
    provider = _provider_id(row[0])
    model = _text(row[1])
    if not provider or not model:
        return None
    provider_cost = _finite(row[2])
    if provider_cost is not None and provider_cost < 0:
        provider_cost = None
    input_tokens = _nonnegative(row[3])
    output_tokens = _nonnegative(row[4])
    cache_read_tokens = _nonnegative(row[5])
    cache_write_tokens = _nonnegative(row[6])
    reasoning_tokens = _nonnegative(row[7])
    token_counts = (input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens)
    if provider_cost == 0 and sum(token_counts) > 0:
        provider_cost = None
    if sum(token_counts) <= 0 and provider_cost is None:
        return None
    return billing.UsageBucket(
        provider,
        model,
        session_id,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_read_tokens=cache_read_tokens,
        cache_write_tokens=cache_write_tokens,
        reasoning_tokens=reasoning_tokens,
        provider_cost_usd=provider_cost,
        source="opencode",
    )


def _sum_nonnegative(alias: str, path: str) -> str:
    """SQL fragment: SUM of finite non-negative numbers at `path`, else 0."""
    return (
        f"SUM(CASE WHEN json_type(json_extract({alias}, '{path}')) IN ('integer', 'real') "
        f"AND json_extract({alias}, '{path}') >= 0 "
        f"AND json_extract({alias}, '{path}') <= {sys.float_info.max} "
        f"THEN json_extract({alias}, '{path}') ELSE 0 END)"
    )


def _bucket_condition(alias: str) -> str:
    """SQL fragment: rows that would produce a usage bucket (valid cost or positive tokens)."""
    cost = (
        f"json_type(json_extract({alias}, '$.cost')) IN ('integer', 'real') "
        f"AND json_extract({alias}, '$.cost') >= 0 "
        f"AND json_extract({alias}, '$.cost') <= {sys.float_info.max}"
    )
    tokens = " OR ".join(
        f"(json_type(json_extract({alias}, '$.tokens.{path}')) IN ('integer', 'real') "
        f"AND json_extract({alias}, '$.tokens.{path}') > 0 "
        f"AND json_extract({alias}, '$.tokens.{path}') <= {sys.float_info.max})"
        for path in ("input", "output", "cache.read", "cache.write", "reasoning")
    )
    return f"({cost} OR {tokens})"


def _v1_message_query(include_parts: bool) -> str:
    """V1 assistant-message usage, aggregated per (provider, model).

    Messages whose step-finish part would produce its own bucket are excluded
    only when the part table exists; without it every message is its own
    bucket, matching the pre-aggregation reader.
    """
    dedup = ""
    if include_parts:
        dedup = (
            "  AND NOT EXISTS (\n"
            "      SELECT 1 FROM part AS p\n"
            "      WHERE p.message_id = m.id AND json_valid(p.data)\n"
            "        AND json_extract(p.data, '$.type') = 'step-finish'\n"
            f"        AND {_bucket_condition('p.data')}\n"
            "  )"
        )
    return f"""
SELECT json_extract(m.data, '$.providerID'), json_extract(m.data, '$.modelID'),
       {_sum_nonnegative("m.data", "$.cost")},
       {_sum_nonnegative("m.data", "$.tokens.input")},
       {_sum_nonnegative("m.data", "$.tokens.output")},
       {_sum_nonnegative("m.data", "$.tokens.cache.read")},
       {_sum_nonnegative("m.data", "$.tokens.cache.write")},
       {_sum_nonnegative("m.data", "$.tokens.reasoning")}
FROM message AS m
WHERE m.session_id = ? AND json_valid(m.data) AND json_extract(m.data, '$.role') = 'assistant'
  AND {_bucket_condition("m.data")}{dedup}
GROUP BY json_extract(m.data, '$.providerID'), json_extract(m.data, '$.modelID')
ORDER BY MIN(m.id)
"""


_V2_MESSAGE_QUERY = f"""
SELECT json_extract(data, '$.model.providerID'), json_extract(data, '$.model.id'),
       {_sum_nonnegative("data", "$.cost")},
       {_sum_nonnegative("data", "$.tokens.input")},
       {_sum_nonnegative("data", "$.tokens.output")},
       {_sum_nonnegative("data", "$.tokens.cache.read")},
       {_sum_nonnegative("data", "$.tokens.cache.write")},
       {_sum_nonnegative("data", "$.tokens.reasoning")}
FROM session_message
WHERE session_id = ? AND type = 'assistant' AND json_valid(data) AND {_bucket_condition("data")}
GROUP BY json_extract(data, '$.model.providerID'), json_extract(data, '$.model.id')
ORDER BY MIN(seq)
"""
_V1_PART_QUERY = f"""
SELECT json_extract(m.data, '$.providerID'), json_extract(m.data, '$.modelID'),
       {_sum_nonnegative("p.data", "$.cost")},
       {_sum_nonnegative("p.data", "$.tokens.input")},
       {_sum_nonnegative("p.data", "$.tokens.output")},
       {_sum_nonnegative("p.data", "$.tokens.cache.read")},
       {_sum_nonnegative("p.data", "$.tokens.cache.write")},
       {_sum_nonnegative("p.data", "$.tokens.reasoning")}
FROM part AS p JOIN message AS m ON m.id = p.message_id
WHERE m.session_id = ? AND json_valid(m.data) AND json_valid(p.data)
  AND json_extract(m.data, '$.role') = 'assistant'
  AND json_extract(p.data, '$.type') = 'step-finish'
  AND {_bucket_condition("p.data")}
GROUP BY json_extract(m.data, '$.providerID'), json_extract(m.data, '$.modelID')
ORDER BY MIN(p.id)
"""


def _read_usage(
    connection: sqlite3.Connection,
    session_id: str,
) -> tuple[billing.UsageBucket, ...]:
    v1_message, v2_message, v1_part = _usage_schema(connection)
    if not (v1_message or v2_message):
        return ()
    deadline = time.monotonic() + _QUERY_TIMEOUT_SECONDS

    def query(sql: str) -> tuple[bool, list]:
        if time.monotonic() >= deadline:
            return False, []
        try:
            return True, connection.execute(sql, (session_id,)).fetchall()
        except sqlite3.Error:
            return False, []

    connection.set_progress_handler(lambda: int(time.monotonic() >= deadline), 1000)
    try:
        v2_ok, v2_rows = query(_V2_MESSAGE_QUERY) if v2_message else (True, [])
        if not v2_ok:
            return ()
        v2_buckets = tuple(bucket for bucket in (_aggregate_bucket(row, session_id) for row in v2_rows) if bucket is not None)
        if v2_buckets:
            return v2_buckets
        v1_ok, message_rows = query(_v1_message_query(v1_part)) if v1_message else (True, [])
        part_ok, part_rows = query(_V1_PART_QUERY) if v1_part and v1_message else (True, [])
        if not v1_ok or not part_ok:
            return ()
    finally:
        connection.set_progress_handler(None, 0)

    message_buckets = tuple(bucket for bucket in (_aggregate_bucket(row, session_id) for row in message_rows) if bucket is not None)
    part_buckets = tuple(bucket for bucket in (_aggregate_bucket(row, session_id) for row in part_rows) if bucket is not None)
    return message_buckets + part_buckets


def _read_database(database_path: str, *, include_all: bool = False) -> list[OpenCodeSession]:
    try:
        with _connect_readonly(database_path) as connection:
            if not _schema_is_supported(connection):
                return []
            overall_deadline = time.monotonic() + _READ_TIMEOUT_SECONDS

            def interrupt_query() -> int:
                return int(time.monotonic() >= overall_deadline)

            connection.set_progress_handler(interrupt_query, 1000)
            try:
                query = "SELECT id, title, directory, time_created, time_updated FROM session ORDER BY time_updated DESC"
                if include_all:
                    rows = connection.execute(query).fetchall()
                else:
                    rows = connection.execute(query + " LIMIT ?", (_MAX_ROWS,)).fetchall()
            finally:
                connection.set_progress_handler(None, 0)
            usage_by_session = {}
            for index, row in enumerate(rows):
                if time.monotonic() >= overall_deadline:
                    rows = rows[:index]
                    break
                session_id = _text(row[0])
                if session_id:
                    usage_by_session[session_id] = _read_usage(connection, session_id)
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


def read_recent_sessions(*, include_all: bool = False) -> list[OpenCodeSession]:
    records: list[OpenCodeSession] = []
    for database_path in discover_database_paths():
        records.extend(_read_database(database_path, include_all=include_all))
    return records


def read_session_targets(*, include_all: bool = True) -> list[OpenCodeSession]:
    return read_recent_sessions(include_all=include_all)
