"""The codex app-server client against a fake `codex` on PATH — a shell script
on POSIX, a .cmd shim on Windows, the way npm installs the real one there."""

import os
import shutil
import stat
import sys
import tempfile
import time
import unittest
from unittest import mock

import _support  # noqa: F401  (sys.path)
from aiusage.providers.codex_rate_limits import get_codex_rate_limits

FAKE_SERVER = r"""
import json, os, sys, queue, threading
pid_file = os.environ.get("FAKE_CODEX_PID")
if pid_file:
    with open(pid_file, "w") as fh:
        fh.write(str(os.getpid()))
def read_line():
    line = b""
    while not line.endswith(b"\n"):
        chunk = os.read(sys.stdin.fileno(), 1)
        if not chunk:
            break
        line += chunk
    return line

read_line()
# The client must await initialize's response before sending the next RPC.
# A thread works with anonymous pipes on Windows, where select() does not.
pending = queue.Queue()
reader = threading.Thread(target=lambda: pending.put(read_line()), daemon=True)
reader.start()
try:
    pending.get(timeout=0.05)
except queue.Empty:
    pass
else:
    print(json.dumps({"id": 1, "result": {}}), flush=True)
    sys.exit(0)
print(json.dumps({"id": 1, "result": {"userAgent": "test"}}), flush=True)
pending.get(timeout=10)
reader.join()
if os.environ.get("FAKE_CODEX_MODE") == "closed":
    sys.exit(0)
if os.environ.get("FAKE_CODEX_MODE") == "ok":
    limits = {"primary": {"usedPercent": 42, "windowDurationMins": 10080, "resetsAt": 200}}
    print(json.dumps({"id": 2, "result": {"rateLimits": limits}}), flush=True)
# Stay up like the real server, until stdin closes or it is killed.
sys.stdin.read()
"""


def _pid_alive(pid):
    import psutil

    try:
        return psutil.Process(pid).status() != psutil.STATUS_ZOMBIE
    except psutil.NoSuchProcess:
        return False


class CodexRateLimitsTest(unittest.TestCase):
    def setUp(self):
        self.bin = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.bin, True)
        server = os.path.join(self.bin, "fake_codex.py")
        with open(server, "w", encoding="utf-8") as fh:
            fh.write(FAKE_SERVER)
        if os.name == "nt":
            with open(os.path.join(self.bin, "codex.cmd"), "w", encoding="utf-8") as fh:
                fh.write(f'@echo off\r\n"{sys.executable}" "{server}" %*\r\n')
        else:
            shim = os.path.join(self.bin, "codex")
            with open(shim, "w", encoding="utf-8") as fh:
                fh.write(f'#!/bin/sh\nexec "{sys.executable}" "{server}" "$@"\n')
            os.chmod(shim, os.stat(shim).st_mode | stat.S_IEXEC)
        self.pid_file = os.path.join(self.bin, "pid")

    def call(self, mode):
        env = {"PATH": self.bin + os.pathsep + os.environ.get("PATH", ""), "FAKE_CODEX_MODE": mode, "FAKE_CODEX_PID": self.pid_file}
        with mock.patch.dict(os.environ, env):
            return get_codex_rate_limits()

    def test_reads_the_rate_limits(self):
        result = self.call("ok")
        self.assertEqual(result["rateLimits"]["primary"]["usedPercent"], 42)
        self.assertEqual(result["rateLimits"]["primary"]["windowDurationMins"], 10080)

    def test_a_server_that_never_answers_gives_up(self):
        started = time.monotonic()
        self.assertEqual(self.call("silent"), {})
        self.assertLess(time.monotonic() - started, 15)

    def test_no_codex_on_path(self):
        with mock.patch.dict(os.environ, {"PATH": tempfile.gettempdir()}):
            self.assertEqual(get_codex_rate_limits(), {})

    def test_a_server_that_exits_without_limits_returns_empty(self):
        self.assertEqual(self.call("closed"), {})

    @unittest.skipUnless(shutil.which("true") or os.name == "nt", "needs a shell")
    def test_the_server_does_not_outlive_the_call(self):
        # On Windows the child is cmd.exe and the server its grandchild; only a
        # tree kill takes both.
        try:
            import psutil  # noqa: F401
        except ImportError:
            self.skipTest("psutil not installed")
        self.call("ok")
        with open(self.pid_file, encoding="utf-8") as fh:
            pid = int(fh.read())
        deadline = time.monotonic() + 5
        while _pid_alive(pid) and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertFalse(_pid_alive(pid), "the fake server was left running")


if __name__ == "__main__":
    unittest.main()
