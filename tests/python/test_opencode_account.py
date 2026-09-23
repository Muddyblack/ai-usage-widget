"""OpenCode account-mode detection and Go quota collection.

Baseline characterization first: the existing local SQLite session collection
output must be unchanged. Then the account contract: Zen/Go mode selection from
``auth.json``, the single bounded Go endpoint call, stable error strings, and
the guarantee that the bearer key never reaches output or error text.
"""

import json
import os
import sqlite3
import tempfile
import unittest
from unittest import mock

from _support import IsolatedHomeTest
from aiusage.collect import collect_opencode
from aiusage.http import HttpResult
from aiusage.providers import opencode_account

_SESSION_SCHEMA = """
CREATE TABLE session (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    directory TEXT NOT NULL,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL
);
"""
_MESSAGE_SCHEMA = """
CREATE TABLE message (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    data TEXT NOT NULL
);
"""
_PART_SCHEMA = """
CREATE TABLE part (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    data TEXT NOT NULL
);
"""

_GO_BODY = json.dumps(
    {
        "usage": {
            "rolling": {"status": "ok", "percent": 42, "resetsAt": "2026-09-23T00:00:00Z"},
            "weekly": {"status": "ok", "percent": 61, "resetsAt": "2026-09-28T00:00:00Z"},
            "monthly": {"status": "ok", "percent": 33, "resetsAt": "2026-10-01T00:00:00Z"},
        }
    }
)


def _create_database(root: str) -> str:
    path = os.path.join(root, "opencode.db")
    connection = sqlite3.connect(path)
    try:
        with connection:
            connection.executescript(_SESSION_SCHEMA + _MESSAGE_SCHEMA + _PART_SCHEMA)
            connection.execute(
                "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                ("session-1", "Synthetic session", "/synthetic/project", 1, 2_000),
            )
            connection.execute(
                "INSERT INTO message VALUES (?, ?, ?)",
                (
                    "message-1",
                    "session-1",
                    json.dumps(
                        {
                            "role": "assistant",
                            "modelID": "gpt-test",
                            "providerID": "anthropic",
                            "tokens": {"input": 800, "output": 100},
                            "cost": 0.42,
                        }
                    ),
                ),
            )
    finally:
        connection.close()
    return path


