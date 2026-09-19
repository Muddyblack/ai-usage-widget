import json
import math
import os
import tempfile
import unittest
from unittest import mock

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import sessions
from test_opencode_costs import _assistant_message, _create_database


def _read_entry(path, rates=None, openai_rates=None):
    catalog = {"anthropic": rates or {}, "openai": openai_rates or {}, "openrouter": {}}
    with (
        mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True),
        mock.patch.object(sessions.pricing, "cached_catalog", return_value=catalog),
    ):
        return sessions._opencode_entries()[0]


class OpenCodeSessionCostTest(unittest.TestCase):
    def test_finite_provider_cost_is_serialized_on_the_public_session_row(self):
        messages = [
            _assistant_message(tokens={"input": 0, "output": 0}, cost=0.42),
            ("prompt-1", "session-1", json.dumps({"role": "user", "content": "private prompt text"})),
        ]
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=messages)
            entry = _read_entry(path)

        self.assertEqual(entry["provider"], "anthropic")
        self.assertEqual(entry["source"], "opencode")
        self.assertEqual(entry["sessionName"], "via OpenCode")
        self.assertEqual(entry["costStatus"], "exact")
        self.assertEqual(entry["costProvenance"], "actual")
        self.assertEqual(entry["costUSD"], 0.42)
        encoded = json.dumps(entry)
        self.assertNotIn(path, encoded)
        self.assertNotIn("session-1", encoded)
        self.assertNotIn("private prompt text", encoded)

    def test_token_usage_uses_the_exact_cached_upstream_model_rate(self):
        message = _assistant_message(tokens={"input": 800, "output": 100, "reasoning": 10, "cache": {"read": 200, "write": 20}})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            entry = _read_entry(path, rates={"gpt-test": {"input": 2, "output": 8, "cached": 0.2}})

        self.assertEqual(entry["costStatus"], "exact")
        self.assertEqual(entry["costProvenance"], "estimated")
        self.assertEqual(entry["costUSD"], 0.00216)

    def test_exact_model_identity_uses_openai_catalog_rates(self):
        message = _assistant_message(provider_id="openai", model="gpt-test", tokens={"input": 800, "output": 100})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            entry = _read_entry(path, openai_rates={"gpt-test": {"input": 2, "output": 8}})

        self.assertEqual(entry["costStatus"], "exact")
        self.assertEqual(entry["costProvenance"], "estimated")
        self.assertAlmostEqual(entry["costUSD"], 0.0024)

    def test_near_match_model_identity_stays_unavailable(self):
        message = _assistant_message(provider_id="openai", model="gpt-test-mini", tokens={"input": 800, "output": 100})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            entry = _read_entry(path, openai_rates={"gpt-test": {"input": 2, "output": 8}})

        self.assertEqual(entry["costStatus"], "unavailable")
        self.assertNotIn("costUSD", entry)

    def test_nonmatching_upstream_catalog_namespace_stays_unavailable(self):
        message = _assistant_message(provider_id="openai", model="gpt-test", tokens={"input": 800, "output": 100})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            entry = _read_entry(path, rates={"gpt-test": {"input": 2, "output": 8}})

        self.assertEqual(entry["costStatus"], "unavailable")
        self.assertNotIn("costUSD", entry)

    def test_openai_upstream_provider_uses_openai_catalog(self):
        message = _assistant_message(provider_id="openai", model="gpt-test", tokens={"input": 800, "output": 100})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            entry = _read_entry(path, openai_rates={"gpt-test": {"input": 2, "output": 8}})

        self.assertEqual(entry["provider"], "openai")
        self.assertEqual(entry["source"], "opencode")
        self.assertEqual(entry["costStatus"], "exact")
        self.assertAlmostEqual(entry["costUSD"], 0.0024)

    def test_token_usage_with_unknown_model_stays_unavailable(self):
        message = _assistant_message(provider_id="openai", model="unpriced", tokens={"output": 100})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            entry = _read_entry(path)

        self.assertEqual(entry["costStatus"], "unavailable")
        self.assertNotIn("costUSD", entry)

    def test_metadata_only_session_stays_unavailable(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, include_usage_tables=False)
            entry = _read_entry(path)

        self.assertEqual(entry["costStatus"], "unavailable")
        self.assertNotIn("costUSD", entry)

    def test_invalid_provider_cost_stays_unavailable(self):
        for invalid_cost in (None, math.nan, math.inf, -math.inf, -1):
            with self.subTest(invalid_cost=invalid_cost):
                message = _assistant_message(tokens={"input": 0, "output": 0}, cost=invalid_cost)
                with tempfile.TemporaryDirectory() as root:
                    path = _create_database(root, messages=[message])
                    entry = _read_entry(path)

                self.assertEqual(entry["costStatus"], "unavailable")
                self.assertNotIn("costUSD", entry)

    def test_multi_provider_session_carries_per_provider_costs(self):
        messages = [
            _assistant_message("message-1", provider_id="ollama-cloud", tokens={"input": 0, "output": 0}, cost=0.42),
            _assistant_message("message-2", provider_id="openai", tokens={"input": 800, "output": 100}),
        ]
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=messages)
            entry = _read_entry(path, openai_rates={"gpt-test": {"input": 2, "output": 8}})

        self.assertEqual(entry["provider"], "opencode")
        self.assertEqual(entry["source"], "opencode")
        self.assertNotIn("billingProvider", entry)
        self.assertEqual(entry["costProvenance"], "mixed")
        self.assertAlmostEqual(entry["costUSD"], 0.4224)
        self.assertEqual(entry["providerCosts"]["ollama-cloud"]["costUSD"], 0.42)
        self.assertEqual(entry["providerCosts"]["ollama-cloud"]["costProvenance"], "actual")
        self.assertEqual(entry["providerCosts"]["openai"]["costProvenance"], "estimated")
        self.assertAlmostEqual(entry["providerCosts"]["openai"]["costUSD"], 0.0024)

    def test_collect_sessions_keeps_opencode_cost_and_estimates_cline_tokens_only(self):
        message = _assistant_message(tokens={"input": 0, "output": 0}, cost=0.42)
        cline_record = {
            "startedAt": 1_700_000_000,
            "endedAt": 1_700_000_100,
            "provider": "cline",
            "model": "anthropic/claude-sonnet-4.5",
            "workspace": "cline-project",
            "input": 100,
            "output": 50,
            "cost": 0.13,
        }
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            with (
                mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True),
                mock.patch.object(
                    sessions.pricing,
                    "cached_catalog",
                    return_value={"anthropic": {"gpt-test": {}, "claude-sonnet-4.5": {"input": 2, "output": 8}}, "openai": {}, "openrouter": {}},
                ),
                mock.patch.object(sessions, "get_cline_sessions", return_value={"sessions": [cline_record]}),
                mock.patch.object(sessions, "_cline_ids", return_value=["cline-session"]),
                mock.patch.object(sessions, "_muse_entries", return_value=[]),
                mock.patch.object(sessions, "_codex_entries", return_value=[]),
                mock.patch.object(sessions, "_grok_entries", return_value=[]),
                mock.patch.object(sessions, "_claude_entries", return_value=[]),
                mock.patch.object(sessions, "_antigravity_entries", return_value=[]),
            ):
                result = sessions.collect_sessions()

        entries = {entry["provider"]: entry for entry in result["sessions"]}
        self.assertEqual(entries["anthropic"]["costStatus"], "exact")
        self.assertEqual(entries["anthropic"]["costUSD"], 0.42)
        self.assertEqual(entries["cline"]["costStatus"], "exact")
        self.assertEqual(entries["cline"]["costProvenance"], "estimated")
        self.assertAlmostEqual(entries["cline"]["costUSD"], 0.0006)


if __name__ == "__main__":
    unittest.main()
