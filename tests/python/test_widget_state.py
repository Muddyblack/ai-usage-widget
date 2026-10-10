"""The Plasma widget's out-of-KConfig state: last good snapshot, shared settings."""

import io
import json
import os
import stat
import threading
import time
import unittest
from contextlib import redirect_stdout
from unittest import mock

import _support  # noqa: F401  (sys.path)
from _support import IsolatedHomeTest
from aiusage import __main__ as backend
from aiusage import envelope, widget_state

GOOD = {"schemaVersion": 1, "updatedAt": 1, "providers": [{"id": "claude", "email": "me@example.test"}]}
FAILED = {"schemaVersion": 1, "updatedAt": 2, "providers": [{"id": "claude", "error": "offline"}]}


def _run(argv, env=None):
    out = io.StringIO()
    with mock.patch.dict(os.environ, env or {}), redirect_stdout(out):
        code = backend.main(argv)
    return code, out.getvalue()


class LastSnapshotTest(IsolatedHomeTest):
    def test_no_snapshot_reads_as_empty_object(self):
        self.assertEqual(_run(["--last-snapshot"]), (0, "{}\n"))

    def test_old_snapshot_drops_removed_providers_and_updates_icons(self):
        old = {
            "active": "gemini",
            "providers": [
                {"id": "gemini", "icon": "gemini.svg"},
                {"id": "antigravity", "icon": "google-color.svg", "summary": {"pct": 42}},
            ],
        }
        widget_state._write_private(widget_state.snapshot_path(), old)
        result = widget_state.last_snapshot()
        self.assertEqual(result["active"], "antigravity")
        self.assertEqual(result["providers"], [{"id": "antigravity", "icon": "antigravity-color.svg", "summary": {"pct": 42}}])
        widget_state.save_snapshot(GOOD)
        with open(widget_state.snapshot_path(), encoding="utf-8") as stream:
            self.assertEqual([p["id"] for p in json.load(stream)["providers"]], ["antigravity", "claude"])

    def test_good_envelope_is_kept_privately_outside_the_config(self):
        self.assertTrue(widget_state.save_snapshot(GOOD))
        path = widget_state.snapshot_path()
        self.assertTrue(path.startswith(os.environ["AI_USAGE_CACHE_DIR"]))
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        self.assertEqual(json.loads(_run(["--last-snapshot"])[1]), GOOD)

    def test_all_failed_envelope_never_replaces_the_last_good_one(self):
        widget_state.save_snapshot(GOOD)
        self.assertFalse(widget_state.save_snapshot(FAILED))
        self.assertEqual(widget_state.last_snapshot(), GOOD)

    def test_partial_refreshes_merge_per_provider(self):
        widget_state.save_snapshot(GOOD)
        widget_state.save_snapshot({"updatedAt": 3, "providers": [{"id": "openai", "plan": "plus"}, {"id": "claude", "error": "offline"}]})
        stored = widget_state.last_snapshot()
        self.assertEqual(stored["updatedAt"], 3)
        self.assertEqual({p["id"]: p for p in stored["providers"]}, {"claude": GOOD["providers"][0], "openai": {"id": "openai", "plan": "plus"}})

    def test_concurrent_saves_keep_both_providers(self):
        read = widget_state._read_object

        def slow_read(path):
            data = read(path)
            time.sleep(0.2)  # widen the read-merge-write window
            return data

        envelopes = [{"providers": [{"id": "claude"}]}, {"providers": [{"id": "openai"}]}]
        with mock.patch.object(widget_state, "_read_object", side_effect=slow_read):
            threads = [threading.Thread(target=widget_state.save_snapshot, args=(env,)) for env in envelopes]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
        self.assertEqual(sorted(p["id"] for p in widget_state.last_snapshot()["providers"]), ["claude", "openai"])

    def test_save_snapshot_flag_writes_what_was_printed(self):
        with mock.patch.object(envelope, "build", return_value=GOOD):
            code, out = _run(["--provider", "claude", "--save-snapshot"])
        self.assertEqual(code, 0)
        self.assertEqual(widget_state.last_snapshot(), json.loads(out))

    def test_plain_fetch_does_not_write_a_snapshot(self):
        with mock.patch.object(envelope, "build", return_value=GOOD):
            _run(["--provider", "claude"])
        self.assertFalse(os.path.exists(widget_state.snapshot_path()))


class SharedSettingsTest(IsolatedHomeTest):
    def _merge(self, patch):
        code, out = _run(["--shared-settings"], {"WIDGET_SHARED_PATCH": json.dumps(patch)})
        self.assertEqual(code, 0)
        return json.loads(out)["data"]

    def test_empty_patch_reads_without_creating_the_file(self):
        self.assertEqual(self._merge({}), {})
        self.assertFalse(os.path.exists(widget_state.shared_settings_path()))

    def test_patches_merge_per_key(self):
        self._merge({"claudeEnabled": True, "pollIntervalSec": 300})
        merged = self._merge({"openaiEnabled": False})
        self.assertEqual(merged, {"claudeEnabled": True, "pollIntervalSec": 300, "openaiEnabled": False})

    def test_null_removes_a_key(self):
        self._merge({"grokApiKey": "secret"})
        self.assertEqual(self._merge({"grokApiKey": None}), {})

    def test_file_is_private(self):
        self._merge({"grokApiKey": "secret"})
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(os.stat(widget_state.shared_settings_path()).st_mode), 0o600)

    def test_each_widget_id_has_its_own_file(self):
        with mock.patch.dict(os.environ, {"AI_USAGE_WIDGET_ID": "org.muddyblack.aiUsageWidgetTest"}):
            self._merge({"claudeEnabled": False})
            test_path = widget_state.shared_settings_path()
        with mock.patch.dict(os.environ, {"AI_USAGE_WIDGET_ID": "org.muddyblack.aiUsageWidget"}):
            self.assertEqual(self._merge({}), {}, "the test copy must not change the real widget")
            self.assertNotEqual(widget_state.shared_settings_path(), test_path)
        with mock.patch.dict(os.environ, {"AI_USAGE_WIDGET_ID": "../../etc/x"}):
            self.assertNotIn("/etc/", widget_state.shared_settings_path().replace(os.sep, "/").split("ai-usage-widget", 1)[1])

    def test_malformed_patch_is_rejected(self):
        code, _ = _run(["--shared-settings"], {"WIDGET_SHARED_PATCH": "{not json"})
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
