"""Persistent, redacted session-index contract tests.

The proposed internal API is ``SessionIndex(cache_path)`` with
``reconcile(sources, parser)`` and ``query(query, limit, offset)``.  The
implementation must remain behind this seam; CLI and frontend contracts are
not part of this module.
"""

import hashlib
import importlib
import sqlite3
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from unittest import mock

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)


@dataclass(frozen=True, slots=True)
class Source:
    path: str
    source_id: str
    mtime_ns: int
    size: int


Row = dict[str, str | int]
Parser = Callable[[Source], list[Row]]


def _index_class() -> type:
    try:
        module = importlib.import_module("aiusage.session_index")
    except ModuleNotFoundError as error:
        if error.name != "aiusage.session_index":
            raise
        raise AssertionError("the approved SessionIndex implementation is not available yet") from error
    return module.SessionIndex


def _source(root: Path, name: str, source_id: str, version: int = 1) -> Source:
    path = root / name
    content = f"transcript-{source_id}-v{version}"
    path.write_text(content, encoding="utf-8")
    return Source(str(path), source_id, version, len(content))


def _parser(calls: list[str]) -> Parser:
    def parse(source: Source) -> list[Row]:
        calls.append(source.source_id)
        return [
            {
                "provider": "test",
                "title": f"Session {source.source_id}",
                "sessionName": "Fixture",
                "state": "idle",
                "lastActivityAt": source.mtime_ns,
                "detail": f"detail {source.source_id}",
                "openKey": "opaque-key",
            }
        ]

    return parse


def _connection(
    stored: list[tuple[str, int, int]],
    checkpoints: list[str],
    events: list[str],
) -> mock.MagicMock:
    connection = mock.MagicMock(spec=sqlite3.Connection)
    connection.__enter__.return_value = connection

    def execute(statement: str, *parameters) -> list[tuple[str, int, int]]:
        if statement.startswith("SELECT source_key, mtime_ns, size"):
            return stored
        if statement.startswith("PRAGMA wal_checkpoint("):
            checkpoints.append(statement.partition("(")[2][:-1])
            events.append(f"checkpoint:{checkpoints[-1]}")
        return []

    connection.execute.side_effect = execute
    connection.commit.side_effect = lambda: events.append("commit")
    return connection


class SessionIndexTest(unittest.TestCase):
    def test_unchanged_manifest_does_not_run_checkpoint_maintenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = _source(root, "one.jsonl", "one")
            source_key = hashlib.sha256(source.source_id.encode("utf-8")).hexdigest()
            checkpoints: list[str] = []
            events: list[str] = []
            connection = _connection([(source_key, source.mtime_ns, source.size)], checkpoints, events)
            index = _index_class()(root / "sessions.sqlite3")
            with (
                mock.patch.object(index, "_open", return_value=connection),
                mock.patch.object(index, "query", return_value={"sessions": [], "total": 0}) as query,
            ):
                index.reconcile([source], _parser([]))

        self.assertEqual(events, ["commit"])
        self.assertEqual(checkpoints, [])
        query.assert_not_called()

    def test_changed_manifest_runs_passive_checkpoint_after_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = _source(root, "one.jsonl", "one")
            checkpoints: list[str] = []
            events: list[str] = []
            connection = _connection([], checkpoints, events)
            index = _index_class()(root / "sessions.sqlite3")
            calls: list[str] = []
            with (
                mock.patch.object(index, "_open", return_value=connection),
                mock.patch.object(index, "query", return_value={"sessions": [], "total": 0}) as query,
            ):
                index.reconcile([source], _parser(calls))

        self.assertEqual(calls, ["one"])
        self.assertEqual(events, ["commit", "checkpoint:PASSIVE"])
        self.assertEqual(checkpoints, ["PASSIVE"])
        self.assertNotIn("TRUNCATE", checkpoints)
        query.assert_not_called()

    def test_unchanged_source_is_reused_across_index_instances(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            source = _source(root, "one.jsonl", "raw-session-one")
            first_calls: list[str] = []
            _index_class()(cache).reconcile([source], _parser(first_calls))
            second_calls: list[str] = []
            second_index = _index_class()(cache)
            second_index.reconcile([source], _parser(second_calls))
            result = second_index.query()

        self.assertEqual(first_calls, ["raw-session-one"])
        self.assertEqual(second_calls, [])
        self.assertEqual(result["total"], 1)

    def test_added_changed_and_deleted_sources_reconcile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            original = _source(root, "one.jsonl", "one")
            removed = _source(root, "two.jsonl", "two")
            calls: list[str] = []
            index = _index_class()(cache)
            index.reconcile([original, removed], _parser(calls))
            changed = _source(root, "one.jsonl", "one", version=2)
            added = _source(root, "three.jsonl", "three")
            calls.clear()
            index.reconcile([changed, added], _parser(calls))
            result = index.query()

        self.assertEqual(calls, ["one", "three"])
        self.assertEqual(
            [row["title"] for row in result["sessions"]],
            ["Session one", "Session three"],
        )
        self.assertEqual(result["total"], 2)

    def test_query_preserves_filter_order_and_exact_pagination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            sources = [_source(root, f"{name}.jsonl", name, version) for version, name in enumerate(("old", "needle-a", "needle-b"), 1)]
            index = _index_class()(cache)
            index.reconcile(sources, _parser([]))
            result = index.query("needle", limit=1, offset=1)

        self.assertEqual([row["title"] for row in result["sessions"]], ["Session needle-a"])
        self.assertEqual(result["total"], 2)
        self.assertTrue(result["totalExact"])
        self.assertEqual(result["offset"], 1)
        self.assertEqual(result["limit"], 1)
        self.assertFalse(result["hasMore"])

    def test_persisted_database_contains_only_redacted_rows_and_hashed_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            source = _source(root, "private-transcript.jsonl", "raw-session-id")
            _index_class()(cache).reconcile(
                [source],
                lambda _source: [
                    {
                        "provider": "test",
                        "title": "Safe title",
                        "sessionName": "Fixture",
                        "state": "idle",
                        "lastActivityAt": 1,
                        "detail": "Safe detail",
                    }
                ],
            )
            persisted = cache.read_bytes()

        for secret in (str(source.path), source.source_id, "transcript-raw-session-id-v1"):
            self.assertNotIn(secret.encode(), persisted)
        self.assertNotIn(b"opaque-key", persisted)
        self.assertNotIn(b"openKey", persisted)
        self.assertRegex(persisted, rb"[0-9a-f]{64}")

    def test_corrupt_database_degrades_to_rebuild_and_miss(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            source = _source(root, "one.jsonl", "one")
            _index_class()(cache).reconcile([source], _parser([]))
            cache.write_bytes(b"not a sqlite database")
            calls: list[str] = []
            index = _index_class()(cache)
            index.reconcile([source], _parser(calls))
            result = index.query()

        self.assertEqual(calls, ["one"])
        self.assertEqual(result["total"], 1)


if __name__ == "__main__":
    unittest.main()
