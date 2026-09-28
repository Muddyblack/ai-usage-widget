"""aiusage.historyio on its own, portably — tests/history-io.test.sh drives the
same module through the shell tool on Linux, with the shell's own lock."""

import contextlib
import glob
import io
import json
import os
import shutil
import tempfile
import threading
import unittest
from unittest import mock

import _support  # noqa: F401  (sys.path)
from aiusage import history, historyio


class HistoryIoTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.latest = os.path.join(self.dir, historyio.LATEST_NAME)

    def run_cmd(self, command, payload=""):
        return historyio.run(command, payload, self.dir)

    def on_disk(self):
        with open(self.latest, encoding="utf-8") as fh:
            return fh.read()

    def test_autosave_then_autoload(self):
        self.run_cmd("autosave", '[{"t":1,"w":40}]')
        self.assertEqual(self.run_cmd("autoload"), '{"ok":true,"data":[{"t":1,"w":40}]}')

    def test_save_unions_and_seed_only_fills_in(self):
        self.run_cmd("autosave", '[{"t":2,"za":60}]')
        out = self.run_cmd("autosave", '[{"t":1,"w":40},{"t":3,"cp":7}]')
        self.assertEqual(out, '{"ok":true,"data":[{"t":1,"w":40},{"t":2,"za":60},{"t":3,"cp":7}]}')
        out = self.run_cmd("seed", '[{"t":1,"w":11},{"t":5,"s":1}]')
        self.assertEqual(out, '{"ok":true,"data":[{"t":1,"w":40},{"t":2,"za":60},{"t":3,"cp":7},{"t":5,"s":1}]}')

    def test_save_returns_and_persists_the_normalized_merged_history(self):
        self.run_cmd("autosave", '[{"t":"2","v":60},{"t":1,"w":40}]')

        out = self.run_cmd("autosave", '[{"t":2,"cp":7}]')

        self.assertEqual(
            json.loads(out)["data"],
            [{"t": 1, "w": 40}, {"t": 2, "w": 60, "cp": 7}],
        )
        self.assertEqual(
            json.loads(self.on_disk()),
            [{"t": 1, "w": 40}, {"t": 2, "w": 60, "cp": 7}],
        )

    def test_identical_save_preserves_file_identity_and_mtime(self):
        payload = '[{"t":1,"w":40},{"t":2,"cp":7}]'
        self.run_cmd("autosave", payload)
        before = os.stat(self.latest)

        out = self.run_cmd("autosave", payload)

        after = os.stat(self.latest)
        self.assertEqual(json.loads(out)["data"], json.loads(self.on_disk()))
        self.assertEqual((after.st_ino, after.st_mtime_ns), (before.st_ino, before.st_mtime_ns))
        self.assertEqual(glob.glob(os.path.join(self.dir, ".usage-history.tmp.*")), [])

    def test_empty_payload_never_touches_the_file(self):
        self.run_cmd("autosave", '[{"t":1,"w":1}]')
        before = self.on_disk()
        self.assertEqual(self.run_cmd("autosave", "[]"), '{"ok":true,"empty":true}')
        self.assertEqual(self.run_cmd("autosave", ""), '{"ok":true,"empty":true}')
        self.assertEqual(self.on_disk(), before)

    def test_bad_payloads_are_refused(self):
        self.assertEqual(self.run_cmd("autosave", "{not json"), '{"error":"history payload was not JSON"}')
        self.assertEqual(self.run_cmd("autosave", '{"t":1}'), '{"error":"history payload was not an array"}')

    def test_held_lock_refuses_the_save(self):
        self.run_cmd("autosave", '[{"t":1,"w":1}]')
        before = self.on_disk()
        lock = historyio._acquire(os.path.join(self.dir, historyio.LOCK_NAME), 0)
        self.assertIsNotNone(lock)
        try:
            with mock.patch.dict(os.environ, {"WIDGET_HISTORY_LOCK_WAIT": "0.2"}):
                out = self.run_cmd("autosave", '[{"t":98,"w":98}]')
            self.assertTrue(out.startswith('{"error":"could not lock'), out)
            self.assertEqual(self.on_disk(), before)
            # An export only reads, so the lock is none of its business.
            self.assertTrue(self.run_cmd("export").startswith('{"ok":true,"path"'))
        finally:
            historyio._release(lock)
        self.assertIn('{"t":98,"w":98}', self.run_cmd("autosave", '[{"t":98,"w":98}]'))

    def test_concurrent_saves_keep_every_point(self):
        threads = [threading.Thread(target=self.run_cmd, args=("autosave", f'[{{"t":{i},"w":{i}}}]')) for i in range(1, 13)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(json.loads(self.on_disk())), 12)

    def test_corrupt_file_is_dropped_and_healed(self):
        with open(self.latest, "w", encoding="utf-8") as fh:
            fh.write('[{"t":1,"w":')
        self.assertEqual(self.run_cmd("autoload"), '{"ok":true,"empty":true,"deleted":true}')
        self.assertFalse(os.path.exists(self.latest))
        self.assertEqual(self.run_cmd("autosave", '[{"t":9,"w":90}]'), '{"ok":true,"data":[{"t":9,"w":90}]}')

    def test_export_snapshots_are_distinct_and_verbatim(self):
        self.assertEqual(self.run_cmd("export"), '{"error":"no history to export"}')
        self.run_cmd("autosave", '[{"t":1,"w":40},{"t":3,"w":60}]')
        first = json.loads(self.run_cmd("export"))["path"]
        second = json.loads(self.run_cmd("export"))["path"]
        self.assertNotEqual(first, second)
        for path in (first, second):
            with open(path, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), self.on_disk())
        self.assertEqual(glob.glob(os.path.join(self.dir, historyio.EXPORT_PREFIX + "*")), [])

    def test_import_falls_back_to_the_newest_snapshot(self):
        self.run_cmd("autosave", '[{"t":1,"w":40}]')
        self.run_cmd("export")
        os.unlink(self.latest)
        self.assertEqual(self.run_cmd("import"), '{"ok":true,"data":[{"t":1,"w":40}]}')

    def test_main_reads_the_payload_from_stdin(self):
        # Windows caps one environment variable at 32767 characters, so the tray
        # app never passes a batch that way.
        out = io.StringIO()
        stdin = io.StringIO('[{"t":5,"w":1}]')
        with mock.patch.dict(os.environ, {"XDG_DATA_HOME": self.dir}), mock.patch("sys.stdin", stdin), contextlib.redirect_stdout(out):
            self.assertEqual(historyio.main(["autosave", "--stdin"]), 0)
        self.assertEqual(out.getvalue(), '{"ok":true,"data":[{"t":5,"w":1}]}\n')

    def test_unknown_command(self):
        self.assertEqual(self.run_cmd("bogus"), '{"error":"unknown command"}')

    def test_same_timestamp_merges_keys_and_autosave_overrides(self):
        self.run_cmd("autosave", '[{"t":1,"w":40}]')
        self.assertEqual(json.loads(self.run_cmd("autosave", '[{"t":1,"s":11}]'))["data"], [{"t": 1, "w": 40, "s": 11}])
        before = self.on_disk()
        self.run_cmd("seed", '[{"t":1,"w":99}]')
        self.assertEqual(self.on_disk(), before)
        self.assertEqual(json.loads(self.run_cmd("autosave", '[{"t":1,"w":12}]'))["data"], [{"t": 1, "w": 12, "s": 11}])

    def test_sanitizes_payload_and_enforces_the_shared_cap(self):
        result = json.loads(self.run_cmd("autosave", '[{"t":null,"w":1},{"t":"10","w":100},{"t":11,"w":null}]'))
        self.assertEqual(result["data"], [{"t": 10, "w": 100}, {"t": 11}])
        self.assertEqual(history.DEFAULT_LIMIT, 10000)
        with open(self.latest, "w", encoding="utf-8") as fh:
            json.dump([{"t": i, "w": i} for i in range(10005)], fh)
        self.run_cmd("autosave", '[{"t":99999999,"w":1}]')
        data = json.loads(self.on_disk())
        self.assertEqual(len(data), 10000)
        self.assertEqual(data[0]["t"], 6)

    def test_atomic_save_and_failed_save_preserve_the_old_file(self):
        self.run_cmd("autosave", '[{"t":1,"w":40}]')
        before = self.on_disk()
        replace = history.replace

        def observe(tmp, destination):
            self.assertEqual(self.on_disk(), before)
            self.assertEqual(destination, self.latest)
            with open(tmp, encoding="utf-8") as fh:
                self.assertEqual(json.load(fh), [{"t": 1, "w": 40}, {"t": 2, "s": 12}])
            return replace(tmp, destination)

        with mock.patch.object(history, "replace", side_effect=observe) as publish:
            self.assertTrue(json.loads(self.run_cmd("autosave", '[{"t":2,"s":12}]'))["ok"])
        publish.assert_called_once()
        before = self.on_disk()
        with mock.patch.object(history, "replace", side_effect=OSError("write failed")):
            self.assertIn("error", json.loads(self.run_cmd("autosave", '[{"t":3,"w":90}]')))
        self.assertEqual(self.on_disk(), before)
        self.assertEqual(glob.glob(os.path.join(self.dir, ".usage-history.tmp.*")), [])

    def test_exports_are_invisible_until_complete_and_clean_up_on_failure(self):
        self.run_cmd("autosave", '[{"t":7,"w":70}]')
        before = self.on_disk()
        self.run_cmd("export")
        replace = history.replace

        def observe(tmp, destination):
            snapshots = glob.glob(os.path.join(self.dir, "usage-history-2*.json"))
            self.assertEqual(len(snapshots), 1)
            self.assertEqual(json.loads(self.run_cmd("autoload"))["data"], json.loads(before))
            return replace(tmp, destination)

        with mock.patch.object(history, "replace", side_effect=observe) as publish:
            self.assertTrue(json.loads(self.run_cmd("export"))["ok"])
        publish.assert_called_once()
        with mock.patch.object(history, "replace", side_effect=OSError("write failed")):
            self.assertIn("error", json.loads(self.run_cmd("export")))
        self.assertEqual(len(glob.glob(os.path.join(self.dir, "usage-history-2*.json"))), 2)
        self.assertEqual(glob.glob(os.path.join(self.dir, historyio.EXPORT_PREFIX + "*")), [])
        self.assertEqual(self.on_disk(), before)


if __name__ == "__main__":
    unittest.main()
