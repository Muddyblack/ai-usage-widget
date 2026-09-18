"""Worker results must reach QML and its property bindings on the GUI thread."""

import importlib.util
import os
import sys
import threading
import unittest
from unittest import mock

from _support import REPO

HAS_PYSIDE = importlib.util.find_spec("PySide6") is not None
if HAS_PYSIDE:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    sys.path.insert(0, os.path.join(REPO, "windows"))
    import app
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QGuiApplication


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
class BackendThreadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qt_app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.backend = app.Backend()
        self.addCleanup(self.backend._pool.shutdown, wait=True)
        self.events = []
        self.gui_thread = threading.get_ident()
        for name in ("busyChanged", "snapshotReady", "refreshFailed", "historyFinished"):
            # A direct observer records the emission thread, without Qt
            # concealing an unsafe emission by queueing the test callback.
            getattr(self.backend, name).connect(
                lambda *args, name=name: self.events.append((name, args, threading.get_ident())),
                Qt.DirectConnection,
            )

    def check_refresh(self, error=None):
        with mock.patch("app.collect_snapshot", return_value='{"providers":[]}', side_effect=error):
            self.backend.refresh()
            # Wait for the worker without pumping GUI events. The UI must
            # remain busy until the queued completion has been handled.
            self.backend._pool.shutdown(wait=True)
            self.assertTrue(self.backend.busy)
            self.assertEqual(self.events, [("busyChanged", (), self.gui_thread)])
            self.qt_app.processEvents()
            self.assertFalse(self.backend.busy)
            expected = ("refreshFailed", ("usage backend failed: offline",)) if error else ("snapshotReady", ('{"providers":[]}',))
            self.assertEqual(self.events[1:], [(*expected, self.gui_thread), ("busyChanged", (), self.gui_thread)])

    def test_refresh_success_is_published_on_the_gui_thread(self):
        self.check_refresh()

    def test_refresh_failure_is_published_on_the_gui_thread(self):
        self.check_refresh(RuntimeError("offline"))

    def test_history_is_published_on_the_gui_thread(self):
        with mock.patch("app.historyio.run", return_value='{"data":[]}'):
            self.backend.history("autoload", "")
            self.backend._pool.shutdown(wait=True)
        self.assertEqual(self.events, [])
        self.qt_app.processEvents()
        self.assertEqual(self.events, [("historyFinished", ("autoload", '{"data":[]}'), self.gui_thread)])

    def test_session_refresh_uses_query_only_collection(self):
        with mock.patch("app.collect_sessions", return_value={}) as collect:
            self.backend.refreshSessions("query", 1, 3)
            self.backend._sessions_future.result(timeout=5)

        self.assertEqual(collect.call_args_list, [mock.call("query", limit=60, offset=3)])

    def test_session_query_forwards_source_ids_through_windows_bridge(self):
        with mock.patch("app.collect_sessions_json", return_value='{"sessions":[]}') as collect:
            self.backend.refreshSessions("query", 1, 3, ["openai", "antigravity"])
            self.backend._sessions_future.result(timeout=5)

        self.assertEqual(
            collect.call_args_list,
            [
                mock.call(
                    "query",
                    source_ids=["openai", "antigravity"],
                    limit=60,
                    offset=3,
                )
            ],
        )

    def test_explicit_session_refresh_uses_global_collection(self):
        with mock.patch("app.refresh_sessions", return_value={}) as refresh:
            self.backend.refreshSessionsAndQuery("query", 1, 3)
            self.backend._sessions_future.result(timeout=5)

        self.assertEqual(refresh.call_args_list, [mock.call("query", limit=60, offset=3)])

    def test_explicit_session_refresh_forwards_source_ids_through_windows_bridge(self):
        with mock.patch("app.refresh_sessions_json", return_value='{"sessions":[]}') as refresh:
            self.backend.refreshSessionsAndQuery("query", 1, 3, ["openai", "opencode"])
            self.backend._sessions_future.result(timeout=5)

        self.assertEqual(
            refresh.call_args_list,
            [
                mock.call(
                    "query",
                    source_ids=["openai", "opencode"],
                    limit=60,
                    offset=3,
                )
            ],
        )

    def test_session_refresh_cancels_queued_superseded_future(self):
        release = threading.Event()
        barrier = threading.Barrier(4)
        self.addCleanup(release.set)

        def block_worker():
            barrier.wait()
            release.wait()

        blockers = [self.backend._pool.submit(block_worker) for _ in range(3)]
        barrier.wait(timeout=5)
        with mock.patch("app.collect_sessions_json", return_value='{"sessions":[]}') as collect:
            self.backend.refreshSessions("first", 1, 0)
            first = self.backend._sessions_future
            self.backend.refreshSessions("second", 2, 0)
            second = self.backend._sessions_future

            self.assertTrue(first.cancelled())
            self.assertFalse(second.cancelled())

            release.set()
            for blocker in blockers:
                blocker.result(timeout=5)
            second.result(timeout=5)

        self.assertEqual(collect.call_args_list, [mock.call("second", limit=60, offset=0)])


if __name__ == "__main__":
    unittest.main()
