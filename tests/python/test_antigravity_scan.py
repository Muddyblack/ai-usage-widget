"""Finding the Antigravity language server: its CSRF token from the command
line and its port from the listening sockets — through /proc on Linux and
psutil everywhere else. A stand-in process plays the server."""

import datetime
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

try:
    import _support  # noqa: F401  (sys.path)
except ModuleNotFoundError:
    from tests.python import _support  # noqa: F401  (sys.path)
from aiusage.providers import antigravity

try:
    import psutil
except ImportError:
    psutil = None

STAND_IN = (
    "import socket, sys, time\ns = socket.socket()\ns.bind(('127.0.0.1', 0))\ns.listen()\nprint(s.getsockname()[1], flush=True)\ntime.sleep(60)\n"
)


class AntigravityScanTest(unittest.TestCase):
    def setUp(self):
        remote = mock.patch("aiusage.providers.antigravity_remote.fetch_instances", return_value=("", None))
        remote.start()
        self.addCleanup(remote.stop)
        self.cache_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.cache_dir.cleanup)
        self.environment = mock.patch.dict(
            os.environ,
            {"AI_USAGE_CACHE_DIR": self.cache_dir.name, "ANTIGRAVITY_TTL_SECONDS": "120"},
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.proc = subprocess.Popen(
            [sys.executable, "-c", STAND_IN, "antigravity-language-server", "--csrf_token", "tok123"],
            stdout=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(self.stop)
        self.port = int(self.proc.stdout.readline())

    def stop(self):
        self.proc.kill()
        self.proc.wait()
        self.proc.stdout.close()

    def check(self):
        found = {str(pid): token for pid, token, _port in antigravity._scan_processes()}
        self.assertEqual(found.get(str(self.proc.pid)), "tok123")
        self.assertIn(self.port, antigravity._pid_listening_ports(self.proc.pid))

    @unittest.skipUnless(psutil, "psutil not installed")
    def test_through_psutil(self):
        with mock.patch.object(antigravity, "_HAS_PROC", False):
            self.check()

    @unittest.skipUnless(os.path.isdir("/proc/self"), "no /proc on this platform")
    def test_through_proc(self):
        with mock.patch.object(antigravity, "_HAS_PROC", True):
            self.check()

    def test_says_what_is_missing_without_either(self):
        no_proc = mock.patch.object(antigravity, "_HAS_PROC", False)
        no_psutil = mock.patch.object(antigravity, "_psutil", lambda: None)
        no_cli = mock.patch.object(antigravity.shutil, "which", lambda _name: None)
        with no_proc, no_psutil, no_cli:
            self.assertIn("psutil", antigravity.get_antigravity_usage()["error"])

    def test_no_process_error_is_not_masked_by_cache(self):
        with open(os.path.join(self.cache_dir.name, "antigravity.json"), "w", encoding="utf-8") as stream:
            json.dump(
                {
                    "fetchedAt": time.time(),
                    "usage": {"method": "cli", "email": None},
                },
                stream,
            )
        no_proc = mock.patch.object(antigravity, "_HAS_PROC", False)
        no_psutil = mock.patch.object(antigravity, "_psutil", lambda: None)
        no_cli = mock.patch.object(antigravity.shutil, "which", lambda _name: None)
        with no_proc, no_psutil, no_cli:
            result = antigravity.get_antigravity_usage()
        self.assertIn("psutil", result["error"])


class AntigravityCacheTest(unittest.TestCase):
    def setUp(self):
        devices = mock.patch("aiusage.providers.antigravity_remote.fetch_instances", return_value=("", None))
        devices.start()
        self.addCleanup(devices.stop)
        self.cache_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.cache_dir.cleanup)
        self.environment = mock.patch.dict(
            os.environ,
            {"AI_USAGE_CACHE_DIR": self.cache_dir.name, "ANTIGRAVITY_TTL_SECONDS": "120"},
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.scan = mock.patch.object(antigravity, "_scan_processes", return_value=[("1", "", "")])
        self.scan.start()
        self.addCleanup(self.scan.stop)
        # The real Remote Control log of whoever runs the tests must not leak in.
        remote = mock.patch.object(antigravity, "remote_control", return_value=None)
        remote.start()
        self.addCleanup(remote.stop)

    @staticmethod
    def _which(name):
        return "/usr/bin/agy" if name == "agy" else None

    @staticmethod
    def _usage():
        return {
            "timestamp": "2026-09-22T12:00:00.000Z",
            "method": "cli",
            "email": None,
            "planType": None,
            "promptCredits": None,
            "models": [{"label": "Gemini", "remainingPercentage": 0.5}],
        }

    def _write_cache(self, usage, fetched_at):
        with open(os.path.join(self.cache_dir.name, "antigravity.json"), "w", encoding="utf-8") as stream:
            json.dump({"fetchedAt": fetched_at, "usage": usage}, stream)

    def test_default_ttl_remains_ninety_seconds_and_override_is_respected(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(antigravity._ttl(), 90)
        with mock.patch.dict(os.environ, {"ANTIGRAVITY_TTL_SECONDS": "45"}):
            self.assertEqual(antigravity._ttl(), 45)

    def test_fresh_cache_avoids_external_probe(self):
        cached = self._usage()
        self._write_cache(cached, time.time())
        expected = dict(cached)
        expected["email"] = "account@example.com"
        expected["source"] = "agy"
        with (
            mock.patch.object(antigravity.shutil, "which", side_effect=self._which),
            mock.patch.object(antigravity, "_run_agy_usage", side_effect=AssertionError("fresh cache must skip agy")),
            mock.patch.object(antigravity, "_account_email", return_value="account@example.com"),
        ):
            result = antigravity.get_antigravity_usage()
        self.assertEqual(result, expected)
        with open(os.path.join(self.cache_dir.name, "antigravity.json"), encoding="utf-8") as stream:
            self.assertIsNone(json.load(stream)["usage"]["email"])

    def test_fresh_cache_precedes_agy_discovery_and_uses_current_account(self):
        cached = self._usage()
        self._write_cache(cached, time.time())
        discovered = []

        def which(name):
            discovered.append(name)
            return None

        with (
            mock.patch.object(antigravity.shutil, "which", side_effect=which),
            mock.patch.object(antigravity, "_account_email", return_value="changed@example.com"),
        ):
            result = antigravity.get_antigravity_usage()
        self.assertEqual(result["email"], "changed@example.com")
        self.assertEqual(result["models"], cached["models"])
        self.assertEqual(discovered, ["aiu", "antigravity-usage"])

    def test_fresh_cache_survives_different_clock_precision(self):
        now = 1_790_078_400.123456
        coarse_now = datetime.datetime.fromtimestamp(now - 0.01, datetime.timezone.utc)
        with (
            mock.patch.object(antigravity.datetime, "datetime", wraps=datetime.datetime) as datetime_clock,
            mock.patch("time.time", return_value=now),
            mock.patch.object(antigravity, "_account_email", return_value=None),
        ):
            # On Windows, datetime.now() can lag time.time() in precision.
            datetime_clock.now.return_value = coarse_now
            self._write_cache(self._usage(), now)
            self.assertEqual(antigravity._read_cache(120), self._usage())
            antigravity._write_cache(self._usage())
            with open(os.path.join(self.cache_dir.name, "antigravity.json"), encoding="utf-8") as stream:
                self.assertEqual(json.load(stream)["fetchedAt"], now)

    def test_malformed_and_future_cache_fall_through_to_agy(self):
        for fetched_at, contents in ((time.time(), "{"), (time.time() + 1, None)):
            with self.subTest(fetched_at=fetched_at):
                if contents is None:
                    self._write_cache(self._usage(), fetched_at)
                else:
                    with open(os.path.join(self.cache_dir.name, "antigravity.json"), "w", encoding="utf-8") as stream:
                        stream.write(contents)
                with (
                    mock.patch.object(antigravity.shutil, "which", side_effect=self._which),
                    mock.patch.object(antigravity, "_run_agy_usage", return_value={"groups": []}) as run_agy,
                    mock.patch.object(antigravity, "_format_agy_usage", return_value=self._usage()),
                ):
                    antigravity.get_antigravity_usage()
                run_agy.assert_called_once_with("/usr/bin/agy")
                run_agy.reset_mock()

    def test_account_change_never_persists_email_identity(self):
        live = self._usage()
        live["email"] = "old@example.com"
        with (
            mock.patch.object(antigravity.shutil, "which", side_effect=self._which),
            mock.patch.object(antigravity, "_run_agy_usage", return_value={"groups": []}),
            mock.patch.object(antigravity, "_format_agy_usage", return_value=live),
        ):
            antigravity.get_antigravity_usage()
        with open(os.path.join(self.cache_dir.name, "antigravity.json"), encoding="utf-8") as stream:
            persisted = json.load(stream)
        self.assertIsNone(persisted["usage"]["email"])
        with mock.patch.object(antigravity, "_account_email", return_value="new@example.com"):
            self.assertEqual(antigravity._read_cache(120)["email"], "new@example.com")

    def test_expired_cache_falls_through_to_external_probe(self):
        self._write_cache(self._usage(), time.time() - 121)
        live = self._usage()
        live["timestamp"] = "2026-09-22T12:02:00.000Z"
        with (
            mock.patch.object(antigravity.shutil, "which", side_effect=self._which),
            mock.patch.object(antigravity, "_run_agy_usage", return_value={"groups": []}) as run_agy,
            mock.patch.object(antigravity, "_format_agy_usage", return_value=live),
        ):
            result = antigravity.get_antigravity_usage()
        self.assertEqual(result, {**live, "source": "agy"})
        run_agy.assert_called_once_with("/usr/bin/agy")
        with open(os.path.join(self.cache_dir.name, "antigravity.json"), encoding="utf-8") as stream:
            self.assertIsNone(json.load(stream)["usage"]["email"])

    def test_structural_empty_agy_success_is_cached(self):
        with (
            mock.patch.object(antigravity.shutil, "which", side_effect=self._which),
            mock.patch.object(antigravity, "_run_agy_usage", return_value={"groups": []}) as run_agy,
        ):
            result = antigravity.get_antigravity_usage()
        self.assertEqual(result["models"], [])
        run_agy.assert_called_once_with("/usr/bin/agy")
        with open(os.path.join(self.cache_dir.name, "antigravity.json"), encoding="utf-8") as stream:
            self.assertEqual(json.load(stream)["usage"]["models"], [])

    def test_error_result_is_not_cached(self):
        with (
            mock.patch.object(antigravity.shutil, "which", side_effect=self._which),
            mock.patch.object(antigravity, "_run_agy_usage", return_value=None),
        ):
            result = antigravity.get_antigravity_usage()
        self.assertIn("error", result)
        self.assertFalse(os.path.exists(os.path.join(self.cache_dir.name, "antigravity.json")))


if __name__ == "__main__":
    unittest.main()
