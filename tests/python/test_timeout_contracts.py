"""Every adapter owns its timeout, and a timeout never fabricates zero data.

The timeout/last-good contract: each frontend retains its last good
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

SHARED_UI = Path(REPO) / "ui"


def _read(path):
    return path.read_text(encoding="utf-8")


class AdapterTimeoutOwnershipTest(unittest.TestCase):
    # Every host shares ui/AppState.qml, so the history wiring is pinned once.
    def test_the_history_save_is_bounded_with_a_grace(self):
        source = _read(SHARED_UI / "AppState.qml")
        self.assertRegex(source, r"id:\s*historySaveTimeout")
        self.assertRegex(source, r"interval:\s*30000")

    def test_a_failed_history_batch_is_released_for_retry(self):
        self.assertIn("UsageHistory.failed(", _read(SHARED_UI / "AppState.qml"))

    def test_the_info_pane_bounds_its_requests(self):
        source = _read(SHARED_UI / "ProjectInfoPane.qml")
        self.assertIn("ProjectInfoRequests.js", source)
        self.assertIn("client.pause()", source)
        requests = _read(SHARED_UI / "js" / "ProjectInfoRequests.js")
        self.assertRegex(requests, r"now\(\) - entry\.started >= 8000")
        self.assertIn("request.abort()", requests)

    def test_http_defaults_are_bounded_and_below_the_watchdog(self):
        source = _read(Path(REPO) / "backend" / "aiusage" / "http.py")
        match = re.search(r"def fetch_json\([^)]*timeout=(\d+)", source)
        self.assertIsNotNone(match)
        self.assertLessEqual(int(match.group(1)), 30, "a provider fetch must not outlive the frontend grace")
        # A missing response is an error, never a fabricated zero.
        self.assertIn('return HttpResult(0, "")', source)


class LastGoodBackendTest(unittest.TestCase):
    def test_pricing_failure_keeps_last_good_tables_and_marks_stale(self):
        # The status vocabulary is produced where the refresh result is built.
        source = _read(Path(REPO) / "backend" / "aiusage" / "__main__.py")
        self.assertIn("stale-good", source)
        # And last-good tables are retained by the catalog loader.
        loader = _read(Path(REPO) / "backend" / "aiusage" / "pricing.py")
        self.assertIn("_merge_tables(snapshot[", loader)
        self.assertIn('cached.get("providers", {})', loader)

    def test_codex_rate_limit_cache_is_time_bounded(self):
        from aiusage.providers import codex_rate_limits

        self.assertIsInstance(codex_rate_limits.TTL_SECONDS, int)
        self.assertGreater(codex_rate_limits.TTL_SECONDS, 0)
        self.assertLessEqual(codex_rate_limits.TTL_SECONDS, 300)


if __name__ == "__main__":
    unittest.main()