class OpenCodeAccountModeTest(IsolatedHomeTest):
    def _write_auth(self, entries):
        self.write(".local/share/opencode/auth.json", entries)

    def _collect(self, now=1_000):
        return collect_opencode(now)

    # ── Baseline characterization: local session collection unchanged ──────

    def test_baseline_local_session_collection_is_unchanged(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root)
            with mock.patch.dict(os.environ, {"OPENCODE_DB": path}):
                raw = self._collect()

        usage = raw["inputs"]["usage"]
        self.assertEqual(len(usage["sessions"]), 1)
        session = usage["sessions"][0]
        for key in ("id", "title", "directory", "createdAt", "lastActivity", "usage", "costUSD", "costStatus", "costProvenance"):
            self.assertIn(key, session)
        self.assertEqual(session["id"], "session-1")
        self.assertEqual(session["usage"][0]["provider"], "anthropic")
        self.assertEqual(session["usage"][0]["model"], "gpt-test")
        self.assertEqual(session["usage"][0]["input"], 800)
        self.assertEqual(session["usage"][0]["output"], 100)
        self.assertEqual(session["usage"][0]["costUSD"], 0.42)
        # The new account field is additive and defaults to Zen with no Go data.
        self.assertEqual(raw["inputs"]["account"], {"mode": "zen", "goUsage": None, "goError": ""})

    # ── Mode selection ─────────────────────────────────────────────────────

    def test_zen_only_auth_never_calls_the_go_endpoint(self):
        self._write_auth({"opencode": {"type": "api", "key": "zen-key"}})
        with mock.patch("aiusage.providers.opencode_account.fetch_json") as fetch:
            raw = self._collect()
        self.assertEqual(raw["inputs"]["account"]["mode"], "zen")
        self.assertIsNone(raw["inputs"]["account"]["goUsage"])
        self.assertEqual(raw["inputs"]["account"]["goError"], "")
        fetch.assert_not_called()

    def test_go_only_auth_fetches_the_go_endpoint_with_bearer_key(self):
        self._write_auth({"opencode-go": {"type": "api", "key": "go-secret-key"}})
        with mock.patch(
            "aiusage.providers.opencode_account.fetch_json",
            return_value=HttpResult(200, _GO_BODY),
        ) as fetch:
            raw = self._collect()

        account = raw["inputs"]["account"]
        self.assertEqual(account["mode"], "go")
        self.assertEqual(account["goError"], "")
        self.assertEqual(account["goUsage"]["usage"]["rolling"]["percent"], 42)
        fetch.assert_called_once()
        self.assertEqual(fetch.call_args.args[0], opencode_account.GO_USAGE_URL)
        self.assertEqual(fetch.call_args.kwargs["headers"]["Authorization"], "Bearer go-secret-key")
        self.assertIsNone(fetch.call_args.kwargs.get("data"))

    def test_both_auth_entries_go_wins_in_either_json_order(self):
        for order in (
            {"opencode": {"type": "api", "key": "zen-key"}, "opencode-go": {"type": "api", "key": "go-key"}},
            {"opencode-go": {"type": "api", "key": "go-key"}, "opencode": {"type": "api", "key": "zen-key"}},
        ):
            with self.subTest(order=order):
                self._write_auth(order)
                with mock.patch(
                    "aiusage.providers.opencode_account.fetch_json",
                    return_value=HttpResult(200, _GO_BODY),
                ) as fetch:
                    raw = self._collect()
                self.assertEqual(raw["inputs"]["account"]["mode"], "go")
                self.assertEqual(fetch.call_args.kwargs["headers"]["Authorization"], "Bearer go-key")

    def test_neither_auth_entry_defaults_to_zen(self):
        self._write_auth({"ollama-cloud": {"type": "api", "key": "other-key"}})
        with mock.patch("aiusage.providers.opencode_account.fetch_json") as fetch:
            raw = self._collect()
        self.assertEqual(raw["inputs"]["account"]["mode"], "zen")
        fetch.assert_not_called()

    def test_missing_auth_file_defaults_to_zen(self):
        with mock.patch("aiusage.providers.opencode_account.fetch_json") as fetch:
            raw = self._collect()
        self.assertEqual(raw["inputs"]["account"]["mode"], "zen")
        fetch.assert_not_called()

    def test_invalid_auth_json_defaults_to_zen(self):
        self.write(".local/share/opencode/auth.json", "{not valid json")
        with mock.patch("aiusage.providers.opencode_account.fetch_json") as fetch:
            raw = self._collect()
        self.assertEqual(raw["inputs"]["account"]["mode"], "zen")
        fetch.assert_not_called()

    def test_malformed_entries_are_not_valid_credentials(self):
        malformed = (
            {"opencode-go": "not-a-dict"},
            {"opencode-go": {"type": "oauth", "key": "go-key"}},
            {"opencode-go": {"type": "api", "key": 123}},
            {"opencode-go": {"type": "api", "key": ""}},
            {"opencode-go": {"type": "api", "key": "   "}},
            {"opencode-go": {"type": "api", "key": "bad\x01key"}},
        )
        for entries in malformed:
            with self.subTest(entries=entries):
                self._write_auth(entries)
                with mock.patch("aiusage.providers.opencode_account.fetch_json") as fetch:
                    raw = self._collect()
                self.assertEqual(raw["inputs"]["account"]["mode"], "zen")
                fetch.assert_not_called()

    def test_non_latin1_go_key_is_rejected_without_request_or_disclosure(self):
        secret = "go-secret-☃"
        self._write_auth({"opencode-go": {"type": "api", "key": secret}})
        with mock.patch("aiusage.providers.opencode_account.fetch_json") as fetch:
            raw = self._collect()

        account = raw["inputs"]["account"]
        self.assertEqual(account["mode"], "zen")
        self.assertIsNone(account["goUsage"])
        self.assertEqual(account["goError"], "")
        self.assertNotIn(secret, json.dumps(raw))
        fetch.assert_not_called()

    # ── Go endpoint errors stay Go mode with stable strings ────────────────

    def test_go_http_errors_stay_go_mode_with_stable_error(self):
        cases = ((401, "token expired"), (403, "access denied"), (429, "rate limited"), (0, "offline"))
        for status, expected in cases:
            with self.subTest(status=status):
                self._write_auth({"opencode-go": {"type": "api", "key": "go-key"}})
                with mock.patch(
                    "aiusage.providers.opencode_account.fetch_json",
                    return_value=HttpResult(status, ""),
                ):
                    raw = self._collect()
                account = raw["inputs"]["account"]
                self.assertEqual(account["mode"], "go")
                self.assertIsNone(account["goUsage"])
                self.assertEqual(account["goError"], expected)

    def test_go_403_never_falls_back_to_zen_or_reports_zero(self):
        self._write_auth({"opencode-go": {"type": "api", "key": "go-key"}})
        with mock.patch(
            "aiusage.providers.opencode_account.fetch_json",
            return_value=HttpResult(403, ""),
        ):
            raw = self._collect()
        account = raw["inputs"]["account"]
        self.assertEqual(account["mode"], "go")
        self.assertIsNone(account["goUsage"])
        self.assertEqual(account["goError"], "access denied")

    def test_go_invalid_json_is_parse_error_not_zero(self):
        self._write_auth({"opencode-go": {"type": "api", "key": "go-key"}})
        for body in ("not json", "[]", "42", ""):
            with self.subTest(body=body):
                with mock.patch(
                    "aiusage.providers.opencode_account.fetch_json",
                    return_value=HttpResult(200, body),
                ):
                    raw = self._collect()
                account = raw["inputs"]["account"]
                self.assertEqual(account["mode"], "go")
                self.assertIsNone(account["goUsage"])
                self.assertEqual(account["goError"], "parse error")

    # ── Secret non-disclosure ──────────────────────────────────────────────

    def test_go_key_never_appears_in_output_or_error_text(self):
        secret = "sk-opencode-go-super-secret-9f8e7d"
        self._write_auth({"opencode-go": {"type": "api", "key": secret}})
        with mock.patch(
            "aiusage.providers.opencode_account.fetch_json",
            return_value=HttpResult(200, _GO_BODY),
        ):
            raw = self._collect()
        serialized = json.dumps(raw)
        self.assertNotIn(secret, serialized)
        self.assertNotIn("Bearer", serialized)

        with mock.patch(
            "aiusage.providers.opencode_account.fetch_json",
            return_value=HttpResult(403, ""),
        ):
            raw = self._collect()
        self.assertNotIn(secret, json.dumps(raw))
        self.assertEqual(raw["inputs"]["account"]["goError"], "access denied")

    # ── Fixture replay hook (no network) ───────────────────────────────────

    def test_go_response_fixture_hook_replays_without_network(self):
        self._write_auth({"opencode-go": {"type": "api", "key": "go-key"}})
        with tempfile.TemporaryDirectory() as root:
            fixture = os.path.join(root, "go-usage.json")
            with open(fixture, "w", encoding="utf-8") as f:
                f.write(_GO_BODY)
            with mock.patch.dict(os.environ, {"OPENCODE_GO_USAGE_RESPONSE_FILE": fixture}):
                raw = self._collect()
        account = raw["inputs"]["account"]
        self.assertEqual(account["mode"], "go")
        self.assertEqual(account["goError"], "")
        self.assertEqual(account["goUsage"]["usage"]["weekly"]["percent"], 61)


if __name__ == "__main__":
    unittest.main()
