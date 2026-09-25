"""Grok local discovery: one fingerprinted walk serves every local view.

The signals reader, the summary reader, the legacy entry reader, and the resume
targets used to walk ``~/.grok/sessions`` independently. They now share one
memoized discovery pass, guarded by token/team identity and a short TTL, so an
unchanged store is walked once while a changed account or store re-reads.
"""

import json
import os
import unittest
from unittest import mock

from _support import IsolatedHomeTest  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import sessions
from aiusage.http import HttpResult
from aiusage.providers import grok


def _write_summary(root, workspace, session_id, title=None, usage=None, cwd="/mnt/projects/demo"):
    directory = os.path.join(root, "sessions", workspace, session_id)
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "summary.json"), "w", encoding="utf-8") as stream:
        json.dump(
            {
                "info": {"id": session_id, "cwd": cwd},
                "generated_title": title or f"title {session_id}",
                "current_model_id": "grok-4.6",
                "last_active_at": "2026-09-16T10:33:33Z",
            },
            stream,
        )
    if usage is not None:
        with open(os.path.join(directory, "updates.jsonl"), "w", encoding="utf-8") as stream:
            for totals in usage:
                stream.write(json.dumps({"method": "x", "params": {"update": {"usage": totals}}}) + "\n")
    return directory


def _write_signals(root, workspace, session_id, models=None, tokens=1000, tool_calls=4):
    directory = os.path.join(root, "sessions", workspace, session_id)
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "signals.json"), "w", encoding="utf-8") as stream:
        json.dump(
            {
                "modelsUsed": models or ["grok-4.6"],
                "contextTokensUsed": tokens,
                "toolCallCount": tool_calls,
                "sessionDurationSeconds": 120,
            },
            stream,
        )
    return directory


