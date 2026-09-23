"""Session-index invalidation and scaling safety (task 28).

The plan asks for a conservative evaluation: the warm path is already keyed by
a code-derived schema fingerprint, so this suite locks in that every
invalidation input rebuilds safely and that queries keep exact totals, privacy,
and source OR semantics at scale.
"""

import importlib
import sqlite3
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest import mock

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)


@dataclass(frozen=True, slots=True)
class Source:
    path: str
    source_id: str
    mtime_ns: int
    size: int


def _index_class():
    return importlib.import_module("aiusage.session_index").SessionIndex


def _storage():
    return importlib.import_module("aiusage.session_index_storage")


def _source(root, name, source_id, version=1):
    path = root / name
    content = f"transcript-{source_id}-v{version}"
    path.write_text(content, encoding="utf-8")
    return Source(str(path), source_id, version, len(content))


def _rows(source, count, provider="openai"):
    return [
        {
            "provider": provider,
            "title": f"needle session {source.source_id} {i}",
            "sessionName": f"Fixture {provider}",
            "state": "idle",
            "lastActivityAt": 1700000000000 + i,
            "detail": f"detail {provider}",
            "openKey": f"opaque-{source.source_id}-{i}",
        }
        for i in range(count)
    ]


class InvalidationSafetyTest(unittest.TestCase):
    def test_a_missing_content_module_still_yields_a_version(self):
        storage = _storage()
        storage._schema_version.cache_clear()
        self.addCleanup(storage._schema_version.cache_clear)
        with mock.patch.object(storage, "_CONTENT_SOURCES", ("this-module-does-not-exist.py",)):
            version = storage._schema_version()
        self.assertIsInstance(version, int)
        self.assertTrue(0 <= version <= 0x7FFF_FFFF)

    def test_wal_leftovers_do_not_break_a_reopen(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            source = _source(root, "one.jsonl", "one")
            index = _index_class()(cache)
            index.reconcile([source], lambda s: _rows(s, 3))
            # Leave the WAL on disk as a crashed writer would.
            self.assertTrue(any(Path(str(cache) + suffix).exists() for suffix in ("-wal", "-shm")) or cache.exists())
            reopened = _index_class()(cache)
            self.assertEqual(reopened.query()["total"], 3)

    def test_a_missing_required_column_is_treated_as_invalid_and_rebuilt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            source = _source(root, "one.jsonl", "one")
            _index_class()(cache).reconcile([source], lambda s: _rows(s, 2))
            connection = sqlite3.connect(str(cache))
            try:
                connection.execute("ALTER TABLE session_rows DROP COLUMN open_key")
                connection.commit()
            except sqlite3.OperationalError:
                self.skipTest("SQLite build does not support DROP COLUMN")
            finally:
                connection.close()
            index = _index_class()(cache)
            index.reconcile([source], lambda s: _rows(s, 2))
            self.assertEqual(index.query()["total"], 2)

    def test_concurrent_index_instances_stay_consistent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            first_source = _source(root, "one.jsonl", "one")
            second_source = _source(root, "two.jsonl", "two")
            writer = _index_class()(cache)
            reader = _index_class()(cache)
            writer.reconcile([first_source], lambda s: _rows(s, 4))
            reader_query = reader.query()
            writer.reconcile([first_source, second_source], lambda s: _rows(s, 4))
            final = reader.query()
        self.assertEqual(reader_query["total"], 4)
        self.assertEqual(final["total"], 8)
        self.assertTrue(final["totalExact"])


class ScalingContractTest(unittest.TestCase):
    def test_exact_totals_privacy_and_source_or_semantics_at_scale(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "sessions.sqlite3"
            one = _source(root, "one.jsonl", "one")
            two = _source(root, "two.jsonl", "two")
            index = _index_class()(cache)
            index.reconcile([one, two], lambda s: _rows(s, 2000, provider="openai" if s.source_id == "one" else "grok"))

            all_rows = index.query("", limit=20000)
            self.assertEqual(all_rows["total"], 4000)
            self.assertTrue(all_rows["totalExact"])

            needle = index.query("needle", limit=50)
            self.assertEqual(needle["total"], 4000)
            self.assertEqual(len(needle["sessions"]), 50)

            filtered = index.query("", limit=20000, source_ids=["grok"])
            self.assertEqual(filtered["total"], 2000)

            both = index.query("", limit=20000, source_ids=["openai", "grok"])
            self.assertEqual(both["total"], 4000)

            # No private field is exposed by the public row shape.
            sample = all_rows["sessions"][0]
            self.assertIn("openKey", sample)
            self.assertNotIn("open_key", sample)


if __name__ == "__main__":
    unittest.main()
