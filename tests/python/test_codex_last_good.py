"""Offline coverage for Codex's identity-bound last-good snapshot."""

import json
import os
import tempfile
import unittest
from unittest import mock

import _support  # noqa: F401
from aiusage.providers import codex_last_good

LIVE = {"rateLimits": {"primary": {"usedPercent": 42, "windowDurationMins": 300, "resetsAt": 500}}}


class CodexLastGoodTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.cache_patch = mock.patch("aiusage.providers.codex_last_good.config.cache_dir", return_value=self.directory.name)
        self.cache_patch.start()
        self.addCleanup(self.cache_patch.stop)

    def test_live_then_empty_and_timeout_use_same_identity_snapshot(self):
        saved, source, _ = codex_last_good.snapshot(LIVE, "token-a", "/tmp/codex", 100)
        self.assertEqual((saved, source), (LIVE, "live"))
        for empty in ({}, {}):
            stale, source, age = codex_last_good.snapshot(empty, "token-a", "/tmp/codex", 130)
            self.assertEqual(stale, LIVE)
            self.assertEqual((source, age), ("stale", 30))

    def test_first_empty_is_unavailable(self):
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/codex", 100), ({}, "unavailable", None))

    def test_malformed_cache_is_unavailable(self):
        _, _, _ = codex_last_good.snapshot(LIVE, "token-a", "/tmp/codex", 100)
        path = self._path("token-a", "/tmp/codex")
        with open(path, "w", encoding="utf-8") as stream:
            stream.write("{")
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/codex", 101), ({}, "unavailable", None))

    def test_write_failure_keeps_live_result_and_does_not_make_cache(self):
        with mock.patch("aiusage.providers.codex_last_good.os.replace", side_effect=OSError):
            live, source, _ = codex_last_good.snapshot(LIVE, "token-a", "/tmp/codex", 100)
        self.assertEqual((live, source), (LIVE, "live"))
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/codex", 101), ({}, "unavailable", None))

    def test_rollback_and_ttl_boundary_do_not_reuse_data(self):
        codex_last_good.snapshot(LIVE, "token-a", "/tmp/codex", 100)
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/codex", 99)[1], "unavailable")
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/codex", 220)[1], "stale")
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/codex", 221)[1], "unavailable")

    def test_logout_login_and_home_changes_cannot_reuse_snapshot(self):
        codex_last_good.snapshot(LIVE, "token-a", "/tmp/codex", 100)
        self.assertEqual(codex_last_good.snapshot({}, "token-b", "/tmp/codex", 101)[1], "unavailable")
        self.assertEqual(codex_last_good.snapshot({}, "token-a", "/tmp/other", 101)[1], "unavailable")

    def test_explicit_no_limits_is_a_fresh_success(self):
        self.assertEqual(codex_last_good.snapshot({"_codexNoLimits": True}, "token-a", "/tmp/codex", 100), ({"_codexNoLimits": True}, "live", 0))

    def test_cache_has_only_safe_metadata_and_hashed_identity(self):
        codex_last_good.snapshot({**LIVE, "email": "private@example.test", "token": "secret"}, "secret.jwt.value", "/tmp/codex", 100)
        names = os.listdir(self.directory.name)
        self.assertEqual(len(names), 1)
        with open(os.path.join(self.directory.name, names[0]), encoding="utf-8") as stream:
            content = stream.read()
        self.assertNotIn("secret", content)
        self.assertNotIn("private@example.test", content)
        payload = json.loads(content)
        self.assertEqual(set(payload["data"]), {"rateLimits"})

    @staticmethod
    def _path(token, home):
        key = codex_last_good.identity_key(token, home)
        return os.path.join(codex_last_good.config.cache_dir(), f"codex-last-good-{key}.json")


if __name__ == "__main__":
    unittest.main()
