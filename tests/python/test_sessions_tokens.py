"""Per-session token totals — local-only aggregation, never message content.

Codex and Claude Code both write cumulative token counters into their own
transcripts. Reading them is reading numbers the CLI itself already computed,
not prompts or responses, so it stays inside the redaction boundary
sessions.py's module docstring describes.
"""

import json
import os
import tempfile
import unittest
from unittest import mock

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import sessions


class FormatTokensTest(unittest.TestCase):
    """K/M formatting for the detail line — matches every frontend's own
    formatTokens() so a session row reads the same way as the stats views."""

    def test_below_a_thousand_is_the_plain_integer(self):
        self.assertEqual(sessions._format_tokens(0), "0")
        self.assertEqual(sessions._format_tokens(999), "999")

    def test_thousands_get_one_decimal_and_a_k_suffix(self):
        self.assertEqual(sessions._format_tokens(1000), "1.0K")
        self.assertEqual(sessions._format_tokens(2500), "2.5K")
        self.assertEqual(sessions._format_tokens(999_999), "1000.0K")

    def test_millions_get_two_decimals_and_an_m_suffix(self):
        self.assertEqual(sessions._format_tokens(1_000_000), "1.00M")
        self.assertEqual(sessions._format_tokens(1_947_411), "1.95M")

    def test_none_or_falsy_is_zero(self):
        self.assertEqual(sessions._format_tokens(None), "0")
        self.assertEqual(sessions._format_tokens(0), "0")


class ClaudeSessionTokensTest(unittest.TestCase):
    def test_missing_file_is_zero(self):
        self.assertEqual(sessions._claude_session_tokens("/no/such/file.jsonl"), 0)

    def test_sums_usage_across_messages(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "t.jsonl")
            with open(path, "w", encoding="utf-8") as f:
                f.write(json.dumps({"message": {"usage": {"input_tokens": 10, "output_tokens": 5}}}) + "\n")
                f.write(json.dumps({"message": {"usage": {"input_tokens": 3, "output_tokens": 2, "cache_read_input_tokens": 100}}}) + "\n")
                f.write(json.dumps({"type": "mode", "mode": "normal"}) + "\n")  # no usage
            self.assertEqual(sessions._claude_session_tokens(path), 10 + 5 + 3 + 2 + 100)

    def test_malformed_lines_are_skipped_not_fatal(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "t.jsonl")
            with open(path, "w", encoding="utf-8") as f:
                f.write('not json but has "usage" in it\n')
                f.write(json.dumps({"message": {"usage": {"input_tokens": 7}}}) + "\n")
            self.assertEqual(sessions._claude_session_tokens(path), 7)

    def test_claude_entries_detail_includes_token_total(self):
        with tempfile.TemporaryDirectory() as root:
            projects = os.path.join(root, "projects", "-mnt-projects-widget")
            os.makedirs(projects, exist_ok=True)
            with open(os.path.join(projects, "session-1.jsonl"), "w", encoding="utf-8") as f:
                f.write(json.dumps({"sessionId": "session-1", "message": {"usage": {"input_tokens": 1000, "output_tokens": 234}}}) + "\n")
            with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}):
                entries = sessions._claude_entries()
        self.assertEqual(len(entries), 1)
        self.assertIn("1.2K tok", entries[0]["detail"])


class CodexTokenCountTest(unittest.TestCase):
    def _write_rollout(self, root, name, lines):
        sessions_dir = os.path.join(root, "sessions")
        os.makedirs(sessions_dir, exist_ok=True)
        path = os.path.join(sessions_dir, name)
        with open(path, "w", encoding="utf-8") as f:
            for line in lines:
                f.write(json.dumps(line) + "\n")
        return path

    def test_last_token_count_event_wins_and_appears_in_detail(self):
        session_id = "019f03b5-a296-7563-adc8-5e66dea3fcd1"
        with tempfile.TemporaryDirectory() as root:
            self._write_rollout(
                root,
                f"rollout-2026-01-01T00-00-00-{session_id}.jsonl",
                [
                    {"payload": {"cwd": "/mnt/projects/widget", "model": "gpt-6-astra"}},
                    {"payload": {"type": "token_count", "info": {"total_token_usage": {"total_tokens": 1000}}}},
                    {"payload": {"type": "token_count", "info": {"total_token_usage": {"total_tokens": 2500}}}},
                ],
            )
            with mock.patch.dict(os.environ, {"CODEX_SESSIONS_DIR": os.path.join(root, "sessions")}):
                entries = sessions._codex_entries()
        self.assertEqual(len(entries), 1)
        entry = entries[0]
        self.assertEqual(entry["title"], "widget")
        self.assertIn("2.5K tok", entry["detail"])
        self.assertIn("gpt-6-astra", entry["detail"])

    def test_no_token_count_event_omits_token_detail(self):
        session_id = "019f03b5-a296-7563-adc8-5e66dea3fcd2"
        with tempfile.TemporaryDirectory() as root:
            self._write_rollout(
                root,
                f"rollout-2026-01-01T00-00-00-{session_id}.jsonl",
                [{"payload": {"cwd": "/mnt/projects/widget", "model": "gpt-6-astra"}}],
            )
            with mock.patch.dict(os.environ, {"CODEX_SESSIONS_DIR": os.path.join(root, "sessions")}):
                entries = sessions._codex_entries()
        self.assertNotIn("tok", entries[0]["detail"])
        self.assertEqual(entries[0]["detail"], "gpt-6-astra")


if __name__ == "__main__":
    unittest.main()
