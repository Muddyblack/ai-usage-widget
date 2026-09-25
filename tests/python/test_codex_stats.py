"""Codex session stats take each rollout's date from its directory names —
which on Windows arrive from os.walk with backslashes."""

import json
import os
import shutil
import tempfile
import time
import unittest
from unittest import mock

import _support  # noqa: F401  (sys.path)
from aiusage.providers import codex_stats
from aiusage.providers.codex_stats import get_codex_stats


def _line(**fields):
    return json.dumps(fields, separators=(",", ":")) + "\n"


def _write_rollout(day, name, model="gpt-5.6-sol", effort="high", tokens=(100, 40, 20, 5, 120)):
    os.makedirs(day, exist_ok=True)
    with open(os.path.join(day, name), "w", encoding="utf-8") as fh:
        fh.write(_line(timestamp="2026-09-10T10:00:00.000Z", type="session_meta"))
        fh.write(_line(timestamp="2026-09-10T10:05:00.000Z", type="event_msg", payload={"type": "user_message"}))
        fh.write(
            _line(
                timestamp="2026-09-10T10:06:00.000Z",
                type="event_msg",
                payload={
                    "type": "token_count",
                    "info": {
                        "total_token_usage": dict(
                            zip(("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"), tokens)
                        )
                    },
                },
            )
        )


class CodexStatsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        day = os.path.join(self.tmp, "sessions", "2026", "09", "10")
        os.makedirs(day)
        with open(os.path.join(day, "rollout-a.jsonl"), "w", encoding="utf-8") as fh:
            fh.write(_line(timestamp="2026-09-10T10:00:00.000Z", type="session_meta"))
            fh.write(_line(timestamp="2026-09-10T10:05:00.000Z", type="event_msg", payload={"type": "user_message"}))

    def test_dates_come_from_the_directory_names(self):
        env = {
            "CODEX_SESSIONS_DIR": os.path.join(self.tmp, "sessions"),
            "CODEX_CONFIG_FILE": os.path.join(self.tmp, "missing.toml"),
            "XDG_CACHE_HOME": os.path.join(self.tmp, "cache"),
        }
        with mock.patch.dict(os.environ, env):
            stats = get_codex_stats()
        self.assertEqual([d["date"] for d in stats["dailyActivity"]], ["2026-09-10"])
        self.assertEqual(stats["totalSessions"], 1)
        self.assertEqual(stats["totalMessages"], 1)

    def test_rollout_aggregation_and_oversized_lines(self):
        sessions = os.path.join(self.tmp, "recorded")
        env = {
            "CODEX_SESSIONS_DIR": sessions,
            "CODEX_CONFIG_FILE": os.path.join(self.tmp, "missing.toml"),
            "XDG_CACHE_HOME": os.path.join(self.tmp, "recorded-cache"),
        }
        with mock.patch.dict(os.environ, env):
            self.assertEqual(get_codex_stats(), {})
            day = os.path.join(sessions, "2026", "07", "19")
            os.makedirs(day)
            for name, hour, model, effort, prompts, tools, usage in (
                ("a", "08", "gpt-5.6-sol", "high", 2, ["function_call", "custom_tool_call"], (100, 40, 20, 5, 120)),
                ("b", "10", "gpt-5.5", "medium", 1, [], (10, 0, 5, 0, 15)),
            ):
                events = [("session_meta", {"id": name}), ("turn_context", {"model": model, "effort": effort})]
                events += [("event_msg", {"type": "user_message", "message": "hi"})] * prompts
                events += [("response_item", {"type": tool}) for tool in tools]
                events.append(
                    (
                        "event_msg",
                        {
                            "type": "token_count",
                            "info": {
                                "model_context_window": 258400,
                                "last_token_usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2},
                                "total_token_usage": dict(
                                    zip(("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"), usage)
                                ),
                            },
                        },
                    )
                )
                with open(os.path.join(day, f"rollout-{name}.jsonl"), "w", encoding="utf-8") as fh:
                    for second, (kind, payload) in enumerate(events):
                        fh.write(_line(timestamp=f"2026-07-19T{hour}:00:{second:02d}.000Z", type=kind, payload=payload))
                    if name == "a":
                        fh.write(_line(timestamp="2026-07-19T09:00:00.000Z", type="event_msg", payload={"type": "task_complete"}))
            stats = get_codex_stats()
            for key, expected in {
                "totalSessions": 2,
                "totalMessages": 3,
                "totalToolCalls": 2,
                "totalTokens": 135,
                "firstSessionDate": "2026-07-19",
                "model": "gpt-5.5",
                "effortLevel": "medium",
            }.items():
                with self.subTest(field=key):
                    self.assertEqual(stats[key], expected)
            self.assertEqual(stats["modelUsage"]["gpt-5.6-sol"]["totalTokens"], 120)
            self.assertEqual(stats["modelUsage"]["gpt-5.6-sol"]["cachedInput"], 40)
            self.assertEqual(stats["modelUsage"]["gpt-5.5"]["sessions"], 1)
            self.assertEqual(stats["longestSession"]["duration"], 3600000)
            self.assertEqual(stats["dailyActivity"][0]["toolCallCount"], 2)
            with open(os.path.join(day, "rollout-c.jsonl"), "w", encoding="utf-8") as fh:
                fh.write(_line(timestamp="2026-07-19T11:00:00.000Z", type="turn_context", payload={"model": "gpt-5.4", "effort": "low"}))
                fh.write(
                    _line(
                        timestamp="2026-07-19T11:00:01.000Z",
                        type="response_item",
                        payload={"type": "function_call_output", "output": "x" * 2_000_000},
                    )
                )
                fh.write(
                    _line(
                        timestamp="2026-07-19T11:00:02.000Z",
                        type="event_msg",
                        payload={
                            "type": "token_count",
                            "info": {
                                "total_token_usage": {
                                    "input_tokens": 7,
                                    "cached_input_tokens": 0,
                                    "output_tokens": 3,
                                    "reasoning_output_tokens": 0,
                                    "total_tokens": 10,
                                }
                            },
                        },
                    )
                )
            shutil.rmtree(env["XDG_CACHE_HOME"])
            stats = get_codex_stats()
            self.assertEqual(stats["totalSessions"], 3)
            self.assertEqual(stats["modelUsage"]["gpt-5.4"]["totalTokens"], 10)
            self.assertEqual(get_codex_stats(), stats)


