import sqlite3
import tempfile
import unittest
from unittest import mock

from _support import REPO  # noqa: F401
from aiusage import session_cache, sessions
from aiusage.session_index import SessionIndex
from aiusage.session_manifest import SessionManifest


def _row(title: str, provider: str, activity: int) -> dict[str, str | int]:
    return {
        "provider": provider,
        "title": title,
        "sessionName": "Fixture",
        "state": "idle",
        "lastActivityAt": activity,
        "detail": "safe",
        "openKey": "",
    }


class SessionCacheFreshnessTest(unittest.TestCase):
    def test_query_reports_no_cache_without_building_or_collecting(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", side_effect=AssertionError("query scanned manifests")),
                mock.patch.object(sessions, "_collect_all_sessions", side_effect=AssertionError("query collected")),
            ):
                result = sessions.collect_sessions()

        self.assertEqual(result["cacheStatus"], "no-cache")
        self.assertIsNone(result["cacheAgeSeconds"])
        self.assertFalse(result["totalExact"])

    def test_manual_refresh_reports_successful_empty_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[SessionManifest("claude", 1, 1)]),
                mock.patch.object(sessions, "collect_source", return_value=[]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=([], True)),
            ):
                result = sessions.refresh_sessions()

        self.assertEqual(result["sessions"], [])
        self.assertEqual(result["cacheStatus"], "empty")
        self.assertEqual(result["refreshStatus"], "refreshed")

    def test_expired_cache_reports_age_without_scanning_on_query(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[SessionManifest("claude", 1, 1)]),
                mock.patch.object(sessions, "collect_source", return_value=[_row("cached", "claude", 1)]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=([_row("cached", "claude", 1)], True)),
            ):
                sessions.refresh_sessions()
                with (
                    mock.patch.object(session_cache.SessionCache, "_cache_age", return_value=601),
                    mock.patch.object(session_cache, "build_manifests", side_effect=AssertionError("query scanned manifests")),
                    mock.patch.object(sessions, "collect_source", side_effect=AssertionError("query collected")),
                ):
                    result = sessions.collect_sessions()

        self.assertEqual(result["cacheStatus"], "stale")
        self.assertEqual(result["cacheAgeSeconds"], 601)
        self.assertEqual([row["title"] for row in result["sessions"]], ["cached"])

    def test_failed_first_refresh_is_not_a_successful_empty_result(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[SessionManifest("claude", 1, 1)]),
                mock.patch.object(sessions, "collect_source", side_effect=OSError("unavailable")),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=([], False)),
            ):
                result = sessions.refresh_sessions()

        self.assertEqual(result["sessions"], [])
        self.assertEqual(result["refreshStatus"], "incomplete")
        self.assertEqual(result["cacheStatus"], "no-cache")

    def test_source_removal_updates_rows_descriptors_and_count(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(session_cache, "build_manifests", return_value=[SessionManifest("claude", 1, 1)]),
                mock.patch.object(sessions, "collect_source", return_value=[_row("old", "claude", 1)]),
                mock.patch.object(sessions, "_collect_all_sessions", return_value=([], True)),
            ):
                sessions.refresh_sessions()
                with (
                    mock.patch.object(session_cache, "build_manifests", return_value=[SessionManifest("opencode", 1, 1)]),
                    mock.patch.object(sessions, "collect_source", return_value=[_row("new", "opencode", 2)]),
                ):
                    result = sessions.refresh_sessions()

        self.assertEqual(result["refreshStatus"], "removed-source")
        self.assertEqual(result["removedSourceCount"], 1)
        self.assertEqual([source["id"] for source in result["sources"]], ["opencode"])
        self.assertEqual([row["title"] for row in result["sessions"]], ["new"])

    def test_sqlite_query_failure_has_unknown_count_not_false_exact_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            SessionIndex(f"{directory}/sessions.sqlite3").reconcile([SessionManifest("claude", 1, 1)], lambda _source: [_row("cached", "claude", 1)])
            with (
                mock.patch("aiusage.config.cache_dir", return_value=directory),
                mock.patch.object(SessionIndex, "query", side_effect=sqlite3.DatabaseError("broken cache")),
            ):
                result = sessions.collect_sessions(limit=2, offset=3)

        self.assertFalse(result["totalExact"])
        self.assertEqual(result["cacheStatus"], "failed")
        self.assertFalse(result["hasMore"])
        self.assertEqual(result["offset"], 3)


if __name__ == "__main__":
    unittest.main()
