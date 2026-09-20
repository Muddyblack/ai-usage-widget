import contextlib
import io
import json
import unittest
from unittest import mock

from _support import REPO, IsolatedHomeTest  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import __main__ as backend
from aiusage import sessions


def _entry(title: str, activity: int, *, provider: str = "test", open_key: str = ""):
    return {
        "provider": provider,
        "title": title,
        "sessionName": "Test",
        "state": "idle",
        "lastActivityAt": activity,
        "detail": "safe detail",
        "openKey": open_key,
    }


def _empty_collectors() -> contextlib.ExitStack:
    patches = contextlib.ExitStack()
    for name in (
        "_cline_entries",
        "_muse_entries",
        "_codex_entries",
        "_grok_entries",
        "_claude_entries",
        "_opencode_entries",
        "_antigravity_entries",
    ):
        patches.enter_context(mock.patch.object(sessions, name, return_value=[]))
    return patches


class SessionQueryTest(IsolatedHomeTest):
    def test_no_source_filter_adds_canonical_cached_source_descriptors(self):
        rows = [
            _entry("Codex preview", 5, provider="openai"),
            _entry("Antigravity preview", 4, provider="antigravity"),
            _entry("OpenCode preview", 3, provider="opencode"),
            _entry("Claude preview", 2, provider="claude"),
            _entry("Cline preview", 1, provider="cline"),
        ]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            result = sessions.collect_sessions("")

        self.assertEqual(result["total"], 5)
        self.assertEqual(len(result["sessions"]), 5)
        self.assertEqual(
            result["sources"],
            [
                {"id": "cline", "label": "Cline"},
                {"id": "openai", "label": "Codex"},
                {"id": "claude", "label": "Claude Code"},
                {"id": "opencode", "label": "OpenCode"},
                {"id": "antigravity", "label": "Antigravity"},
            ],
        )

    def test_one_source_filter_uses_empty_source_selection_as_all(self):
        rows = [
            _entry("Codex", 3, provider="openai"),
            _entry("Antigravity", 2, provider="antigravity"),
            _entry("OpenCode", 1, provider="opencode"),
        ]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            all_rows = sessions.collect_sessions("", source_ids=[])
            selected = sessions.collect_sessions("", source_ids=["openai"])

        self.assertEqual(all_rows["total"], 3)
        self.assertEqual([row["provider"] for row in selected["sessions"]], ["openai"])
        self.assertEqual(selected["total"], 1)
        self.assertEqual(selected["offset"], 0)
        self.assertEqual(selected["limit"], 60)
        self.assertFalse(selected["hasMore"])
        self.assertEqual(
            selected["sources"],
            [
                {"id": "openai", "label": "Codex"},
                {"id": "opencode", "label": "OpenCode"},
                {"id": "antigravity", "label": "Antigravity"},
            ],
        )

    def test_multiple_sources_or_with_text_search_and_exact_pagination(self):
        rows = [
            _entry("needle Codex", 5, provider="openai"),
            _entry("needle Antigravity", 4, provider="antigravity"),
            _entry("needle OpenCode", 3, provider="opencode"),
            _entry("needle Claude", 2, provider="claude"),
            _entry("other Codex", 1, provider="openai"),
        ]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            result = sessions.collect_sessions("NEEDLE", source_ids=["openai", "antigravity", "opencode"], limit=2, offset=1)

        self.assertEqual([row["provider"] for row in result["sessions"]], ["antigravity", "opencode"])
        self.assertEqual(result["total"], 3)
        self.assertTrue(result["totalExact"])
        self.assertEqual(result["offset"], 1)
        self.assertEqual(result["limit"], 2)
        self.assertFalse(result["hasMore"])
        self.assertEqual(
            result["sources"],
            [
                {"id": "openai", "label": "Codex"},
                {"id": "claude", "label": "Claude Code"},
                {"id": "opencode", "label": "OpenCode"},
                {"id": "antigravity", "label": "Antigravity"},
            ],
        )

    def test_empty_and_whitespace_queries_keep_newest_sixty_rows(self):
        rows = [_entry(f"row-{index}", index) for index in range(61)]
        results = []
        for query in ("", "   "):
            with self.subTest(query=query), _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
                sessions.refresh_sessions()
                result = sessions.collect_sessions(query)

            self.assertEqual(len(result["sessions"]), 60)
            self.assertEqual(result["sessions"][0]["title"], "row-60")
            self.assertEqual(result["total"], 61)
            self.assertTrue(result["totalExact"])
            self.assertEqual(result["offset"], 0)
            self.assertEqual(result["limit"], 60)
            self.assertTrue(result["hasMore"])
            results.append(result)

        self.assertEqual(results[0]["sessions"], results[1]["sessions"])

    def test_empty_query_page_returns_final_row_without_more_results(self):
        rows = [_entry(f"row-{index}", index) for index in range(61)]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            result = sessions.collect_sessions("", limit=60, offset=60)

        self.assertEqual([row["title"] for row in result["sessions"]], ["row-0"])
        self.assertEqual(result["total"], 61)
        self.assertTrue(result["totalExact"])
        self.assertEqual(result["offset"], 60)
        self.assertEqual(result["limit"], 60)
        self.assertFalse(result["hasMore"])

    def test_non_empty_query_finds_matching_row_older_than_sixty(self):
        rows = [_entry("older needle", 1)] + [_entry(f"row-{index}", index + 2) for index in range(60)]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            result = sessions.collect_sessions("needle")

        self.assertEqual([row["title"] for row in result["sessions"]], ["older needle"])
        self.assertEqual(result["total"], 1)
        self.assertTrue(result["totalExact"])
        self.assertEqual(result["offset"], 0)
        self.assertEqual(result["limit"], 60)
        self.assertFalse(result["hasMore"])

    def test_non_empty_query_pages_matching_rows(self):
        rows = [_entry(f"needle-{index}", index) for index in range(61)]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            first_page = sessions.collect_sessions("needle")
            second_page = sessions.collect_sessions("needle", offset=60)

        self.assertEqual(len(first_page["sessions"]), 60)
        self.assertEqual(first_page["sessions"][0]["title"], "needle-60")
        self.assertEqual(first_page["total"], 61)
        self.assertTrue(first_page["totalExact"])
        self.assertEqual(first_page["offset"], 0)
        self.assertEqual(first_page["limit"], 60)
        self.assertTrue(first_page["hasMore"])
        self.assertEqual([row["title"] for row in second_page["sessions"]], ["needle-0"])
        self.assertEqual(second_page["total"], 61)
        self.assertTrue(second_page["totalExact"])
        self.assertEqual(second_page["offset"], 60)
        self.assertEqual(second_page["limit"], 60)
        self.assertFalse(second_page["hasMore"])

    def test_unfiltered_total_and_pages_use_the_complete_session_universe(self):
        rows = [_entry(f"row-{index}", index) for index in range(61)]
        calls = []

        def claude_entries(*, include_all=False):
            calls.append(include_all)
            return rows if include_all else rows[-60:]

        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", side_effect=claude_entries):
            sessions.refresh_sessions()
            first_page = sessions.collect_sessions("")
            final_page = sessions.collect_sessions("", limit=60, offset=60)
            searched = sessions.collect_sessions("row")

        self.assertEqual(first_page["total"], 61)
        self.assertEqual(len(first_page["sessions"]), 60)
        self.assertTrue(first_page["hasMore"])
        self.assertEqual([row["title"] for row in final_page["sessions"]], ["row-0"])
        self.assertFalse(final_page["hasMore"])
        self.assertEqual(searched["total"], 61)
        self.assertEqual(len(searched["sessions"]), 60)
        self.assertEqual(searched["limit"], 60)
        self.assertTrue(searched["hasMore"])
        self.assertEqual(calls, [True])

    def test_query_is_case_insensitive_and_ignores_opaque_fields(self):
        rows = [_entry("Safe Title", 2), _entry("Other", 1, open_key="safe title")]
        with _empty_collectors(), mock.patch.object(sessions, "_claude_entries", return_value=rows):
            sessions.refresh_sessions()
            result = sessions.collect_sessions("SAFE TITLE")

        self.assertEqual([row["title"] for row in result["sessions"]], ["Safe Title"])


