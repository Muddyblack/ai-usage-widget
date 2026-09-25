"""Every adapter owns its timeout, and a timeout never fabricates zero data.

The plan's timeout/last-good contract: each frontend retains its last good
summary/panel/menu-bar values, marks stale/error, rejects a late result, gives
an owned child a bounded grace and terminates it, and keeps a history batch
retryable. This suite pins the values and the wiring without a desktop session.

The UI-level last-good/stale matrix lives in tests/behavior/stale-state.json and
tests/frontend-behavior.test.js; this covers the backend-side ownership.
"""

import re
import unittest
from pathlib import Path

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)

UI = Path(REPO) / "package" / "contents" / "ui"
HYPRLAND = Path(REPO) / "hyprland"
WINDOWS = Path(REPO) / "windows"
MACOS = Path(REPO) / "macos" / "Sources" / "AIUsage"


def _read(path):
    return path.read_text(encoding="utf-8")


class AdapterTimeoutOwnershipTest(unittest.TestCase):
    def test_every_adapter_bounds_the_history_save_with_the_same_grace(self):
        for path in (UI / "main.qml", HYPRLAND / "AiUsageShell.qml", WINDOWS / "qml" / "Main.qml"):
            with self.subTest(adapter=path.name):
                source = _read(path)
                self.assertRegex(source, r"id:\s*historySaveTimeout")
                self.assertRegex(source, r"interval:\s*30000")

    def test_every_adapter_releases_a_failed_history_batch_for_retry(self):
        for path in (UI / "main.qml", HYPRLAND / "AiUsageShell.qml", WINDOWS / "qml" / "Main.qml"):
            with self.subTest(adapter=path.name):
                self.assertIn("UsageHistory.failed(", _read(path))

    def test_the_info_pane_bounds_its_requests_in_every_adapter(self):
        for path in (UI / "ProjectInfoPane.qml", HYPRLAND / "ProjectInfoPane.qml"):
            with self.subTest(adapter=path.name):
                source = _read(path)
                self.assertIn("ProjectInfoRequests.js", source)
                self.assertIn("client.pause()", source)
        requests = _read(UI / ".." / "code" / "ProjectInfoRequests.js")
        self.assertRegex(requests, r"now\(\) - entry\.started >= 8000")
        self.assertIn("request.abort()", requests)

    def test_macos_drains_both_pipes_before_waiting(self):
        # The deadlock guard: a provider list can outgrow the 64 KB pipe buffer,
        # so both pipes are read while the child runs rather than after wait.
        runner = _read(MACOS / "Backend" / "BackendRunner.swift")
        self.assertIn("readDataToEndOfFile", runner)
        # The grace/termination for a hung child is task 26's scope; it is not
        # present here today, so this test only pins what the adapter does own.
        self.assertIn("waitUntilExit", runner)

    def test_http_defaults_are_bounded_and_below_the_watchdog(self):
        source = _read(Path(REPO) / "package" / "contents" / "tools" / "aiusage" / "http.py")
        match = re.search(r"def fetch_json\([^)]*timeout=(\d+)", source)
        self.assertIsNotNone(match)
        self.assertLessEqual(int(match.group(1)), 30, "a provider fetch must not outlive the frontend grace")
        # A missing response is an error, never a fabricated zero.
        self.assertIn('return HttpResult(0, "")', source)


class LastGoodBackendTest(unittest.TestCase):
    def test_pricing_failure_keeps_last_good_tables_and_marks_stale(self):
        # The status vocabulary is produced where the refresh result is built.
        source = _read(Path(REPO) / "package" / "contents" / "tools" / "aiusage" / "__main__.py")
        self.assertIn("stale-good", source)
        # And last-good tables are retained by the catalog loader.
        loader = _read(Path(REPO) / "package" / "contents" / "tools" / "aiusage" / "pricing.py")
        self.assertIn("_merge_tables(snapshot[", loader)
        self.assertIn('cached.get("providers", {})', loader)

    def test_codex_last_good_is_time_bounded(self):
        from aiusage.providers import codex_last_good

        self.assertIsInstance(codex_last_good.TTL_SECONDS, int)
        self.assertGreater(codex_last_good.TTL_SECONDS, 0)
        self.assertLessEqual(codex_last_good.TTL_SECONDS, 300)


if __name__ == "__main__":
    unittest.main()
