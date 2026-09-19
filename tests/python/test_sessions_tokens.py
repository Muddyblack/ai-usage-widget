"""Per-session token totals — local-only aggregation, never message content.

Codex and Claude Code both write cumulative token counters into their own
transcripts. Reading them is reading numbers the CLI itself already computed,
not prompts or responses, so it stays inside the redaction boundary
sessions.py's module docstring describes.
"""

import json
import math
import os
import tempfile
import unittest
from unittest import mock

from _support import REPO, raw_fixture  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import pricing, sessions


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

    def test_claude_entries_keep_valid_usage_beside_nonfinite_usage(self):
        with tempfile.TemporaryDirectory() as root:
            projects = os.path.join(root, "projects", "-mnt-projects-widget")
            os.makedirs(projects, exist_ok=True)
            with open(os.path.join(projects, "session-1.jsonl"), "w", encoding="utf-8") as f:
                malformed = {
                    "sessionId": "session-1",
                    "message": {"model": "claude-test", "usage": {"input_tokens": math.nan, "output_tokens": math.inf}},
                }
                valid = {"sessionId": "session-1", "message": {"model": "claude-test", "usage": {"input_tokens": 100, "output_tokens": 50}}}
                f.write(json.dumps(malformed) + "\n")
                f.write(json.dumps(valid) + "\n")
            with (
                mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}),
                mock.patch.object(pricing, "cached_catalog", return_value={"anthropic": {"claude-test": {"input": 2, "output": 8}}}),
            ):
                entry = sessions._claude_entries()[0]
        self.assertEqual(entry["costStatus"], "exact")
        self.assertAlmostEqual(entry["costUSD"], 0.0006)