class CodexStatsCacheTest(unittest.TestCase):
    """Task-14: home-aware fingerprint cache for Codex local statistics."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.sessions = os.path.join(self.tmp, "sessions")
        self.cache = os.path.join(self.tmp, "cache")
        self.env = {
            "CODEX_SESSIONS_DIR": self.sessions,
            "CODEX_CONFIG_FILE": os.path.join(self.tmp, "missing.toml"),
            "XDG_CACHE_HOME": self.cache,
        }

    def _cache_files(self):
        directory = os.path.join(self.cache, "kde-ai-usage")
        return [name for name in os.listdir(directory) if name.startswith("codex-stats-")]

    def _cache_payload(self):
        directory = os.path.join(self.cache, "kde-ai-usage")
        name = self._cache_files()[0]
        with open(os.path.join(directory, name), encoding="utf-8") as fh:
            return json.load(fh)

    def test_warm_cache_skips_jsonl_scan(self):
        _write_rollout(os.path.join(self.sessions, "2026", "09", "10"), "rollout-a.jsonl")
        with mock.patch.dict(os.environ, self.env):
            cold = get_codex_stats()
            self.assertEqual(cold["totalSessions"], 1)
            calls = []

            def counting_scan(path, date):
                calls.append(path)
                return codex_stats._scan_rollout(path, date)

            with mock.patch("aiusage.providers.codex_stats._scan_rollout", side_effect=counting_scan):
                warm = get_codex_stats()
        self.assertEqual(calls, [])
        self.assertEqual(warm, cold)

    def test_changed_home_uses_separate_cache(self):
        home_a = os.path.join(self.tmp, "home-a")
        home_b = os.path.join(self.tmp, "home-b")
        _write_rollout(os.path.join(home_a, "sessions", "2026", "09", "10"), "rollout-a.jsonl")
        _write_rollout(os.path.join(home_b, "sessions", "2026", "09", "10"), "rollout-a.jsonl")
        _write_rollout(os.path.join(home_b, "sessions", "2026", "09", "11"), "rollout-b.jsonl")
        with mock.patch.dict(os.environ, {"CODEX_HOME": home_a, "XDG_CACHE_HOME": self.cache}):
            stats_a = get_codex_stats()
        with mock.patch.dict(os.environ, {"CODEX_HOME": home_b, "XDG_CACHE_HOME": self.cache}):
            stats_b = get_codex_stats()
        self.assertEqual(stats_a["totalSessions"], 1)
        self.assertEqual(stats_b["totalSessions"], 2)
        self.assertEqual(len(self._cache_files()), 2)

    def test_deleted_tree_returns_empty(self):
        _write_rollout(os.path.join(self.sessions, "2026", "09", "10"), "rollout-a.jsonl")
        with mock.patch.dict(os.environ, self.env):
            self.assertEqual(get_codex_stats()["totalSessions"], 1)
            shutil.rmtree(self.sessions)
            self.assertEqual(get_codex_stats(), {})

    def test_malformed_cache_recovers(self):
        _write_rollout(os.path.join(self.sessions, "2026", "09", "10"), "rollout-a.jsonl")
        with mock.patch.dict(os.environ, self.env):
            stats = get_codex_stats()
            directory = os.path.join(self.cache, "kde-ai-usage")
            name = self._cache_files()[0]
            with open(os.path.join(directory, name), "w", encoding="utf-8") as fh:
                fh.write("{not json")
            self.assertEqual(get_codex_stats(), stats)

    def test_changed_rollout_mtime_invalidates(self):
        day = os.path.join(self.sessions, "2026", "09", "10")
        rollout = os.path.join(day, "rollout-a.jsonl")
        _write_rollout(day, "rollout-a.jsonl")
        with mock.patch.dict(os.environ, self.env):
            first = get_codex_stats()
            self.assertEqual(first["totalSessions"], 1)
            future = time.time_ns() + 5_000_000_000
            os.utime(rollout, ns=(future, future))
            second = get_codex_stats()
            self.assertEqual(second["totalSessions"], 1)
            self.assertEqual(second["totalMessages"], 1)

    def test_deleted_rollout_invalidates_cache(self):
        day = os.path.join(self.sessions, "2026", "09", "10")
        _write_rollout(day, "rollout-a.jsonl")
        _write_rollout(day, "rollout-b.jsonl")
        with mock.patch.dict(os.environ, self.env):
            self.assertEqual(get_codex_stats()["totalSessions"], 2)
            os.unlink(os.path.join(day, "rollout-b.jsonl"))
            self.assertEqual(get_codex_stats()["totalSessions"], 1)

    def test_empty_tree_remains_cached_zero_stat(self):
        os.makedirs(self.sessions)
        with mock.patch.dict(os.environ, self.env):
            first = get_codex_stats()
            self.assertEqual(first["totalSessions"], 0)
            directory = os.path.join(self.cache, "kde-ai-usage")
            name = self._cache_files()[0]
            cache_path = os.path.join(directory, name)
            mtime_before = os.stat(cache_path).st_mtime_ns
            second = get_codex_stats()
            mtime_after = os.stat(cache_path).st_mtime_ns
        self.assertEqual(second, first)
        self.assertEqual(mtime_before, mtime_after)

    def test_cache_payload_has_no_paths(self):
        _write_rollout(os.path.join(self.sessions, "2026", "09", "10"), "rollout-a.jsonl")
        with mock.patch.dict(os.environ, self.env):
            get_codex_stats()
        payload = self._cache_payload()
        self.assertEqual(payload["version"], 2)
        self.assertIsInstance(payload["home"], str)
        self.assertIsInstance(payload["fingerprint"], str)
        self.assertIsInstance(payload["stats"], dict)
        raw = json.dumps(payload)
        self.assertNotIn(self.tmp, raw)
        self.assertNotIn("rollout-a", raw)


if __name__ == "__main__":
    unittest.main()
