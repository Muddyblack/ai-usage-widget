import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from _support import REPO  # noqa: F401
from aiusage.normalize.antigravity import normalize_antigravity
from aiusage.providers import antigravity_stats as reader
from aiusage.stats import antigravity_stats

_CLI_ID = "11111111-1111-4111-8111-111111111111"
_IDE_ID = "22222222-2222-4222-8222-222222222222"


def _row(kind, at, **extra):
    return json.dumps({"step_index": 0, "source": "MODEL", "type": kind, "status": "DONE", "created_at": at, **extra})


class AntigravityStatsTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.cache = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        self.addCleanup(self.cache.cleanup)
        patches = [
            mock.patch.dict(os.environ, {"ANTIGRAVITY_HOME": self.home.name}),
            mock.patch("aiusage.paths.cache_home", return_value=self.cache.name),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _cli(self, session_id, rows):
        path = Path(self.home.name) / "antigravity-cli" / "brain" / session_id / ".system_generated" / "logs" / "transcript.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(rows) + "\n", encoding="utf-8")

    def _ide(self, session_id, stamp):
        path = Path(self.home.name) / "antigravity" / "brain" / session_id / "task.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("# Task\n", encoding="utf-8")
        os.utime(path, (stamp, stamp))

    def test_nothing_on_disk_is_unavailable(self):
        self.assertEqual(reader.get_antigravity_stats(), {})
        self.assertEqual(antigravity_stats({}, time.time()), {"available": False})

    def test_transcript_tallies_messages_tools_searches_and_tokens(self):
        self._cli(
            _CLI_ID,
            [
                _row("USER_INPUT", "2026-06-04T21:00:00Z", source="USER_EXPLICIT", content="hi"),
                _row("PLANNER_RESPONSE", "2026-06-04T21:00:05Z", input_tokens=100, output_tokens=20, cache_read_tokens=50),
                _row("VIEW_FILE", "2026-06-04T21:00:06Z"),
                _row("SEARCH_WEB", "2026-06-04T21:00:07Z"),
                _row("USER_INPUT", "2026-06-04T21:30:00Z", source="USER_EXPLICIT", content="more"),
                "not json",
            ],
        )
        self._ide(_IDE_ID, 1_780_000_000)

        raw = reader.get_antigravity_stats()
        s = antigravity_stats(raw, time.time())
        self.assertTrue(s["available"])
        self.assertEqual(s["totalSessions"], 2)
        self.assertEqual(s["totalMessages"], 2)
        self.assertEqual(s["totalToolCalls"], 2)
        self.assertEqual(s["totalWebSearches"], 1)
        self.assertEqual(s["totalTokens"], 120)
        self.assertEqual(s["totalCachedTokens"], 50)
        self.assertEqual(s["longestSessionMs"], 30 * 60 * 1000)
        self.assertEqual(s["dailyUnit"], "messages")
        self.assertEqual(len(s["hourCounts"]), 24)
        self.assertEqual(sum(s["hourCounts"]), 2)

    def test_editor_conversation_the_cli_logged_counts_once(self):
        self._cli(_CLI_ID, [_row("USER_INPUT", "2026-06-04T21:00:00Z")])
        self._ide(_CLI_ID, 1_780_000_000)
        self.assertEqual(reader.get_antigravity_stats()["totalSessions"], 1)

    def test_second_read_comes_from_the_cache(self):
        self._cli(_CLI_ID, [_row("USER_INPUT", "2026-06-04T21:00:00Z")])
        first = reader.get_antigravity_stats()
        with mock.patch.object(reader, "_scan", side_effect=AssertionError("rescanned")):
            self.assertEqual(reader.get_antigravity_stats(), first)

    def test_stats_survive_the_ide_not_running(self):
        self._cli(_CLI_ID, [_row("USER_INPUT", "2026-06-04T21:00:00Z")])
        raw = {"now": time.time(), "inputs": {"usage": {"error": "Antigravity is not running"}, "stats": reader.get_antigravity_stats()}}
        self.assertTrue(normalize_antigravity(raw)["details"]["stats"]["available"])


if __name__ == "__main__":
    unittest.main()
