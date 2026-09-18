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
    redact_rows,
)
from .session_manifest import build_manifest

CollectorBatch = tuple[list[Mapping[str, str | int]], bool]
Collector = Callable[[], CollectorBatch]


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

    def refresh(self, collect: Collector) -> list[SessionRow] | None:
        """Reconcile the index, returning direct rows only for incomplete scans."""
        manifest = build_manifest()

        def parse(_source: SessionSource) -> Sequence[Mapping[str, str | int]]:
            rows, complete = collect()
            if not complete:
                raise IncompleteRefresh(rows)
            return rows

        try:
            self._index.reconcile([manifest], parse, force=True)
        except IncompleteRefresh as error:
            return redact_rows(error.rows)
        except (OSError, sqlite3.Error):
            return None
        return None
