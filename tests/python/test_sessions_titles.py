"""Session row titles — the boundary between a folder name and a user's own
words.

Claude Code writes no separate summary, so its row title is the session's own
opening prompt (from ``history.jsonl``), clipped, with the full text offered
back as ``fullTitle`` for a frontend to expand. Cline's own ``prompt`` field
looks similar but is a rolling snapshot of recent tool output rather than an
opening message, so it must never reach ``_cline_entries()``'s output — that
is a regression a future edit could reintroduce without this test.
"""

import json
import os
import tempfile
import unittest
from unittest import mock

from _support import REPO, IsolatedHomeTest  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import sessions


class ClipTitleTest(unittest.TestCase):
    def test_short_text_passes_through_unchanged(self):
        self.assertEqual(sessions._clip_title("fix the login bug"), "fix the login bug")

    def test_collapses_internal_whitespace(self):
        self.assertEqual(sessions._clip_title("fix   the\nlogin\tbug"), "fix the login bug")

    def test_exactly_at_the_limit_is_not_clipped(self):
        text = "x" * sessions._TITLE_PREVIEW_LEN
        self.assertEqual(sessions._clip_title(text), text)

    def test_over_the_limit_is_clipped_with_ellipsis(self):
        text = "x" * (sessions._TITLE_PREVIEW_LEN + 20)
        clipped = sessions._clip_title(text)
        self.assertTrue(clipped.endswith("…"))
        self.assertEqual(len(clipped), sessions._TITLE_PREVIEW_LEN + 1)

    def test_non_string_input_is_empty(self):
        self.assertEqual(sessions._clip_title(None), "")
        self.assertEqual(sessions._clip_title(42), "")


