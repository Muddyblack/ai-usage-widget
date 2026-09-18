"""Persistent, redacted SQLite index for local agent sessions."""

from __future__ import annotations

import hashlib
import sqlite3
import time
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Callable, Final, Protocol, TypedDict

_SEARCH_COLUMNS: Final = ("provider", "title", "session_name", "state", "detail")
SOURCE_REGISTRY: Final = (
    ("cline", "Cline"),
    ("muse", "Muse"),
    ("openai", "Codex"),
    ("grok", "Grok"),
    ("claude", "Claude Code"),
    ("opencode", "OpenCode"),
    ("antigravity", "Antigravity"),
)


class SessionSource(Protocol):
    source_id: str
    mtime_ns: int
    size: int


class SessionRow(TypedDict):
    provider: str
    title: str
    sessionName: str
    state: str
    lastActivityAt: int
    detail: str
    openKey: str


class SessionSourceDescriptor(TypedDict):
    id: str
    label: str


class SessionQueryResult(TypedDict):
    updatedAt: int
    sessions: list[SessionRow]
    total: int
    totalExact: bool
    offset: int
    limit: int
    hasMore: bool
    sources: list[SessionSourceDescriptor]


SessionParser = Callable[[SessionSource], Sequence[Mapping[str, str | int]]]


def _source_key(source: SessionSource) -> str:
    return hashlib.sha256(source.source_id.encode("utf-8")).hexdigest()


def _text(value: str | int) -> str:
    return value if isinstance(value, str) else str(value)


def _timestamp(value: str | int) -> int:
    return value if isinstance(value, int) else int(value)


def _redact(rows: Sequence[Mapping[str, str | int]]) -> list[SessionRow]:
    redacted: list[SessionRow] = []
    for row in rows:
        redacted.append(
            {
                "provider": _text(row.get("provider", "")),
                "title": _text(row.get("title", "")),
                "sessionName": _text(row.get("sessionName", "")),
                "state": _text(row.get("state", "")),
                "lastActivityAt": _timestamp(row.get("lastActivityAt", 0)),
                "detail": _text(row.get("detail", "")),
                "openKey": _valid_open_key(row.get("openKey", "")),
            }
        )
    return redacted


def redact_rows(rows: Sequence[Mapping[str, str | int]]) -> list[SessionRow]:
    """Return only the public fields allowed in a session response."""
    return _redact(rows)


def normalize_source_ids(source_ids: Sequence[str] | None) -> tuple[str, ...] | None:
    """Normalize selected source IDs while preserving an explicit filter."""
    if source_ids is None or not source_ids:
        return None
    return tuple(dict.fromkeys(source_id.strip() for source_id in source_ids))


def source_descriptors(providers: Iterable[str]) -> list[SessionSourceDescriptor]:
    """Return canonical, public descriptors for cached provider rows."""
    available = frozenset(providers)
    return [{"id": source_id, "label": label} for source_id, label in SOURCE_REGISTRY if source_id in available]


def _valid_open_key(value: object) -> str:
    return value if isinstance(value, str) and len(value) == 64 and all(char in "0123456789abcdef" for char in value) else ""