class SessionQueryCliTest(unittest.TestCase):
    def test_source_forms_are_normalized_deduplicated_and_forwarded(self):
        for argv in (
            ("--sessions", "--source", "antigravity,openai,opencode,openai"),
            ("--sessions", "--source=antigravity,openai,opencode,openai"),
        ):
            with (
                self.subTest(argv=argv),
                mock.patch(
                    "aiusage.sessions.refresh_sessions",
                    return_value={"updatedAt": 1, "sessions": []},
                ) as refresh,
                mock.patch("sys.stdout", new=io.StringIO()),
            ):
                self.assertEqual(backend.main([*argv, "--query=old", "--limit=5", "--offset=7"]), 0)

            refresh.assert_called_once_with("old", source_ids=["openai", "opencode", "antigravity"], limit=5, offset=7)

    def test_invalid_source_ids_and_source_mode_are_rejected(self):
        for source_value in ("unknown", "", "openai,,antigravity", "openai;antigravity"):
            with (
                self.subTest(source_value=source_value),
                mock.patch("aiusage.sessions.refresh_sessions") as refresh,
                mock.patch("sys.stdout", new=io.StringIO()),
                mock.patch("sys.stderr", new=io.StringIO()) as error,
            ):
                result = backend.main(["--sessions", "--source=" + source_value])

            self.assertEqual(result, 2)
            self.assertIn("source", error.getvalue())
            self.assertNotIn("unknown argument", error.getvalue())
            refresh.assert_not_called()

        with (
            mock.patch("aiusage.sessions.refresh_sessions") as refresh,
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()) as error,
        ):
            result = backend.main(["--source", "openai"])

        self.assertEqual(result, 2)
        self.assertIn("--sessions", error.getvalue())
        self.assertNotIn("unknown argument", error.getvalue())
        refresh.assert_not_called()

    def test_space_and_equals_query_forms_are_forwarded_to_sessions(self):
        for argv in (("--sessions", "--query", "old"), ("--sessions", "--query=old")):
            with (
                self.subTest(argv=argv),
                mock.patch(
                    "aiusage.sessions.refresh_sessions",
                    return_value={"updatedAt": 1, "sessions": []},
                ) as refresh,
                mock.patch("sys.stdout", new=io.StringIO()),
            ):
                self.assertEqual(backend.main(list(argv)), 0)

            refresh.assert_called_once_with("old")

    def test_pagination_forms_are_forwarded_to_sessions(self):
        argv = ("--sessions", "--query=old", "--limit", "5", "--offset=7")
        with (
            mock.patch(
                "aiusage.sessions.refresh_sessions",
                return_value={"updatedAt": 1, "sessions": []},
            ) as refresh,
            mock.patch("sys.stdout", new=io.StringIO()),
        ):
            self.assertEqual(backend.main(list(argv)), 0)

        refresh.assert_called_once_with("old", limit=5, offset=7)

    def test_query_only_forwards_page_without_refresh(self):
        argv = ("--sessions", "--query-only", "--query=old", "--limit=5", "--offset=7")
        with (
            mock.patch(
                "aiusage.sessions.collect_sessions",
                return_value={"updatedAt": 1, "sessions": []},
            ) as collect,
            mock.patch("aiusage.sessions.refresh_sessions") as refresh,
            mock.patch("sys.stdout", new=io.StringIO()),
        ):
            self.assertEqual(backend.main(list(argv)), 0)

        collect.assert_called_once_with("old", limit=5, offset=7)
        refresh.assert_not_called()

    def test_refresh_flag_forwards_page_to_global_refresh(self):
        argv = ("--sessions", "--refresh", "--query=old", "--limit=5", "--offset=7")
        with (
            mock.patch(
                "aiusage.sessions.refresh_sessions",
                return_value={"updatedAt": 1, "sessions": []},
            ) as refresh,
            mock.patch("sys.stdout", new=io.StringIO()),
        ):
            self.assertEqual(backend.main(list(argv)), 0)

        refresh.assert_called_once_with("old", limit=5, offset=7)

    def test_query_only_and_refresh_are_rejected_together(self):
        with (
            mock.patch("aiusage.sessions.collect_sessions") as collect,
            mock.patch("aiusage.sessions.refresh_sessions") as refresh,
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()) as error,
        ):
            result = backend.main(["--sessions", "--query-only", "--refresh"])

        self.assertEqual(result, 2)
        self.assertIn("cannot be used together", error.getvalue())
        collect.assert_not_called()
        refresh.assert_not_called()

    def test_invalid_pagination_values_print_usage_error(self):
        for argv in (
            ("--sessions", "--limit", "0"),
            ("--sessions", "--limit", "-1"),
            ("--sessions", "--limit", "not-a-number"),
            ("--sessions", "--offset", "-1"),
            ("--sessions", "--offset", "not-a-number"),
        ):
            with (
                self.subTest(argv=argv),
                mock.patch("sys.stdout", new=io.StringIO()),
                mock.patch("sys.stderr", new=io.StringIO()) as error,
                mock.patch("aiusage.sessions.collect_sessions") as collect,
            ):
                self.assertEqual(backend.main(list(argv)), 2)

            self.assertIn("usage:", error.getvalue())
            collect.assert_not_called()

    def test_query_response_does_not_add_private_data(self):
        entry = _entry("matching", 2, open_key="opaque")
        with (
            mock.patch(
                "aiusage.sessions.refresh_sessions",
                return_value={
                    "updatedAt": 1,
                    "sessions": [entry],
                    "sources": [{"id": "openai", "label": "Codex"}],
                },
            ),
            mock.patch("sys.stdout", new=io.StringIO()) as output,
        ):
            self.assertEqual(backend.main(["--sessions", "--query", "matching"]), 0)

        encoded = output.getvalue()
        self.assertNotIn("/private/database.db", encoded)
        self.assertNotIn("raw-session-id", encoded)
        self.assertEqual(json.loads(encoded)["sessions"][0]["title"], "matching")


if __name__ == "__main__":
    unittest.main()