class ClaudePromptTitlesTest(unittest.TestCase):
    def test_missing_history_file_is_empty(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(sessions._claude_prompt_titles(root), {})

    def test_first_occurrence_per_session_wins(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "history.jsonl")
            with open(path, "w", encoding="utf-8") as f:
                f.write(json.dumps({"sessionId": "s1", "display": "opening message"}) + "\n")
                f.write(json.dumps({"sessionId": "s1", "display": "a later message"}) + "\n")
                f.write(json.dumps({"sessionId": "s2", "display": "another session"}) + "\n")
            titles = sessions._claude_prompt_titles(root)
        self.assertEqual(titles, {"s1": "opening message", "s2": "another session"})

    def test_malformed_lines_are_skipped_not_fatal(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "history.jsonl")
            with open(path, "w", encoding="utf-8") as f:
                f.write("not json\n")
                f.write(json.dumps(["array", "not", "object"]) + "\n")
                f.write(json.dumps({"sessionId": "s1", "display": "fine"}) + "\n")
                f.write(json.dumps({"sessionId": "s2"}) + "\n")  # no display
            titles = sessions._claude_prompt_titles(root)
        self.assertEqual(titles, {"s1": "fine"})


class ClaudeEntriesTitleTest(IsolatedHomeTest):
    def _write_session(self, root, project_dir, session_id):
        projects = os.path.join(root, "projects", project_dir)
        os.makedirs(projects, exist_ok=True)
        with open(os.path.join(projects, session_id + ".jsonl"), "w", encoding="utf-8") as f:
            f.write(json.dumps({"sessionId": session_id}) + "\n")

    def test_title_is_the_clipped_opening_prompt_with_folder_as_detail(self):
        with tempfile.TemporaryDirectory() as root:
            self._write_session(root, "-mnt-projects-widget", "session-1")
            with open(os.path.join(root, "history.jsonl"), "w", encoding="utf-8") as f:
                f.write(json.dumps({"sessionId": "session-1", "display": "fix the login bug"}) + "\n")
            with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}):
                entries = sessions._claude_entries()
        self.assertEqual(len(entries), 1)
        entry = entries[0]
        self.assertEqual(entry["title"], "fix the login bug")
        self.assertEqual(entry["detail"], "widget")
        self.assertNotIn("fullTitle", entry)  # short enough it wasn't clipped

    def test_long_prompt_carries_fulltitle_when_clipped(self):
        long_prompt = "please " + ("x" * 100)
        with tempfile.TemporaryDirectory() as root:
            self._write_session(root, "-mnt-projects-widget", "session-1")
            with open(os.path.join(root, "history.jsonl"), "w", encoding="utf-8") as f:
                f.write(json.dumps({"sessionId": "session-1", "display": long_prompt}) + "\n")
            with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}):
                entries = sessions._claude_entries()
        entry = entries[0]
        self.assertTrue(entry["title"].endswith("…"))
        self.assertEqual(entry["fullTitle"], long_prompt)
        self.assertRegex(entry["openKey"], r"^[0-9a-f]{64}$")
        self.assertNotEqual(entry["openKey"], "session-1")

    def test_no_history_entry_falls_back_to_folder_name(self):
        with tempfile.TemporaryDirectory() as root:
            self._write_session(root, "-mnt-projects-widget", "session-1")
            with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}):
                entries = sessions._claude_entries()
        entry = entries[0]
        self.assertEqual(entry["title"], "widget")
        self.assertEqual(entry["detail"], "")
        self.assertNotIn("fullTitle", entry)

    def test_query_scan_exposes_an_older_transcript_in_the_same_project(self):
        with tempfile.TemporaryDirectory() as root:
            self._write_session(root, "-mnt-projects-widget", "old-session")
            self._write_session(root, "-mnt-projects-widget", "new-session")
            old_path = os.path.join(root, "projects", "-mnt-projects-widget", "old-session.jsonl")
            new_path = os.path.join(root, "projects", "-mnt-projects-widget", "new-session.jsonl")
            os.utime(old_path, (1_000, 1_000))
            os.utime(new_path, (2_000, 2_000))
            with open(os.path.join(root, "history.jsonl"), "w", encoding="utf-8") as f:
                f.write(json.dumps({"sessionId": "old-session", "display": "find this older Claude session"}) + "\n")
                f.write(json.dumps({"sessionId": "new-session", "display": "newer session"}) + "\n")
            with (
                mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}),
                mock.patch.object(sessions, "_cline_entries", return_value=[]),
                mock.patch.object(sessions, "_muse_entries", return_value=[]),
                mock.patch.object(sessions, "_codex_entries", return_value=[]),
                mock.patch.object(sessions, "_grok_entries", return_value=[]),
                mock.patch.object(sessions, "_opencode_entries", return_value=[]),
                mock.patch.object(sessions, "_antigravity_entries", return_value=[]),
            ):
                sessions.refresh_sessions()
                result = sessions.collect_sessions("OLDER CLAUDE")

        self.assertEqual([entry["title"] for entry in result["sessions"]], ["find this older Claude session"])


class ClineNeverUsesItsPromptFieldTest(unittest.TestCase):
    """Regression guard: Cline's ``prompt`` field is a rolling snapshot of
    tool output, not an opening message (see providers/cline.py) — it must
    never end up in a Sessions-tab title or detail."""

    def test_prompt_field_is_absent_from_collector_output(self):
        with tempfile.TemporaryDirectory() as root:
            session_dir = os.path.join(root, "session-1")
            os.makedirs(session_dir, exist_ok=True)
            record = {
                "started_at": "2024-01-01T00:00:00Z",
                "workspace_root": "/mnt/projects/widget",
                "prompt": "<user_input>SENSITIVE TOOL OUTPUT / OTHER PROJECT PATH</user_input>",
            }
            with open(os.path.join(session_dir, "session-1.json"), "w", encoding="utf-8") as f:
                json.dump(record, f)
            with mock.patch.dict(os.environ, {"CLINE_SESSIONS_DIR": root}):
                entries = sessions._cline_entries()
        self.assertEqual(len(entries), 1)
        blob = json.dumps(entries[0])
        self.assertNotIn("SENSITIVE", blob)
        self.assertEqual(entries[0]["title"], "widget")


if __name__ == "__main__":
    unittest.main()
