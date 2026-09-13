"""Codex session stats take each rollout's date from its directory names —
which on Windows arrive from os.walk with backslashes."""

import json
import os
import shutil
import tempfile
import unittest
from unittest import mock

import _support  # noqa: F401  (sys.path)
from aiusage.providers.codex_stats import get_codex_stats


def _line(**fields):
    return json.dumps(fields, separators=(",", ":")) + "\n"


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


if __name__ == "__main__":
    unittest.main()
