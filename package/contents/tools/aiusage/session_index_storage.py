"""SQLite connection and schema recovery for the session index."""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Final

_BUSY_TIMEOUT_MS: Final = 5_000
# Bump whenever a collector's *output* changes shape or content, not just when
# a column is added: cached rows are the product of the parser that produced
# them, so a parser improvement has to invalidate them. Without this, a better
# title or a newly priced cost never reached a store whose files had not
# happened to change since.
_SCHEMA_VERSION: Final = 5


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


def _discard_stale_rows(connection: sqlite3.Connection) -> None:
    """Drop rows parsed by an older build so every source re-collects once."""
    row = connection.execute("PRAGMA user_version").fetchone()
    stored = int(row[0]) if row else 0
    if stored == _SCHEMA_VERSION:
        return
    connection.execute("DELETE FROM session_rows")
    connection.execute("DELETE FROM source_meta")
    # The DELETEs opened an implicit transaction. Close it before touching
    # user_version: a PRAGMA write inside a transaction does not stick, and
    # leaving one open makes reconcile's BEGIN IMMEDIATE fail.
    connection.commit()
    connection.execute(f"PRAGMA user_version = {_SCHEMA_VERSION}")
    connection.commit()


def _ensure_schema(connection: sqlite3.Connection, *, discard_stale: bool = False) -> None:
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
        "cost_billing TEXT NOT NULL DEFAULT 'api', "
        "PRIMARY KEY (source_key, row_order))"
    )
    connection.execute("CREATE INDEX IF NOT EXISTS idx_session_rows_activity ON session_rows (last_activity_at DESC)")
    connection.execute("CREATE INDEX IF NOT EXISTS idx_session_rows_provider ON session_rows (provider)")
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
            "cost_billing",
        },
    }
    for table, columns in required.items():
        actual = {str(row[1]) for row in connection.execute(f"PRAGMA table_info({table})")}
        if not columns.issubset(actual):
            raise sqlite3.DatabaseError("session index schema is invalid")
    if discard_stale:
        _discard_stale_rows(connection)


def _secure_permissions(cache_path: Path) -> None:
    for suffix in ("", "-wal", "-shm"):
        try:
            os.chmod(str(cache_path) + suffix, 0o600)
        except OSError:
            pass


def open_index(cache_path: Path, *, discard_stale: bool = False) -> sqlite3.Connection:
    """Open a writable index connection, replacing a corrupt database.

    ``discard_stale`` drops rows produced by an older parser. Only a reconcile
    passes it: a read doing the wipe would blank the list and leave it blank
    until the next poll, which is exactly what the user sees on screen.
    """
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(str(cache_path), timeout=5.0)
        _secure_permissions(cache_path)
        connection.execute(f"PRAGMA busy_timeout={_BUSY_TIMEOUT_MS}")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.create_function("casefold", 1, str.casefold)
        _try_wal(connection)
        _secure_permissions(cache_path)
        _ensure_schema(connection, discard_stale=discard_stale)
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
        _secure_permissions(cache_path)
        connection.execute(f"PRAGMA busy_timeout={_BUSY_TIMEOUT_MS}")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.create_function("casefold", 1, str.casefold)
        _try_wal(connection)
        _secure_permissions(cache_path)
        _ensure_schema(connection, discard_stale=discard_stale)
    return connection
