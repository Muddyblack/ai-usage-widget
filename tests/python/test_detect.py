import builtins
import contextlib
import io
import json
import shutil
import socket
import sqlite3
import subprocess
import unittest
from unittest import mock

from _support import IsolatedHomeTest
from aiusage import __main__ as backend
from aiusage import config, detect


class ProviderDetectionTest(IsolatedHomeTest):
    def test_detection_uses_local_markers_in_canonical_order(self):
        self.write(".claude/.credentials.json", "not-json-secret")
        self.write(".codex/auth.json", "not-json-secret")
        self.write(".cursor/auth.json", "not-json-secret")
        self.write(".cursor/chats/project/session/meta.json", "not-json-secret")
        self.write(".cline/data/sessions/session/session.json", "not-json-secret")
        self.write(".config/openrouter/api-key", "openrouter-secret")
        self.write(".config/deepseek/api-key", "deepseek-secret")

        with (
            mock.patch.object(shutil, "which", return_value=""),
            mock.patch.object(subprocess, "run", side_effect=AssertionError("detection ran a subprocess")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("detection opened SQLite")),
        ):
            self.assertEqual(detect.detect_providers(), ["claude", "openai", "cursor", "cline"])

    def test_detection_never_reads_files_or_uses_network(self):
        self.write(".claude/.credentials.json", "secret")
        with (
            mock.patch.object(builtins, "open", side_effect=AssertionError("detection read file contents")),
            mock.patch.object(socket, "create_connection", side_effect=AssertionError("detection used network")),
            mock.patch.object(subprocess, "run", side_effect=AssertionError("detection ran a subprocess")),
            mock.patch.object(sqlite3, "connect", side_effect=AssertionError("detection opened SQLite")),
            mock.patch.object(shutil, "which", return_value=""),
        ):
            self.assertEqual(detect.detect_providers(), ["claude"])


class ProviderDefaultsTest(IsolatedHomeTest):
    def test_missing_provider_values_are_disabled_once_defaults_applied(self):
        latched = {"providerDefaultsApplied": True}
        self.assertFalse(config.provider_enabled({**latched, "providers": {}}, "claude"))
        self.assertFalse(config.provider_enabled({**latched, "providers": {}}, "cursor"))
        self.assertTrue(config.provider_enabled({**latched, "providers": {"claude": True}}, "claude"))
        self.assertFalse(config.provider_enabled({**latched, "providers": {"claude": False}}, "claude"))

    def test_unapplied_settings_keep_legacy_defaults(self):
        self.assertTrue(config.provider_enabled({"providers": {}}, "claude"))
        self.assertFalse(config.provider_enabled({"providers": {}}, "cursor"))
        self.assertFalse(config.provider_enabled({"providers": {"claude": False}}, "claude"))
        self.assertTrue(config.provider_enabled({"providers": {"cursor": True}}, "cursor"))

    def test_new_settings_are_zero_default_except_for_detected_providers(self):
        with mock.patch.object(detect, "detect_providers", return_value=["cursor"]):
            result = config.initialize_provider_defaults()

        expected = {provider: provider == "cursor" for provider in config.ALL_PROVIDERS}
        self.assertEqual(result["providers"], expected)
        self.assertTrue(result["providerDefaultsApplied"])
        with open(config.config_path(), encoding="utf-8") as stream:
            self.assertEqual(json.load(stream), result)

    def test_existing_settings_materialize_legacy_defaults_and_preserve_choices(self):
        original = {
            "providers": {"claude": False, "cursor": True},
            "keys": {"openai": "secret"},
            "futureField": {"kept": True},
        }
        self.write("config.json", original)
        with mock.patch.object(detect, "detect_providers", side_effect=AssertionError("existing settings were probed")):
            result = config.initialize_provider_defaults()

        self.assertFalse(result["providers"]["claude"])
        self.assertTrue(result["providers"]["cursor"])
        self.assertTrue(result["providers"]["openai"])
        self.assertTrue(result["providers"]["antigravity"])
        self.assertFalse(result["providers"]["muse"])
        self.assertEqual(result["keys"], original["keys"])
        self.assertEqual(result["futureField"], original["futureField"])
        self.assertTrue(result["providerDefaultsApplied"])

    def test_existing_settings_never_gain_detected_providers(self):
        self.write("config.json", {"providers": {"mistral": False}})
        result = config.initialize_provider_defaults(detected=["cursor", "opencode"])
        self.assertFalse(result["providers"]["cursor"])
        self.assertFalse(result["providers"]["opencode"])
        self.assertFalse(result["providers"]["mistral"])
        self.assertTrue(result["providers"]["claude"])

    def test_symlinked_settings_are_not_replaced(self):
        target = self.write("store/settings.json", {"providers": {"claude": True}})
        link = self.home / "config.json"
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(target)
        result = config.initialize_provider_defaults(detected=[])
        self.assertTrue(link.is_symlink())
        self.assertEqual(json.loads(target.read_text(encoding="utf-8")), {"providers": {"claude": True}})
        self.assertTrue(result["providers"]["claude"])

    def test_latch_prevents_future_detection_and_writes(self):
        original = {"providers": {"cursor": False}, "providerDefaultsApplied": True, "future": 1}
        self.write("config.json", original)
        with mock.patch.object(detect, "detect_providers", side_effect=AssertionError("probe repeated")):
            self.assertEqual(config.initialize_provider_defaults(), original)

    def test_failed_atomic_publish_preserves_existing_settings(self):
        original = {"providers": {"claude": False}, "future": 1}
        path = self.write("config.json", original)
        with (
            mock.patch.object(detect, "detect_providers", return_value=[]),
            mock.patch.object(config.os, "replace", side_effect=OSError("publish failed")),
        ):
            with self.assertRaises(OSError):
                config.initialize_provider_defaults()
        self.assertEqual(json.loads(path.read_text(encoding="utf-8")), original)


class ProviderDefaultsCliTest(IsolatedHomeTest):
    def test_detect_cli_emits_stable_json_data(self):
        output = io.StringIO()
        with mock.patch.object(detect, "detect_providers", return_value=["cursor", "opencode"]), contextlib.redirect_stdout(output):
            self.assertEqual(backend.main(["--detect-providers"]), 0)
        self.assertEqual(json.loads(output.getvalue()), {"ok": True, "data": ["cursor", "opencode"]})

    def test_initialize_cli_emits_settings_without_touching_all_mode(self):
        settings = {"providers": {"cursor": True}, "providerDefaultsApplied": True}
        output = io.StringIO()
        with mock.patch.object(config, "initialize_provider_defaults", return_value=settings), contextlib.redirect_stdout(output):
            self.assertEqual(backend.main(["--initialize-provider-defaults"]), 0)
        self.assertEqual(json.loads(output.getvalue()), {"ok": True, "data": settings})

        with mock.patch.object(config, "initialize_provider_defaults", side_effect=AssertionError("all initialized settings")):
            with mock.patch.object(backend.envelope, "build", return_value={"providers": []}):
                self.assertEqual(backend.main(["--all"]), 0)


if __name__ == "__main__":
    unittest.main()
