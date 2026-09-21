"""Persistent cache boundary for the merged session listing."""

from __future__ import annotations

import sqlite3
import time
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

from . import config
from .session_index import (
    SessionIndex,
    SessionQueryResult,
    SessionRow,
    SessionSource,
    SkipSource,
    redact_rows,
)
from .session_manifest import build_manifests

CollectorBatch = tuple[list[Mapping[str, str | int]], bool]
Collector = Callable[[], CollectorBatch]
# Rows for one named source; raising means "keep what the index already has".
SourceCollector = Callable[[str], Sequence[Mapping[str, str | int]]]


class IncompleteRefresh(Exception):
    """Carry the direct result when one collector could not refresh."""

    def __init__(self, rows: list[Mapping[str, str | int]]) -> None:
        super().__init__("session collector refresh was incomplete")
        self.rows = rows


class SessionCache:
    """Refresh and query one persistent merged redacted session listing."""

    def __init__(self) -> None:
        self._index = SessionIndex(Path(config.cache_dir()) / "sessions.sqlite3")

    def query(
        self,
        query: str = "",
        limit: int | None = None,
        offset: int = 0,
        source_ids: Sequence[str] | None = None,
    ) -> SessionQueryResult:
        """Return a page from the existing index without scanning session stores."""
        page_limit = 60 if limit is None else limit
        try:
            return self._index.query(
                query,
                limit=page_limit,
                offset=offset,
                source_ids=source_ids,
            )
        except (OSError, sqlite3.Error):
            return {
                "updatedAt": int(time.time()),
                "sessions": [],
                "total": 0,
                "totalExact": True,
                "offset": offset,
                "limit": page_limit,
                "hasMore": False,
                "sources": [],
            }

    def rows(self) -> list[SessionRow]:
        """Every indexed row, unpaged — spend rollups must never sum a page."""
        try:
            return self._index.rows()
        except (OSError, sqlite3.Error):
            return []

    def refresh(self, collect: Collector, collect_source: SourceCollector | None = None) -> list[SessionRow] | None:
        """Reconcile the index per source, returning direct rows only when the
        index itself cannot be used.

        Each collector is fingerprinted on its own, so a poll re-parses only the
        stores that actually changed. A collector that raises keeps its previous
        rows instead of blanking them.
        """
        if collect_source is None:
            return self._refresh_all(collect)

        def parse(source: SessionSource) -> Sequence[Mapping[str, str | int]]:
            try:
                return collect_source(source.source_id)
            except Exception:
                raise SkipSource(source.source_id) from None

        try:
            self._index.reconcile(build_manifests(), parse)
        except (OSError, sqlite3.Error):
            return self._direct(collect)
        return None

    def _refresh_all(self, collect: Collector) -> list[SessionRow] | None:
        """Single-source fallback for callers with no per-source collector."""
        scanned: list[Mapping[str, str | int]] = []

        def parse(_source: SessionSource) -> Sequence[Mapping[str, str | int]]:
            rows, complete = collect()
            scanned[:] = rows
            if not complete:
                raise IncompleteRefresh(rows)
            return rows

        try:
            self._index.reconcile(build_manifests(), parse)
        except IncompleteRefresh as error:
            return redact_rows(error.rows)
        except (OSError, sqlite3.Error):
            if scanned:
                return redact_rows(scanned)
            return self._direct(collect)
        return None

    def _direct(self, collect: Collector) -> list[SessionRow]:
        """The index is unusable, so querying it would show an empty tab."""
        rows, _complete = collect()
        return redact_rows(rows)
