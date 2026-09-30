"""MiMo uses the installed CLI's v1 schema; fixtures contain no personal data."""

import json
import os
import sqlite3
from contextlib import closing
from unittest import mock

from _support import IsolatedHomeTest
from aiusage import detect, session_manifest, sessions
from aiusage.normalize.mimo import normalize_mimo
from aiusage.providers import mimo, opencode


class MimoTest(IsolatedHomeTest):
    def database(self):
        path = self.home / ".local/share/mimocode/mimocode.db"
        path.parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(path)) as db, db:
            db.executescript("""
                CREATE TABLE session (id TEXT, title TEXT, directory TEXT, time_created INTEGER, time_updated INTEGER);
                CREATE TABLE message (id TEXT, session_id TEXT, agent_id TEXT, data TEXT);
                CREATE TABLE part (id TEXT, message_id TEXT, data TEXT);
            """)
            db.execute("INSERT INTO session VALUES (?, ?, ?, ?, ?)", ("ses_test", "Example", str(self.home), 1700000000000, 1700000000000))
            usage = {
                "role": "assistant",
                "providerID": "mimo",
                "modelID": "mimo-v2.5",
                "cost": 0.25,
                "tokens": {"input": 100, "output": 20, "reasoning": 0, "cache": {"read": 30, "write": 0}},
            }
            db.execute("INSERT INTO message VALUES (?, ?, ?, ?)", ("msg_test", "ses_test", "main", json.dumps(usage)))
            db.execute("INSERT INTO part VALUES (?, ?, ?)", ("part_test", "msg_test", json.dumps({**usage, "type": "step-finish"})))
        return path

    def test_discovery_is_separate_and_override_is_authoritative(self):
        path = self.database()
        self.assertEqual(mimo.discover_database_paths(), [str(path)])
        with mock.patch.object(opencode, "_cli_database_path", return_value=""):
            self.assertEqual(opencode.discover_database_paths(), [])
        with mock.patch.dict(os.environ, {"MIMO_DB": "mimocode.db"}):
            self.assertEqual(mimo.discover_database_paths(), [str(path)])
        with mock.patch.dict(os.environ, {"MIMO_DB": str(self.home / "missing.db")}):
            self.assertEqual(mimo.discover_database_paths(), [])

    def test_usage_deduplicates_parts_and_has_no_quota(self):
        self.database()
        with mock.patch("aiusage.pricing.load_catalog"), mock.patch("aiusage.pricing.cached_catalog", return_value={}):
            snapshot = mimo.usage_snapshot()
        row = snapshot["sessions"][0]
        self.assertEqual(row["costUSD"], 0.25)
        self.assertEqual(row["usage"][0]["input"], 100)
        normalized = normalize_mimo({"now": 1700000000, "inputs": {"usage": snapshot}})
        self.assertEqual(normalized["id"], "mimo")
        self.assertEqual(normalized["details"]["stats"]["totalTokens"], 150)
        self.assertFalse(normalized["historyValues"])
        self.assertTrue(all(not w["showMeter"] for w in normalized["quotaWindows"]))
        self.assertEqual(mimo.read_recent_sessions()[0].usage[0].source, "mimo")

    def test_empty_or_invalid_database_is_unavailable(self):
        path = self.home / "broken.db"
        path.write_bytes(b"not sqlite")
        with mock.patch.dict(os.environ, {"MIMO_DB": str(path)}), mock.patch("aiusage.pricing.load_catalog"):
            normalized = normalize_mimo({"now": 1700000000, "inputs": {"usage": mimo.usage_snapshot()}})
        self.assertFalse(normalized["ok"])
        self.assertFalse(normalized["details"]["stats"]["available"])

    def test_resume_target_and_wal_invalidation(self):
        path = self.database()
        with mock.patch("aiusage.pricing.cached_catalog", return_value={}):
            entries = sessions._mimo_entries()
        self.assertEqual(entries[0]["source"], "mimo")
        self.assertEqual(entries[0]["sessionName"], "via MiMo Code")
        self.assertEqual(sessions._mimo_targets()[0]["provider"], "mimo")
        self.assertEqual(sessions._mimo_targets()[0]["id"], "ses_test")
        before = session_manifest._mimo_records()
        path.with_name(path.name + "-wal").write_bytes(b"changed")
        self.assertNotEqual(before, session_manifest._mimo_records())

    def test_detects_mimo_executable(self):
        with mock.patch.object(detect.shutil, "which", side_effect=lambda name, **kwargs: "/bin/mimo" if name == "mimo" else None):
            self.assertIn("mimo", detect.detect_providers())

    def test_imported_history_is_not_mimo_usage_or_a_resume_target(self):
        for table in ("external_import", "claude_import"):
            with self.subTest(table=table):
                path = self.database()
                with closing(sqlite3.connect(path)) as db, db:
                    db.execute(f"CREATE TABLE {table} (session_id TEXT, message_ids TEXT)")
                    db.execute(f"INSERT INTO {table} VALUES (?, ?)", ("ses_test", '["msg_test"]'))
                self.assertEqual(mimo.read_recent_sessions(include_all=True), [])
                self.assertEqual(sessions._mimo_entries(), [])
                self.assertEqual(sessions._mimo_targets(), [])
                # Shared OpenCode parsing must remain unaffected.
                self.assertEqual(len(opencode._read_database(str(path))), 1)
                path.unlink()

    def test_native_continuation_excludes_imported_cost_and_tokens(self):
        path = self.database()
        with closing(sqlite3.connect(path)) as db, db:
            db.execute("CREATE TABLE external_import (session_id TEXT, message_ids TEXT)")
            db.execute("INSERT INTO external_import VALUES (?, ?)", ("ses_test", '["msg_test"]'))
            native = {"role": "assistant", "providerID": "mimo", "modelID": "mimo-v2.5", "cost": 0.02, "tokens": {"input": 5, "output": 7}}
            db.execute("INSERT INTO message VALUES (?, ?, ?, ?)", ("msg_native", "ses_test", "main", json.dumps(native)))
        records = mimo.read_recent_sessions()
        self.assertEqual(len(records), 1)
        self.assertEqual(sum(b.input_tokens for b in records[0].usage), 5)
        self.assertEqual(sum(b.output_tokens for b in records[0].usage), 7)
        self.assertAlmostEqual(sum(b.provider_cost_usd for b in records[0].usage), 0.02)

    def test_legacy_imports_without_message_tracking_are_excluded(self):
        path = self.database()
        with closing(sqlite3.connect(path)) as db, db:
            db.execute("CREATE TABLE claude_import (session_id TEXT)")
            db.execute("INSERT INTO claude_import VALUES ('ses_test')")
        self.assertEqual(mimo.read_recent_sessions(), [])
