"""The tray app's QML loads without a single warning — the shared popup and
settings page included — and its plain helpers behave. Needs PySide6."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

from _support import REPO

APP = os.path.join(REPO, "windows", "app.py")
HAS_PYSIDE = importlib.util.find_spec("PySide6") is not None
# Every provider off, so nothing here depends on the network.
ALL_OFF = {"providers": dict.fromkeys(("claude", "antigravity", "openai", "kiro", "mistral", "openrouter", "grok"), False)}


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
class TrayAppTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def env(self, settings):
        config = os.path.join(self.tmp, "settings.json")
        with open(config, "w", encoding="utf-8") as fh:
            json.dump(settings, fh)
        return dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            PYTHONFAULTHANDLER="1",
            AI_USAGE_CONFIG=config,
            XDG_DATA_HOME=os.path.join(self.tmp, "data"),
            XDG_CACHE_HOME=os.path.join(self.tmp, "cache"),
        )

    def selftest(self, settings, **extra):
        return subprocess.run([sys.executable, APP, "--selftest"], env=dict(self.env(settings), **extra), capture_output=True, text=True, timeout=120)

    def test_popup_and_every_settings_section_load_cleanly(self):
        # The selftest itself opens each settings section in turn. The
        # floating pill is on too, so its window loads and draws as well.
        result = self.selftest(dict(ALL_OFF, floatingPill=True))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_loads_cleanly_translated(self):
        # translate/fr.po parsed by I18n.js: a bad catalog or a shell.i18n call
        # the QML cannot resolve shows up as a warning, which fails the selftest.
        result = self.selftest(dict(ALL_OFF, floatingPill=True), LANGUAGE="fr")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_runs_without_stdout_or_stderr(self):
        # The .exe is a windowed build with no console, where sys.stdout and
        # sys.stderr are None. A bare .flush() on them raised, which the
        # bootloader turns into a modal error dialog: on every quit, and in
        # CI's check of the built .exe, where nobody can click it away.
        windowed = (
            f"import runpy, sys; sys.stdout = sys.stderr = None; sys.argv = [{APP!r}, '--selftest']; runpy.run_path({APP!r}, run_name='__main__')"
        )
        result = subprocess.run([sys.executable, "-c", windowed], env=self.env(ALL_OFF), capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, "the selftest failed with sys.stdout and sys.stderr set to None, as in the .exe")


if __name__ == "__main__":
    unittest.main()
