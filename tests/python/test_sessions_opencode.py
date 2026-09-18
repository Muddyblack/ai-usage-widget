import json
import os
import sqlite3
import tempfile
import unittest
from unittest import mock

from _support import IsolatedHomeTest, REPO  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import sessions
from aiusage.providers import opencode

_SESSION_SCHEMA = (
    "CREATE TABLE session ("
    "id TEXT PRIMARY KEY,"
    "title TEXT NOT NULL,"
    "directory TEXT NOT NULL,"
    "time_created INTEGER NOT NULL,"
    "time_updated INTEGER NOT NULL)"
)


def _create_database(root: str, name: str, rows: list[tuple[str, str, str, int, int]]) -> str:
    path = os.path.join(root, name)
    connection = sqlite3.connect(path)
    try:
        with connection:
            connection.executescript(_SESSION_SCHEMA)
            connection.executemany(
                "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                rows,
            )
    finally:
        connection.close()
    return path


class OpenCodeDiscoveryTest(unittest.TestCase):
    def test_discovers_every_opencode_database_without_scanning_unrelated_files(self):
        with tempfile.TemporaryDirectory() as root:
            data = os.path.join(root, "opencode")
            os.mkdir(data)
            first = _create_database(data, "opencode.db", [])
            second = _create_database(data, "opencode-stable.db", [])
            _create_database(data, "other.db", [])
            with (
                mock.patch.dict(os.environ, {"XDG_DATA_HOME": root}, clear=True),
                mock.patch.object(opencode.shutil, "which", return_value=None),
            ):
                found = opencode.discover_database_paths()

        self.assertEqual(found, sorted([first, second]))

    def test_explicit_database_does_not_fall_back_when_invalid(self):
        with tempfile.TemporaryDirectory() as root:
            explicit = os.path.join(root, "missing.db")
            _create_database(root, "opencode.db", [])
            with mock.patch.dict(os.environ, {"OPENCODE_DB": explicit}, clear=True):
                found = opencode.discover_database_paths()

        self.assertEqual(found, [])

    def test_uses_opencode_cli_database_path(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, "opencode-cli.db", [])
            result = mock.Mock(returncode=0, stdout=f"{path}\n")
            with (
                mock.patch.dict(os.environ, {}, clear=True),
                mock.patch.object(opencode.shutil, "which", return_value="/usr/bin/opencode"),
                mock.patch.object(opencode.subprocess, "run", return_value=result),
                mock.patch.object(opencode.paths, "data_home_dirs", return_value=[]),
            ):
                found = opencode.discover_database_paths()

        self.assertEqual(found, [path])

    def test_rejects_sqlite_files_without_a_session_table(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "opencode.db")
            connection = sqlite3.connect(path)
            try:
                connection.execute("CREATE TABLE unrelated (value TEXT)")
            finally:
                connection.close()
            with mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True):
                records = opencode.read_recent_sessions()

        self.assertEqual(records, [])


class OpenCodeSessionRowsTest(IsolatedHomeTest):
    def test_reads_only_recent_metadata_and_normalizes_milliseconds(self):
        rows = [(f"ses-{index:03d}", f"Session {index}", "/private/project", 1_700_000_000_000, 1_700_000_000_000 + index) for index in range(61)]
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, "opencode.db", rows)
            with mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True):
                records = opencode.read_recent_sessions()

        self.assertEqual(len(records), 60)
        self.assertEqual(records[0].session_id, "ses-060")
        self.assertEqual(records[0].last_activity, 1_700_000_000)
        self.assertEqual(records[0].directory, "/private/project")

    def test_query_reads_matching_rows_older_than_the_default_cap(self):
        rows = [
            (
                f"ses-{index:03d}",
                "older needle" if index == 0 else f"Session {index}",
                "/private/project",
                1_700_000_000_000,
                1_700_000_000_000 + index,
            )
            for index in range(61)
        ]
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, "opencode.db", rows)
            with (
                mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True),
                mock.patch.object(sessions, "_cline_entries", return_value=[]),
                mock.patch.object(sessions, "_muse_entries", return_value=[]),
                mock.patch.object(sessions, "_codex_entries", return_value=[]),
                mock.patch.object(sessions, "_grok_entries", return_value=[]),
                mock.patch.object(sessions, "_claude_entries", return_value=[]),
                mock.patch.object(sessions, "_antigravity_entries", return_value=[]),
            ):
                sessions.refresh_sessions()
                result = sessions.collect_sessions("needle")

        self.assertEqual([entry["title"] for entry in result["sessions"]], ["older needle"])
        encoded = json.dumps(result)
        self.assertNotIn(path, encoded)
        self.assertNotIn("ses-000", encoded)
        self.assertNotIn("/private/project", encoded)

    def test_multiple_databases_are_deduplicated_by_newest_session(self):
        with tempfile.TemporaryDirectory() as root:
            data = os.path.join(root, "opencode")
            os.mkdir(data)
            _create_database(data, "opencode-old.db", [("ses-same", "Old", "/old", 1, 10)])
            _create_database(data, "opencode-new.db", [("ses-same", "New", "/new", 1, 20)])
            with (
                mock.patch.dict(os.environ, {"XDG_DATA_HOME": root}, clear=True),
                mock.patch.object(opencode.shutil, "which", return_value=None),
            ):
                entries = sessions._opencode_entries()

        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["title"], "New")
        self.assertEqual(entries[0]["detail"], "new")
        self.assertNotIn("/new", json.dumps(entries))

    def test_public_entry_contains_no_database_path_or_session_id(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, "opencode.db", [("ses-secret", "Useful title", "/private/project", 1, 2_000)])
            with mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True):
                entry = sessions._opencode_entries()[0]

        encoded = json.dumps(entry)
        self.assertEqual(entry["provider"], "opencode")
        self.assertEqual(entry["sessionName"], "OpenCode")
        self.assertNotIn(path, encoded)
        self.assertNotIn("ses-secret", encoded)
        self.assertNotIn("/private/project", encoded)
        self.assertRegex(entry["openKey"], r"^[0-9a-f]{64}$")

    def test_open_targets_hash_database_identity_but_keep_real_resume_id(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, "opencode.db", [("ses-secret", "Title", "/tmp", 1, 2_000)])
            with mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True):
                targets = sessions.collect_open_targets()

        key_id = f"{path}\x00ses-secret"
        key = sessions._open_key("opencode", key_id)
        self.assertEqual(targets[key]["id"], "ses-secret")
        self.assertEqual(targets[key]["keyId"], key_id)


if __name__ == "__main__":
    unittest.main()
