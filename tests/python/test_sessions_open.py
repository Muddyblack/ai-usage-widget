"""``open_session()`` — the resume-in-terminal path for the Sessions tab.

Covers the redaction/validation boundary described in sessions.py's module
docstring: a key is either a fresh digest of a real target or the call fails
closed, and it never leaks a path or session id in its (user-visible) message.
"""

import unittest
from unittest import mock

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import sessions


class OpenKeyStabilityTest(unittest.TestCase):
    def test_same_provider_and_id_always_the_same_digest(self):
        first = sessions._open_key("claude", "abc-123")
        second = sessions._open_key("claude", "abc-123")
        self.assertEqual(first, second)
        self.assertRegex(first, r"^[0-9a-f]{64}$")

    def test_different_ids_get_different_digests(self):
        self.assertNotEqual(sessions._open_key("claude", "abc-123"), sessions._open_key("claude", "abc-124"))

    def test_different_providers_get_different_digests(self):
        self.assertNotEqual(sessions._open_key("claude", "abc-123"), sessions._open_key("openai", "abc-123"))

    def test_missing_provider_or_id_is_empty(self):
        self.assertEqual(sessions._open_key("", "abc-123"), "")
        self.assertEqual(sessions._open_key("claude", ""), "")


class OpenSessionFailsClosedTest(unittest.TestCase):
    def test_malformed_key_fails_closed(self):
        for bad in ("", "not-hex", "abc", "0" * 16, "0" * 63, "0" * 65, "GHIJKLMNOPQRSTUV"):
            with self.subTest(key=bad):
                ok, message = sessions.open_session(bad)
                self.assertFalse(ok)
                self.assertIn("refresh", message)

    def test_stale_key_not_in_a_fresh_scan_fails_closed(self):
        with mock.patch.object(sessions, "collect_open_targets", return_value={}):
            ok, message = sessions.open_session("0123456789abcdef" * 4)
        self.assertFalse(ok)
        self.assertIn("refresh", message)

    def test_failure_message_never_names_a_path_or_id(self):
        with (
            mock.patch.object(
                sessions,
                "collect_open_targets",
                return_value={"0123456789abcdef": {"provider": "claude", "id": "secret-session-id", "cwd": "/home/user/project"}},
            ),
            mock.patch.object(sessions.shutil, "which", return_value=None),
        ):
            ok, message = sessions.open_session("0123456789abcdef" * 4)
        self.assertFalse(ok)
        self.assertNotIn("secret-session-id", message)
        self.assertNotIn("/home/user/project", message)


class OpenSessionResolvesAndSpawnsTest(unittest.TestCase):
    """A real key from collect_sessions() resolves and spawns the resume
    command through a fake $TERMINAL — no real terminal is ever launched
    here or in CI."""

    def test_resolves_a_real_key_and_spawns_terminal_with_right_argv_and_cwd(self):
        # Use a known Claude target: local sessions may belong to another CLI,
        # while fake_which below intentionally exposes only Claude.
        provider, session_id, cwd = "claude", "abc-123", "/tmp"
        entry = sessions._entry(provider, "Example", 1, session_id=session_id)
        target_key = entry["openKey"]
        targets_patch = mock.patch.object(
            sessions,
            "collect_open_targets",
            return_value={target_key: {"provider": provider, "id": session_id, "cwd": cwd}},
        )

        captured = {}

        def fake_popen(argv, **kwargs):
            captured["argv"] = argv
            captured["cwd"] = kwargs.get("cwd")
            return mock.Mock()

        def fake_which(name):
            # Only the resume binary and one terminal exist on this "machine".
            if name in ("claude", "fake-term"):
                return f"/usr/bin/{name}"
            return None

        with (
            targets_patch,
            mock.patch.dict("os.environ", {"TERMINAL": ""}, clear=False),
            mock.patch.object(sessions.shutil, "which", side_effect=fake_which),
            mock.patch.object(sessions.subprocess, "Popen", side_effect=fake_popen),
            mock.patch.object(sessions, "_TERMINAL_TEMPLATES", [("fake-term", ["-e", "sh", "-c", "{cmd}"])]),
        ):
            ok, message = sessions.open_session(target_key)

        self.assertTrue(ok)
        self.assertIn("fake-term", message)
        self.assertIn("/usr/bin/fake-term", captured["argv"])
        joined = " ".join(captured["argv"])
        self.assertIn("claude", joined)
        self.assertIn("--resume", joined)

    def test_no_resume_command_for_provider_fails_closed(self):
        key = sessions._open_key("muse", "some-id")
        with mock.patch.object(sessions, "collect_open_targets", return_value={key: {"provider": "muse", "id": "some-id", "cwd": ""}}):
            ok, message = sessions.open_session(key)
        self.assertFalse(ok)
        self.assertIn("muse", message)

    def test_opencode_uses_actual_session_id_but_keeps_database_in_opaque_key(self):
        provider, session_id, key_id, cwd = "opencode", "ses-abc", "/private/opencode.db\x00ses-abc", "/tmp"
        target_key = sessions._open_key(provider, key_id)
        targets_patch = mock.patch.object(
            sessions,
            "collect_open_targets",
            return_value={target_key: {"provider": provider, "id": session_id, "keyId": key_id, "cwd": cwd}},
        )
        captured = {}

        def fake_popen(argv, **kwargs):
            captured["argv"] = argv
            captured["cwd"] = kwargs.get("cwd")
            return mock.Mock()

        def fake_which(name):
            if name in ("opencode", "fake-term"):
                return f"/usr/bin/{name}"
            return None

        with (
            targets_patch,
            mock.patch.object(sessions.shutil, "which", side_effect=fake_which),
            mock.patch.object(sessions.subprocess, "Popen", side_effect=fake_popen),
            mock.patch.object(sessions, "_TERMINAL_TEMPLATES", [("fake-term", ["-e", "sh", "-c", "{cmd}"])]),
        ):
            ok, _message = sessions.open_session(target_key)

        self.assertTrue(ok)
        command = " ".join(captured["argv"])
        self.assertIn("--session", command)
        self.assertIn(session_id, command)
        self.assertNotIn(key_id, command)

    def test_missing_resume_binary_fails_closed(self):
        key = sessions._open_key("claude", "some-id")
        with (
            mock.patch.object(sessions, "collect_open_targets", return_value={key: {"provider": "claude", "id": "some-id", "cwd": ""}}),
            mock.patch.object(sessions.shutil, "which", return_value=None),
        ):
            ok, message = sessions.open_session(key)
        self.assertFalse(ok)
        self.assertIn("claude", message)


if __name__ == "__main__":
    unittest.main()
