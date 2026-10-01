"""Synthetic Junie 3419.22 events; no account or paid request is needed."""

import builtins
import json
import os
import subprocess
from pathlib import Path
from unittest import mock

from _support import IsolatedHomeTest, fixture
from aiusage import detect, session_manifest, sessions
from aiusage.normalize.junie import normalize_junie
from aiusage.providers import junie

NOW = 1790841600
SID = "session-261001-080000-test"


def event(at=NOW, **overrides):
    usage = {"model": "gemini-test", "inputTokens": 100, "outputTokens": 20, "cacheInputTokens": 40, "cacheCreateTokens": 10}
    usage.update(overrides)
    return {
        "kind": "SessionA2uxEvent",
        "timestampMs": int(at * 1000),
        "event": {"state": "IN_PROGRESS", "agentEvent": {"kind": "LlmResponseMetadataEvent", "modelUsage": [usage]}},
    }


class JunieTest(IsolatedHomeTest):
    def seed(self, events=None):
        self.write(
            ".junie/sessions/index.jsonl",
            {
                "sessionId": SID,
                "createdAt": (NOW - 86400) * 1000,
                "updatedAt": NOW * 1000,
                "projectDir": str(self.home / "workspace"),
                "taskName": "A Junie task",
            },
        )
        return self.write(f".junie/sessions/{SID}/events.jsonl", "\n".join(json.dumps(row) for row in (events or [event()])))

    def normalized(self):
        return normalize_junie({"id": "junie", "now": NOW, "inputs": {"usage": junie.usage_snapshot()}})

    def test_additive_events_and_cache_tokens_are_counted_once(self):
        self.seed([event(), event(model="second-model")])
        # A summary is metadata, not another usage ledger. Subagent events are
        # already in the parent stream, so standalone transcripts are ignored.
        self.write(
            f".junie/sessions/{SID}/summary.json",
            {
                "sessionId": SID,
                "updatedAt": NOW * 1000,
                "mainAgent": {"modelUsage": [{"inputTokens": 999999}]},
            },
        )
        self.write(f".junie/sessions/{SID}/subagents/one/events.jsonl", event())
        stats = self.normalized()["details"]["stats"]
        self.assertEqual(stats["totalTokens"], 340)
        self.assertEqual(stats["totalCachedTokens"], 100)
        self.assertEqual(len(stats["models"]), 2)
        self.assertEqual(stats["totalSessions"], 1)

    def test_usage_dates_follow_events_across_days_and_periods(self):
        self.seed([event(NOW - 40 * 86400), event(NOW)])
        stats = self.normalized()["details"]["stats"]
        self.assertEqual([row["total"] for row in stats["dailyTokens"]], [170, 170])
        self.assertEqual(next(row["tokens"] for row in stats["periods"] if row["key"] == "7d"), 170)
        self.assertEqual(next(row["tokens"] for row in stats["periods"] if row["key"] == "all"), 340)

    def test_top_model_sums_requests_instead_of_selecting_the_largest_request(self):
        self.seed([event(model="single-large-request", inputTokens=150), event(), event()])
        self.assertEqual(self.normalized()["details"]["stats"]["favoriteModel"], "junie/gemini-test")

    def test_malformed_sessions_and_usage_are_unavailable(self):
        for value in (42, {}, [None], [{"id": SID, "usage": 42}], [{"id": SID, "usage": {}}]):
            with self.subTest(value=value):
                result = normalize_junie({"id": "junie", "now": NOW, "inputs": {"usage": {"sessions": value}}})
                self.assertFalse(result["ok"])

    def test_unknown_cost_units_never_become_dollars_or_quota(self):
        self.seed([event(cost=7.5)])
        result = self.normalized()
        self.assertTrue(result["details"]["untested"])
        self.assertEqual(result["details"]["stats"]["costStatus"], "unavailable")
        self.assertEqual(result["details"]["stats"]["totalCostUSD"], 0)
        self.assertEqual(result["historyValues"], {})
        self.assertEqual(result["chartWindows"], [])
        self.assertTrue(all(not row["showMeter"] for row in result["quotaWindows"]))
        self.assertFalse(result["summary"]["hasChart"])
        self.assertNotIn("costUSD", sessions._junie_entries()[0])

    def test_malformed_and_partial_events_keep_valid_data(self):
        path = self.seed([event(), event(inputTokens=-1, outputTokens=True, cacheInputTokens=None, cacheCreateTokens=3)])
        with path.open("a", encoding="utf-8") as stream:
            stream.write('\nnull\n[]\n{"kind": "SessionA2uxEvent", "event": []}\n{"incomplete":')
        result = self.normalized()
        self.assertEqual(result["details"]["stats"]["totalTokens"], 173)
        self.assertTrue(result["details"]["tokensPartial"])

    def test_missing_counts_are_unavailable_not_zero_usage(self):
        self.seed([event(inputTokens=None, outputTokens=None, cacheInputTokens=None, cacheCreateTokens=None)])
        result = self.normalized()
        self.assertFalse(result["ok"])
        self.assertEqual(result["details"]["sessionCount"], 1)
        self.assertNotIn("tokens", sessions._junie_entries()[0])

    def test_unrelated_text_and_usage_shapes_are_ignored(self):
        self.seed([{"kind": "SystemMessageEvent", "timestampMs": NOW * 1000, "inputTokens": 99999, "text": "private-prompt"}])
        self.assertFalse(self.normalized()["details"]["stats"]["available"])
        self.assertNotIn("private-prompt", json.dumps(sessions._junie_entries()))

    def test_sessions_are_redacted_searchable_and_resumable(self):
        self.seed([event(), {"kind": "TaskState", "state": "FAILED", "timestampMs": NOW * 1000}])
        row = sessions._junie_entries()[0]
        self.assertEqual((row["provider"], row["title"], row["detail"], row["tokens"]), ("junie", "A Junie task", "workspace", 170))
        self.assertEqual(row["state"], "idle")
        self.assertNotIn(str(self.home), json.dumps(row))
        self.assertNotIn(SID, json.dumps(row))
        self.assertTrue(row["openKey"])
        target = sessions._junie_targets()[0]
        self.assertEqual(target["id"], SID)
        self.assertEqual(sessions.SESSION_COLLECTORS["junie"], "_junie_entries")

    def test_custom_home_and_unindexed_sessions(self):
        self.write(f"custom/sessions/{SID}/events.jsonl", event())
        with mock.patch.dict(os.environ, {"JUNIE_HOME": str(self.home / "custom")}):
            self.assertEqual(junie.read_sessions()[0]["id"], SID)

    def test_index_cannot_redirect_reader_outside_session_directory(self):
        self.write(".junie/sessions/index.jsonl", {"sessionId": "../../escape", "updatedAt": NOW * 1000})
        self.assertEqual(junie.read_sessions(), [])

    def test_appends_invalidate_parser_and_session_manifest(self):
        path = self.seed()
        before = {row.source_id: row for row in session_manifest.build_manifests()}["junie"]
        self.assertEqual(self.normalized()["details"]["stats"]["totalTokens"], 170)
        with path.open("a", encoding="utf-8") as stream:
            stream.write("\n" + json.dumps(event()))
        after = {row.source_id: row for row in session_manifest.build_manifests()}["junie"]
        self.assertNotEqual(before, after)
        self.assertEqual(self.normalized()["details"]["stats"]["totalTokens"], 340)

    def test_collection_does_not_launch_cli_or_read_credentials(self):
        self.seed()
        self.write(".junie/settings.json", {"private-key": "do-not-read"})
        junie._read_events.cache_clear()
        open_file = Path.open

        def read_metadata(path, *args, **kwargs):
            self.assertIn(path.name, ("index.jsonl", "summary.json", "events.jsonl"))
            return open_file(path, *args, **kwargs)

        with (
            mock.patch.object(subprocess, "run", side_effect=AssertionError("launched CLI")),
            mock.patch.object(Path, "open", read_metadata),
        ):
            self.assertTrue(self.normalized()["ok"])
        self.assertNotIn("do-not-read", json.dumps(self.normalized()))

    def test_detection_is_stat_only(self):
        with (
            mock.patch.object(detect.shutil, "which", side_effect=lambda name, **kwargs: "/bin/junie" if name == "junie" else None),
            mock.patch.object(builtins, "open", side_effect=AssertionError("read file")),
            mock.patch.object(subprocess, "run", side_effect=AssertionError("launched CLI")),
        ):
            self.assertIn("junie", detect.detect_providers())

    def test_empty_and_success_fixtures(self):
        self.assertTrue(fixture("junie-success")["ok"])
        for name in ("junie-missing-data", "junie-malformed"):
            self.assertFalse(fixture(name)["ok"])
