import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from _support import REPO  # noqa: F401
from aiusage.normalize.kiro import normalize_kiro
from aiusage.providers import kiro_stats as reader
from aiusage.stats import kiro_stats


def _turn(end, secs, requests, tools, credits, model="auto"):
    return {
        "end_timestamp": end,
        "turn_duration": {"secs": secs, "nanos": 0},
        "total_request_count": requests,
        "builtin_tool_uses": tools,
        "input_token_count": 0,
        "output_token_count": 0,
        "model": model,
        "metering_usage": [{"value": credits / requests, "unit": "credit"} for _ in range(requests)],
    }


class KiroStatsTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.agent = tempfile.TemporaryDirectory()
        self.cache = tempfile.TemporaryDirectory()
        for d in (self.home, self.agent, self.cache):
            self.addCleanup(d.cleanup)
        patches = [
            mock.patch.dict(os.environ, {"KIRO_HOME": self.home.name, "KIRO_AGENT_DIR": self.agent.name}),
            mock.patch("aiusage.paths.cache_home", return_value=self.cache.name),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _cli(self, name, turns, created="2026-09-18T11:00:00Z", updated="2026-09-18T11:30:00Z"):
        path = Path(self.home.name) / "sessions" / "cli" / f"{name}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        state = {"conversation_metadata": {"user_turn_metadatas": turns}}
        path.write_text(json.dumps({"created_at": created, "updated_at": updated, "session_state": state}), encoding="utf-8")

    def _ide(self, workspace, name, start_ms, end_ms, model="claude-sonnet-4.5"):
        path = Path(self.agent.name) / workspace / f"{name}.chat"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"chat": [], "metadata": {"modelId": model, "startTime": start_ms, "endTime": end_ms}}), encoding="utf-8")

    def test_nothing_on_disk_is_unavailable(self):
        self.assertEqual(reader.get_kiro_stats(), {})
        self.assertEqual(kiro_stats({}, time.time()), {"available": False})

    def test_cli_turns_count_requests_tools_and_credits(self):
        self._cli("a", [_turn("2026-09-18T11:10:00Z", 60, 3, 2, 0.3), _turn("2026-09-18T11:20:00Z", 30, 2, 1, 0.2, "claude-sonnet-4.5")])
        # A session that never finished a turn is not activity.
        self._cli("b", [])
        s = kiro_stats(reader.get_kiro_stats(), time.time())
        self.assertEqual(s["totalSessions"], 1)
        self.assertEqual(s["totalMessages"], 2)
        self.assertEqual(s["totalRequests"], 5)
        self.assertEqual(s["totalToolCalls"], 3)
        self.assertAlmostEqual(s["totalCredits"], 0.5)
        self.assertEqual(s["favoriteModel"], "claude-sonnet-4.5")
        self.assertEqual(s["dailyUnit"], "requests")
        self.assertEqual(s["totalTokens"], 0)
        self.assertEqual(sum(s["hourCounts"]), 2)

    def test_ide_runs_group_into_sessions_by_gap(self):
        base = 1_776_171_381_000
        self._ide("ws1", "r1", base, base + 10_000)
        self._ide("ws1", "r2", base + 60_000, base + 70_000)
        # More than 30 minutes later: a new session.
        self._ide("ws1", "r3", base + 3 * 3600_000, base + 3 * 3600_000 + 5_000)
        s = kiro_stats(reader.get_kiro_stats(), time.time())
        self.assertEqual(s["totalSessions"], 2)
        self.assertEqual(s["totalMessages"], 3)
        self.assertEqual(s["totalRequests"], 3)

    def test_second_read_comes_from_the_cache(self):
        self._cli("a", [_turn("2026-09-18T11:10:00Z", 60, 1, 0, 0.1)])
        first = reader.get_kiro_stats()
        with mock.patch.object(reader, "_cli_sessions", side_effect=AssertionError("rescanned")):
            self.assertEqual(reader.get_kiro_stats(), first)

    def test_stats_survive_no_login(self):
        self._cli("a", [_turn("2026-09-18T11:10:00Z", 60, 1, 0, 0.1)])
        r = normalize_kiro({"now": time.time(), "inputs": {"usage": {}, "stats": reader.get_kiro_stats()}})
        self.assertTrue(r["details"]["stats"]["available"])


if __name__ == "__main__":
    unittest.main()
