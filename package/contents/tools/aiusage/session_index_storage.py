"""SQLite connection and schema recovery for the session index."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Final

_BUSY_TIMEOUT_MS: Final = 5_000
_SCHEMA_VERSION: Final = 3


def _is_corrupt(error: sqlite3.DatabaseError) -> bool:
    message = str(error).casefold()
    return any(
        marker in message
        for marker in (
            "not a database",
            "database disk image is malformed",
            "malformed database",
            "unsupported file format",
            "session index schema is invalid",
        )
    )


def _try_wal(connection: sqlite3.Connection) -> str:
    try:
        result = connection.execute("PRAGMA journal_mode=WAL").fetchone()
    except sqlite3.DatabaseError as error:
        if _is_corrupt(error):
            raise
        return "unsupported"
    return str(result[0]) if result else "unsupported"


def _ensure_schema(connection: sqlite3.Connection) -> None:
    connection.execute(f"PRAGMA user_version = {_SCHEMA_VERSION}")
    connection.execute(
        "CREATE TABLE IF NOT EXISTS source_meta (source_key TEXT PRIMARY KEY, "
        "mtime_ns INTEGER NOT NULL, size INTEGER NOT NULL, "
        "source_order INTEGER NOT NULL DEFAULT 0)"
    )
    connection.execute(
        "CREATE TABLE IF NOT EXISTS session_rows (source_key TEXT NOT NULL, "
        "row_order INTEGER NOT NULL, provider TEXT NOT NULL, title TEXT NOT NULL, "
        "session_name TEXT NOT NULL, state TEXT NOT NULL, "
        "last_activity_at INTEGER NOT NULL, detail TEXT NOT NULL, "
        "open_key TEXT NOT NULL DEFAULT '', "
        "full_title TEXT NOT NULL DEFAULT '', "
        "source TEXT NOT NULL DEFAULT '', "
        "cost_usd REAL, "
        "cost_status TEXT NOT NULL DEFAULT 'unavailable', "
        "cost_provenance TEXT, "
        "cost_breakdown TEXT, "
        "billing_provider TEXT NOT NULL DEFAULT '', "
        "provider_costs TEXT, "
        "PRIMARY KEY (source_key, row_order))"
    )
    required = {
        "source_meta": {"source_key", "mtime_ns", "size", "source_order"},
        "session_rows": {
            "source_key",
            "row_order",
            "provider",
            "title",
            "session_name",
            "state",
            "last_activity_at",
            "detail",
            "open_key",
            "full_title",
            "source",
            "cost_usd",
            "cost_status",
            "cost_provenance",
            "cost_breakdown",
            "billing_provider",
            "provider_costs",
        },
    }
    for table, columns in required.items():
        actual = {str(row[1]) for row in connection.execute(f"PRAGMA table_info({table})")}
        if not columns.issubset(actual):
            raise sqlite3.DatabaseError("session index schema is invalid")


def open_index(cache_path: Path) -> sqlite3.Connection:
    """Open a writable index connection, replacing a corrupt database."""
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(str(cache_path), timeout=5.0)
        connection.execute(f"PRAGMA busy_timeout={_BUSY_TIMEOUT_MS}")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.create_function("casefold", 1, str.casefold)
        _try_wal(connection)
        _ensure_schema(connection)
    except sqlite3.DatabaseError as error:
        if connection is not None:
            connection.close()
        if not _is_corrupt(error):
            raise
        for suffix in ("", "-wal", "-shm"):
            try:
                Path(str(cache_path) + suffix).unlink()
            except FileNotFoundError:
                continue
        connection = sqlite3.connect(str(cache_path), timeout=5.0)
        connection.execute(f"PRAGMA busy_timeout={_BUSY_TIMEOUT_MS}")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.create_function("casefold", 1, str.casefold)
        _try_wal(connection)
        _ensure_schema(connection)
    return connection