class ClineSessionCostTest(unittest.TestCase):
    def _entry_for_record(self, record):
        with (
            mock.patch.object(sessions, "get_cline_sessions", return_value={"sessions": [record]}),
            mock.patch.object(sessions, "_cline_ids", return_value=["synthetic-session"]),
        ):
            return sessions._cline_entries()[0]

    def test_cline_provider_cost_is_not_structured_as_local_actual(self):
        record = {
            "startedAt": 1789047000,
            "endedAt": 1789047600,
            "provider": "cline",
            "model": "synthetic-model",
            "workspace": "synthetic-workspace",
            "input": 1000,
            "output": 200,
            "cost": 0.123456,
        }
        entry = self._entry_for_record(record)

        self.assertEqual(entry["costStatus"], "unavailable", msg=json.dumps(entry, sort_keys=True))
        self.assertNotIn("costUSD", entry)
        self.assertIn("1.2K tok", entry["detail"])
        self.assertIn("synthetic-model", entry["detail"])
        self.assertNotIn("$0.12", entry["detail"])

    def test_cline_missing_provider_cost_stays_unavailable(self):
        entry = self._entry_for_record(
            {
                "startedAt": 1789047000,
                "endedAt": 1789047600,
                "provider": "cline",
                "model": "synthetic-model",
                "workspace": "synthetic-workspace",
                "input": 1000,
                "output": 200,
            }
        )

        self.assertEqual(entry["costStatus"], "unavailable")
        self.assertNotIn("costUSD", entry)

    def test_cline_known_tokens_use_cached_rate_when_provider_cost_is_zero(self):
        record = {
            "startedAt": 1789047000,
            "endedAt": 1789047600,
            "provider": "cline",
            "model": "anthropic/claude-sonnet-4.5",
            "workspace": "synthetic-workspace",
            "input": 100,
            "output": 50,
            "cacheRead": 20,
            "cacheWrite": 10,
            "cost": 0,
        }
        with mock.patch.object(
            pricing,
            "cached_catalog",
            return_value={
                "anthropic": {"claude-sonnet-4.5": {"input": 2, "output": 8, "cached": 0.2}},
                "openai": {"gpt-4o": {"input": 4, "output": 12}},
            },
        ):
            entry = self._entry_for_record(record)

        self.assertEqual(entry["costStatus"], "exact")
        self.assertEqual(entry["costProvenance"], "estimated")
        self.assertAlmostEqual(entry["costUSD"], 0.000584)

    def test_cline_unknown_or_unsupported_provider_stays_unavailable(self):
        catalog = {
            "anthropic": {"claude-sonnet-4.5": {"input": 2, "output": 8}},
            "openai": {"gpt-4o": {"input": 4, "output": 12}},
            "cline": {"z-ai/glm-5.3-flash": {"input": 1, "output": 1}},
        }
        for model in ("z-ai/glm-5.3-flash", "unknown/model"):
            with self.subTest(model=model), mock.patch.object(pricing, "cached_catalog", return_value=catalog):
                entry = self._entry_for_record(
                    {
                        "startedAt": 1789047000,
                        "endedAt": 1789047600,
                        "provider": "cline",
                        "model": model,
                        "workspace": "synthetic-workspace",
                        "input": 100,
                        "output": 50,
                    }
                )

            self.assertEqual(entry["costStatus"], "unavailable")
            self.assertNotIn("costUSD", entry)

    def test_cline_nonfinite_provider_cost_stays_unavailable(self):
        for invalid_cost in (math.nan, math.inf, -math.inf):
            with self.subTest(invalid_cost=invalid_cost):
                entry = self._entry_for_record(
                    {
                        "startedAt": 1789047000,
                        "endedAt": 1789047600,
                        "provider": "cline",
                        "model": "synthetic-model",
                        "workspace": "synthetic-workspace",
                        "input": 1000,
                        "output": 200,
                        "cost": invalid_cost,
                    }
                )

                self.assertEqual(entry["costStatus"], "unavailable")
                self.assertNotIn("costUSD", entry)


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

    def test_last_token_usage_is_priced_before_cumulative_fallback(self):
        session_id = "019f03b5-a296-7563-adc8-5e66dea3fcd3"
        with tempfile.TemporaryDirectory() as root:
            self._write_rollout(
                root,
                f"rollout-2026-01-01T00-00-00-{session_id}.jsonl",
                [
                    {"payload": {"cwd": "/mnt/projects/widget", "model": "gpt-6-astra"}},
                    {
                        "payload": {
                            "type": "token_count",
                            "info": {
                                "last_token_usage": {
                                    "input_tokens": 1_000,
                                    "cached_input_tokens": 200,
                                    "output_tokens": 100,
                                    "reasoning_output_tokens": 10,
                                },
                                "total_token_usage": {"input_tokens": 9_000, "output_tokens": 900},
                            },
                        }
                    },
                ],
            )
            with (
                mock.patch.dict(os.environ, {"CODEX_SESSIONS_DIR": os.path.join(root, "sessions")}),
                mock.patch.object(pricing, "cached_catalog", return_value={"openai": {"gpt-6-astra": {"input": 2, "output": 8, "cached": 0.2}}}),
            ):
                entry = sessions._codex_entries()[0]
        self.assertEqual(entry["costStatus"], "exact")
        self.assertAlmostEqual(entry["costUSD"], 0.00252)

    def test_fixture_backed_codex_model_uses_exact_cached_rate(self):
        session_id = "019f03b5-a296-7563-adc8-5e66dea3fcd4"
        fixture = raw_fixture("openai-codex-success")
        rates = fixture["inputs"]["pricing"]
        with tempfile.TemporaryDirectory() as root:
            self._write_rollout(
                root,
                f"rollout-2026-01-01T00-00-00-{session_id}.jsonl",
                [
                    {"payload": {"cwd": "/mnt/projects/widget", "model": "gpt-4o"}},
                    {
                        "payload": {
                            "type": "token_count",
                            "info": {"last_token_usage": {"input_tokens": 1_000, "output_tokens": 100}},
                        }
                    },
                ],
            )
            with (
                mock.patch.dict(os.environ, {"CODEX_SESSIONS_DIR": os.path.join(root, "sessions")}),
                mock.patch.object(pricing, "cached_catalog", return_value={"openai": rates}),
            ):
                entry = sessions._codex_entries()[0]
        self.assertEqual(entry["costStatus"], "exact")
        self.assertAlmostEqual(entry["costUSD"], 0.0035)

    def test_fixture_stats_only_codex_model_stays_unavailable_without_price(self):
        session_id = "019f03b5-a296-7563-adc8-5e66dea3fcd5"
        fixture = raw_fixture("openai-codex-success")
        rates = fixture["inputs"]["pricing"]
        with tempfile.TemporaryDirectory() as root:
            self._write_rollout(
                root,
                f"rollout-2026-01-01T00-00-00-{session_id}.jsonl",
                [
                    {"payload": {"cwd": "/mnt/projects/widget", "model": "gpt-5-codex"}},
                    {
                        "payload": {
                            "type": "token_count",
                            "info": {"last_token_usage": {"input_tokens": 1_000, "output_tokens": 100}},
                        }
                    },
                ],
            )
            with (
                mock.patch.dict(os.environ, {"CODEX_SESSIONS_DIR": os.path.join(root, "sessions")}),
                mock.patch.object(pricing, "cached_catalog", return_value={"openai": rates}),
            ):
                entry = sessions._codex_entries()[0]
        self.assertEqual(entry["costStatus"], "unavailable")
        self.assertNotIn("costUSD", entry)

    def test_fixture_priced_and_stats_only_models_remain_partial(self):
        session_id = "019f03b5-a296-7563-adc8-5e66dea3fcd6"
        fixture = raw_fixture("openai-codex-success")
        rates = fixture["inputs"]["pricing"]
        with tempfile.TemporaryDirectory() as root:
            self._write_rollout(
                root,
                f"rollout-2026-01-01T00-00-00-{session_id}.jsonl",
                [
                    {"payload": {"cwd": "/mnt/projects/widget", "model": "gpt-4o"}},
                    {
                        "payload": {
                            "type": "token_count",
                            "model": "gpt-4o",
                            "info": {"last_token_usage": {"input_tokens": 1_000, "output_tokens": 100}},
                        }
                    },
                    {
                        "payload": {
                            "type": "token_count",
                            "model": "gpt-5-codex",
                            "info": {"last_token_usage": {"input_tokens": 100, "output_tokens": 10}},
                        }
                    },
                ],
            )
            with (
                mock.patch.dict(os.environ, {"CODEX_SESSIONS_DIR": os.path.join(root, "sessions")}),
                mock.patch.object(pricing, "cached_catalog", return_value={"openai": rates}),
            ):
                entry = sessions._codex_entries()[0]
        self.assertEqual(entry["costStatus"], "partial")
        self.assertAlmostEqual(entry["costUSD"], 0.0035)


if __name__ == "__main__":
    unittest.main()