class GrokDiscoveryTest(IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        self.root = os.path.join(self.home, "grok")
        grok.reset_discovery_cache()
        self.addCleanup(grok.reset_discovery_cache)

    def _counting_walk(self):
        calls = []
        real = grok._walk_sessions

        def counting(*args, **kwargs):
            calls.append(1)
            return real(*args, **kwargs)

        return calls, mock.patch.object(grok, "_walk_sessions", side_effect=counting)

    def test_one_walk_serves_all_local_views(self):
        _write_summary(self.root, "%2Fmnt%2Fprojects%2Fdemo", "sess-a", usage=[{"inputTokens": 10, "outputTokens": 1}])
        _write_signals(self.root, "%2Fold", "sess-b")
        calls, patched = self._counting_walk()
        with mock.patch.object(sessions, "grok_home", return_value=self.root), mock.patch.object(grok, "grok_home", return_value=self.root), patched:
            entries = sessions._grok_entries(include_all=True)
            targets = sessions._grok_targets()
            stats = grok._grok_local_stats()
        self.assertEqual(len(calls), 1)
        self.assertTrue(entries and targets)
        self.assertEqual(stats["sessionCount"], 1)

    def test_changed_identity_cannot_reuse_discovery(self):
        _write_summary(self.root, "%2Fw", "sess-a")
        directory = os.path.join(self.root, "sessions")
        calls, patched = self._counting_walk()
        with patched:
            grok.discover_sessions(directory, identity="team-a")
            grok.discover_sessions(directory, identity="team-a")
            grok.discover_sessions(directory, identity="team-b")
        self.assertEqual(len(calls), 2)

    def test_discovery_cache_expires_after_ttl(self):
        _write_summary(self.root, "%2Fw", "sess-a")
        directory = os.path.join(self.root, "sessions")
        calls, patched = self._counting_walk()
        with patched:
            grok.discover_sessions(directory, identity="x", now=1000.0)
            grok.discover_sessions(directory, identity="x", now=1010.0)
            grok.discover_sessions(directory, identity="x", now=1031.0)
        self.assertEqual(len(calls), 2)

    def test_changed_signal_content_is_read_fresh(self):
        _write_signals(self.root, "%2Fw", "sess-a", models=["grok-1"])
        with mock.patch.object(sessions, "grok_home", return_value=self.root):
            first = sessions._grok_entries(include_all=True)
            _write_signals(self.root, "%2Fw", "sess-a", models=["grok-2"])
            grok.reset_discovery_cache()
            second = sessions._grok_entries(include_all=True)
        self.assertIn("grok-1", first[0]["detail"])
        self.assertIn("grok-2", second[0]["detail"])

    def test_added_session_appears_after_ttl(self):
        _write_signals(self.root, "%2Fw", "sess-a")
        with mock.patch.object(sessions, "grok_home", return_value=self.root):
            self.assertEqual(len(sessions._grok_targets()), 1)
            _write_signals(self.root, "%2Fw", "sess-b")
            grok.reset_discovery_cache()
            self.assertEqual(len(sessions._grok_targets()), 2)

    def test_malformed_signal_is_skipped(self):
        _write_signals(self.root, "%2Fw", "sess-a")
        directory = os.path.join(self.root, "sessions", "%2Fw", "sess-b")
        os.makedirs(directory)
        with open(os.path.join(directory, "signals.json"), "w", encoding="utf-8") as stream:
            stream.write("{not json")
        grok.reset_discovery_cache()
        with mock.patch.object(sessions, "grok_home", return_value=self.root):
            entries = sessions._grok_entries(include_all=True)
        self.assertEqual([e["sessionName"] for e in entries], ["Grok CLI"] * 1)

    def test_resume_targets_decode_the_workspace_and_prefer_summary(self):
        _write_summary(self.root, "%2Fmnt%2Fprojects%2Fdemo", "sess-a")
        _write_signals(self.root, "%2Fmnt%2Fprojects%2Fdemo", "sess-a")
        grok.reset_discovery_cache()
        with mock.patch.object(sessions, "grok_home", return_value=self.root):
            targets = sessions._grok_targets()
        self.assertEqual(len(targets), 1)
        self.assertEqual(targets[0]["provider"], "grok")
        self.assertEqual(targets[0]["id"], "sess-a")
        self.assertEqual(targets[0]["cwd"], "/mnt/projects/demo")

    def test_summary_and_signals_layouts_coexist(self):
        _write_summary(self.root, "%2Fw", "summary-session", title="Summary title", usage=[{"inputTokens": 5, "outputTokens": 1}])
        _write_signals(self.root, "%2Fw", "signals-session")
        grok.reset_discovery_cache()
        with mock.patch.object(sessions, "grok_home", return_value=self.root):
            entries = sessions._grok_entries(include_all=True)
        titles = sorted(e["title"] for e in entries)
        self.assertIn("Summary title", titles)
        self.assertEqual(len(entries), 2)


class GrokAccountIdentityTest(IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        grok.reset_discovery_cache()
        self.addCleanup(grok.reset_discovery_cache)

    def test_identity_changes_with_the_token_or_team(self):
        self.write(
            ".grok/auth.json",
            {
                "one": {"key": "tok-a", "team_id": "team-a", "user_id": "user-a", "create_time": "1"},
            },
        )
        first = grok.account_identity()
        self.write(
            ".grok/auth.json",
            {
                "one": {"key": "tok-b", "team_id": "team-b", "user_id": "user-b", "create_time": "2"},
            },
        )
        self.assertNotEqual(first, grok.account_identity())

    def test_remote_billing_error_semantics_are_unchanged(self):
        with mock.patch("aiusage.providers.grok.fetch_json", return_value=HttpResult(401, "")):
            credits, billing, error = grok._grok_billing_calls("tok", grok.CLIENT_VER)
        self.assertEqual((credits, billing), ({}, {}))
        self.assertEqual(error, "Grok auth expired — run grok --oauth")
        with mock.patch("aiusage.providers.grok.fetch_json", return_value=HttpResult(503, "")):
            credits, billing, error = grok._grok_billing_calls("tok", grok.CLIENT_VER)
        self.assertEqual(error, "Billing HTTP 503")

    def test_free_tier_window_is_retained_at_24_hours(self):
        now = 2_000_000_000.0
        recent = {"ts": "2026-09-16T10:33:33Z", "used": "21", "limit": "50"}
        old = {"ts": "2020-01-01T00:00:00Z", "used": "21", "limit": "50"}
        self.assertEqual(grok._resolve_free_usage(recent, 1_758_012_813.0), recent)
        self.assertEqual(grok._resolve_free_usage(old, now), {})


if __name__ == "__main__":
    unittest.main()