class SessionIndex:
    """Keep redacted session rows keyed by a private source fingerprint."""

    def __init__(self, cache_path: str | Path) -> None:
        self._cache_path = Path(cache_path)
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)

    def _open(self) -> sqlite3.Connection:
        from .session_index_storage import open_index

        return open_index(self._cache_path)

    def reconcile(
        self,
        sources: Iterable[SessionSource],
        parser: SessionParser,
        *,
        force: bool = False,
    ) -> None:
        """Refresh changed sources and remove sources absent from the scan."""
        source_map = {_source_key(source): source for source in sources}
        connection = self._open()
        try:
            with connection:
                connection.execute("BEGIN IMMEDIATE")
                stored = {str(row[0]): (int(row[1]), int(row[2])) for row in connection.execute("SELECT source_key, mtime_ns, size FROM source_meta")}
                stored_orders = {str(row[0]): int(row[1]) for row in connection.execute("SELECT source_key, source_order FROM source_meta")}
                mutated = False
                for key in stored:
                    if key not in source_map:
                        mutated = True
                        connection.execute("DELETE FROM session_rows WHERE source_key = ?", (key,))
                        connection.execute("DELETE FROM source_meta WHERE source_key = ?", (key,))

                for source_order, (key, source) in enumerate(source_map.items()):
                    metadata = (source.mtime_ns, source.size)
                    if not force and stored.get(key) == metadata:
                        if key in stored_orders and stored_orders[key] != source_order:
                            mutated = True
                        connection.execute(
                            "UPDATE source_meta SET source_order = ? WHERE source_key = ?",
                            (source_order, key),
                        )
                        continue
                    mutated = True
                    rows = _redact(parser(source))
                    connection.execute(
                        "INSERT INTO source_meta (source_key, mtime_ns, size, source_order) "
                        "VALUES (?, ?, ?, ?) ON CONFLICT(source_key) DO UPDATE SET "
                        "mtime_ns = excluded.mtime_ns, size = excluded.size, "
                        "source_order = excluded.source_order",
                        (key, source.mtime_ns, source.size, source_order),
                    )
                    connection.execute("DELETE FROM session_rows WHERE source_key = ?", (key,))
                    connection.executemany(
                        "INSERT INTO session_rows (source_key, row_order, provider, "
                        "title, session_name, state, last_activity_at, detail, "
                        "open_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            (
                                key,
                                row_order,
                                row["provider"],
                                row["title"],
                                row["sessionName"],
                                row["state"],
                                row["lastActivityAt"],
                                row["detail"],
                                row["openKey"],
                            )
                            for row_order, row in enumerate(rows)
                        ),
                    )
                connection.commit()
            if mutated:
                try:
                    connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
                except sqlite3.DatabaseError:
                    pass
        finally:
            connection.close()

    def rows(self) -> list[SessionRow]:
        """Return the cached merged rows in their original collector order."""
        connection = self._open()
        try:
            page = connection.execute(
                "SELECT provider, title, session_name, state, last_activity_at, "
                "detail, open_key FROM session_rows "
                "ORDER BY (SELECT source_order FROM source_meta "
                "WHERE source_key = session_rows.source_key), row_order"
            ).fetchall()
        finally:
            connection.close()
        return [
            {
                "provider": _text(row[0]),
                "title": _text(row[1]),
                "sessionName": _text(row[2]),
                "state": _text(row[3]),
                "lastActivityAt": _timestamp(row[4]),
                "detail": _text(row[5]),
                "openKey": _valid_open_key(row[6]),
            }
            for row in page
        ]

    def query(
        self,
        query: str = "",
        limit: int = 60,
        offset: int = 0,
        source_ids: Sequence[str] | None = None,
    ) -> SessionQueryResult:
        """Return a literal, case-insensitive substring page of public rows."""
        needle = query.strip().casefold()
        normalized_source_ids = normalize_source_ids(source_ids)
        connection = self._open()
        try:
            available_providers = [str(row[0]) for row in connection.execute("SELECT DISTINCT provider FROM session_rows").fetchall()]
            predicates: list[str] = []
            parameters: list[str] = []
            if needle:
                predicates.append("(" + " OR ".join(f"instr(casefold({column}), ?) > 0" for column in _SEARCH_COLUMNS) + ")")
                parameters.extend((needle,) * len(_SEARCH_COLUMNS))
            if normalized_source_ids is not None:
                predicates.append("(" + " OR ".join("provider = ?" for _ in normalized_source_ids) + ")")
                parameters.extend(normalized_source_ids)
            where = " WHERE " + " AND ".join(predicates) if predicates else ""
            total = int(
                connection.execute(
                    "SELECT COUNT(*) FROM session_rows" + where,
                    tuple(parameters),
                ).fetchone()[0]
            )
            page = connection.execute(
                "SELECT provider, title, session_name, state, last_activity_at, detail, open_key "
                "FROM session_rows" + where + " ORDER BY last_activity_at DESC, "
                "(SELECT source_order FROM source_meta WHERE source_key = session_rows.source_key) ASC, "
                "row_order ASC" + " LIMIT ? OFFSET ?",
                (*parameters, limit, offset),
            ).fetchall()
            sessions: list[SessionRow] = [
                {
                    "provider": _text(row[0]),
                    "title": _text(row[1]),
                    "sessionName": _text(row[2]),
                    "state": _text(row[3]),
                    "lastActivityAt": _timestamp(row[4]),
                    "detail": _text(row[5]),
                    "openKey": _valid_open_key(row[6]),
                }
                for row in page
            ]
        finally:
            connection.close()
        return {
            "updatedAt": int(time.time()),
            "sessions": sessions,
            "total": total,
            "totalExact": True,
            "offset": offset,
            "limit": limit,
            "hasMore": offset + limit < total,
            "sources": source_descriptors(available_providers),
        }
