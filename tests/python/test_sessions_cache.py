import sqlite3
import tempfile
import unittest
from unittest import mock

from _support import REPO  # noqa: F401
from aiusage import session_cache, session_manifest, sessions
from aiusage.session_index import SessionIndex
from aiusage.session_manifest import SessionManifest


def _row(title: str, activity: int, open_key: str = "") -> dict[str, str | int]:
    return {
        "provider": "test",
        "title": title,
        "sessionName": "Fixture",
        "state": "idle",
        "lastActivityAt": activity,
        "detail": "safe",
        "openKey": open_key,
    }


class SessionCacheIntegrationTest(unittest.TestCase):
    def _manifest(self, version: int) -> SessionManifest:
        return SessionManifest(f"manifest-{version}", version, version)

    def setUp(self):
        # The index reconciles per source. These tests describe one merged
        # listing, so they run with a single fake source whose collector is
        # whatever `_collect_all_sessions` is patched to at call time.
        source = mock.patch.object(sessions, "collect_source", lambda _id: sessions._collect_all_sessions()[0])
        source.start()
        self.addCleanup(source.stop)

    def test_repeated_queries_and_pages_reuse_cached_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = [_row("first", 2), _row("needle", 2), _row("last", 1)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[self._manifest(1)]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=(rows, True)) as collect,
            ):
                sessions.refresh_sessions()
                with mock.patch.object(sessions, "_collect_all_sessions", side_effect=AssertionError("cache miss")):
                    searched = sessions.collect_sessions("needle")
                    page = sessions.collect_sessions("", limit=1, offset=1)

        collect.assert_called_once()
        self.assertEqual([row["title"] for row in searched["sessions"]], ["needle"])
        self.assertEqual([row["title"] for row in page["sessions"]], ["needle"])
        self.assertEqual(page["total"], 3)

    def test_cached_query_exposes_sources_and_applies_one_source_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = [
                _row("codex", 3),
                _row("antigravity", 2),
                _row("opencode", 1),
            ]
            rows[0]["provider"] = "openai"
            rows[1]["provider"] = "antigravity"
            rows[2]["provider"] = "opencode"
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[self._manifest(1)]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=(rows, True)),
            ):
                sessions.refresh_sessions()
                result = sessions.collect_sessions("", source_ids=["openai"])

        self.assertEqual([row["provider"] for row in result["sessions"]], ["openai"])
        self.assertEqual(result["total"], 1)
        self.assertEqual(
            result["sources"],
            [
                {"id": "openai", "label": "Codex"},
                {"id": "opencode", "label": "OpenCode"},
                {"id": "antigravity", "label": "Antigravity"},
            ],
        )

    def test_manifest_change_refreshes_the_merged_listing(self):
        with tempfile.TemporaryDirectory() as directory:
            manifests = [self._manifest(1), self._manifest(2)]
            rows = [_row("old", 1)]
            refreshed = [_row("new", 2)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", side_effect=[[m] for m in manifests]),
                mock.patch.object(sessions, "_collect_all_sessions", side_effect=[(rows, True), (refreshed, True)]) as collect,
            ):
                sessions.refresh_sessions()
                result = sessions.refresh_sessions()

        self.assertEqual([row["title"] for row in result["sessions"]], ["new"])
        self.assertEqual(collect.call_count, 2)

    def test_cache_preserves_ties_and_valid_open_keys(self):
        key = sessions._open_key("claude", "session-id")
        rows = [_row("cline", 7), _row("claude", 7, key)]
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch("aiusage.config.cache_dir", return_value=directory),
            mock.patch.object(session_cache, "build_manifests", return_value=[self._manifest(1)]),
            mock.patch.object(sessions, "_collect_all_sessions", return_value=(rows, True)),
        ):
            result = sessions.refresh_sessions()

        self.assertEqual([row["title"] for row in result["sessions"]], ["cline", "claude"])
        self.assertEqual(result["sessions"][1]["openKey"], key)

    def _two_source_refresh(self, directory, version, claude_rows, antigravity_rows):
        """Run one refresh over two independently fingerprinted sources."""

        def collect_source(source_id):
            rows = claude_rows if source_id == "claude" else antigravity_rows
            if isinstance(rows, Exception):
                raise rows
            return rows

        manifests = [
            SessionManifest("claude", version if claude_rows is not None else 1, 1),
            SessionManifest("antigravity", version, 1),
        ]
        with (
            mock.patch("aiusage.config.cache_dir", return_value=directory),
            mock.patch.object(session_cache, "build_manifests", return_value=manifests),
            mock.patch.object(sessions, "collect_source", collect_source),
            mock.patch.object(sessions, "_collect_all_sessions", return_value=([], True)),
        ):
            return sessions.refresh_sessions()

    def test_a_broken_collector_keeps_its_own_rows_and_lets_the_others_update(self):
        with tempfile.TemporaryDirectory() as directory:
            claude_old = [dict(_row("claude old", 1), provider="claude")]
            antigravity_old = [dict(_row("antigravity old", 2), provider="antigravity")]
            antigravity_new = [dict(_row("antigravity new", 3), provider="antigravity")]

            self._two_source_refresh(directory, 1, claude_old, antigravity_old)
            result = self._two_source_refresh(directory, 2, OSError("unreadable store"), antigravity_new)
            retained = SessionIndex(f"{directory}/sessions.sqlite3").rows()

        titles = sorted(row["title"] for row in retained)
        # Claude could not be read, so its cached row survives untouched while
        # the healthy source still moves forward.
        self.assertEqual(titles, ["antigravity new", "claude old"])
        self.assertEqual([row["title"] for row in result["sessions"]], ["antigravity new", "claude old"])
        self.assertEqual(
            result["sources"],
            [{"id": "claude", "label": "Claude Code"}, {"id": "antigravity", "label": "Antigravity"}],
        )

    def test_an_unchanged_source_is_not_recollected_while_a_changed_one_is(self):
        with tempfile.TemporaryDirectory() as directory:
            claude_rows = [dict(_row("claude", 1), provider="claude")]
            antigravity_v1 = [dict(_row("antigravity v1", 2), provider="antigravity")]
            antigravity_v2 = [dict(_row("antigravity v2", 3), provider="antigravity")]

            self._two_source_refresh(directory, 1, claude_rows, antigravity_v1)
            # Claude's fingerprint is pinned to 1 by the helper, so only
            # antigravity looks changed on the second pass.
            result = self._two_source_refresh(
                directory,
                2,
                AssertionError("unchanged source was re-collected"),
                antigravity_v2,
            )

        self.assertEqual([row["title"] for row in result["sessions"]], ["antigravity v2", "claude"])

    def test_corrupt_cache_rebuilds(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = f"{directory}/sessions.sqlite3"
            rows = [_row("rebuilt", 1)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[self._manifest(1)]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=(rows, True)) as collect,
            ):
                sessions.refresh_sessions()
                with open(cache, "wb") as stream:
                    stream.write(b"not sqlite")
                sessions.refresh_sessions()

        self.assertEqual(collect.call_count, 2)

    def test_query_only_does_not_build_manifest_or_collectors(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", side_effect=AssertionError("query built manifest")),
                mock.patch.object(sessions, "_collect_all_sessions", side_effect=AssertionError("query collected")),
            ):
                result = sessions.collect_sessions("needle")

        self.assertEqual(result["sessions"], [])
        self.assertEqual(result["total"], 0)
        self.assertTrue(result["totalExact"])
        self.assertEqual(result["sources"], [])

    def test_cache_query_error_returns_schema_complete_empty_result(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch("aiusage.config.cache_dir", return_value=directory),
            mock.patch.object(SessionIndex, "query", side_effect=sqlite3.DatabaseError("broken cache")),
        ):
            result = sessions.collect_sessions("needle", limit=2, offset=3)

        self.assertEqual(result["sessions"], [])
        self.assertEqual(result["total"], 0)
        self.assertTrue(result["totalExact"])
        self.assertEqual(result["offset"], 3)
        self.assertEqual(result["limit"], 2)
        self.assertFalse(result["hasMore"])
        self.assertEqual(result["sources"], [])

    def test_unchanged_manifest_does_not_recollect_on_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = [_row("first", 2)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[self._manifest(1)]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=(rows, True)) as collect,
            ):
                sessions.refresh_sessions()
                with mock.patch.object(sessions, "_collect_all_sessions", side_effect=AssertionError("cache miss")):
                    result = sessions.refresh_sessions()

        collect.assert_called_once()
        self.assertEqual([row["title"] for row in result["sessions"]], ["first"])

    def test_manifest_does_not_use_opencode_cli_discovery(self):
        with mock.patch.object(
            session_manifest.opencode,
            "discover_database_paths",
            side_effect=AssertionError("cached manifest must not run opencode db path"),
        ):
            manifests = session_manifest.build_manifests()

        self.assertEqual(
            [manifest.source_id for manifest in manifests],
            list(sessions.SESSION_COLLECTORS),
        )


if __name__ == "__main__":
    unittest.main()
