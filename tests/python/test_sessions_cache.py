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

    def test_repeated_queries_and_pages_reuse_cached_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = [_row("first", 2), _row("needle", 2), _row("last", 1)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifest", return_value=self._manifest(1)),
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
                mock.patch.object(session_cache, "build_manifest", return_value=self._manifest(1)),
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
                mock.patch.object(session_cache, "build_manifest", side_effect=manifests),
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
            mock.patch.object(session_cache, "build_manifest", return_value=self._manifest(1)),
            mock.patch.object(sessions, "_collect_all_sessions", return_value=(rows, True)),
        ):
            result = sessions.refresh_sessions()

        self.assertEqual([row["title"] for row in result["sessions"]], ["cline", "claude"])
        self.assertEqual(result["sessions"][1]["openKey"], key)

    def test_failed_refresh_returns_direct_rows_without_overwriting_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            old_rows = [_row("old", 1)]
            current_rows = [_row("current", 2)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifest", side_effect=[self._manifest(1), self._manifest(2)]),
                mock.patch.object(sessions, "_collect_all_sessions", side_effect=[(old_rows, True), (current_rows, False)]),
            ):
                sessions.refresh_sessions()
                result = sessions.refresh_sessions()
                retained = SessionIndex(f"{directory}/sessions.sqlite3").rows()

        self.assertEqual([row["title"] for row in result["sessions"]], ["current"])
        self.assertEqual([row["title"] for row in retained], ["old"])

    def test_incomplete_refresh_derives_sources_from_direct_rows_without_private_data(self):
        with tempfile.TemporaryDirectory() as directory:
            old_rows = [_row("old", 1)]
            old_rows[0]["provider"] = "claude"
            current_rows = [_row("current", 2)]
            current_rows[0]["provider"] = "antigravity"
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifest", side_effect=[self._manifest(1), self._manifest(2)]),
                mock.patch.object(sessions, "_collect_all_sessions", side_effect=[(old_rows, True), (current_rows, False)]),
            ):
                sessions.refresh_sessions()
                result = sessions.refresh_sessions()
                retained = SessionIndex(f"{directory}/sessions.sqlite3").rows()

        self.assertEqual([row["title"] for row in result["sessions"]], ["current"])
        self.assertEqual([row["title"] for row in retained], ["old"])
        self.assertEqual(result["sources"], [{"id": "antigravity", "label": "Antigravity"}])

    def test_corrupt_cache_rebuilds(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = f"{directory}/sessions.sqlite3"
            rows = [_row("rebuilt", 1)]
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifest", return_value=self._manifest(1)),
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
                mock.patch.object(session_cache, "build_manifest", side_effect=AssertionError("query built manifest")),
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
                mock.patch.object(session_cache, "build_manifest", return_value=self._manifest(1)),
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
            manifest = session_manifest.build_manifest()

        self.assertTrue(manifest.source_id)


if __name__ == "__main__":
    unittest.main()
