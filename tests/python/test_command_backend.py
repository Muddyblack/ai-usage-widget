"""ui/CommandBackend.qml + ui/AppState.qml, the state every process-based host
(Quickshell, KDE Plasma) shares, driven end to end against the real backend
tools. A Python runner stands in for the host's process launcher, which is the
only part a host adds. Needs PySide6; Linux/macOS only (the tools are sh)."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

from _support import REPO

HAS_PYSIDE = importlib.util.find_spec("PySide6") is not None

HARNESS = r"""
import QtQuick
import "%(ui)s"

Item {
    id: root
    CommandBackend {
        id: commandBackend
        runner: pyRunner
        toolsDir: "%(repo)s/backend/sh"
        translateDir: "%(repo)s/translate"
        assetsDir: "%(repo)s/assets"
        configPath: "%(config)s"
        systemLanguages: ["fr"]
    }

    AppState {
        id: appState
        objectName: "appState"
        backend: commandBackend
        popupVisible: true
    }
}
"""

SCRIPT = r"""
import json, os, subprocess, sys, threading
from PySide6.QtCore import QObject, QTimer, QUrl, Signal, Slot, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine, QJSValue

app = QGuiApplication(sys.argv)
engine = QQmlEngine()
warnings = []
engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))


class Runner(QObject):
    # Only a job number crosses threads; the results stay in a dict.
    _done = Signal(int)

    def __init__(self):
        super().__init__()
        self._done.connect(self._deliver, Qt.QueuedConnection)
        self.ran = []
        self.jobs = {}

    @Slot(list, QJSValue)
    def run(self, argv, callback):
        self.ran.append(list(argv))
        job = len(self.ran)
        self.jobs[job] = [QJSValue(callback), None]

        def work():
            p = subprocess.run(argv, capture_output=True, text=True)
            self.jobs[job][1] = (p.stdout, p.stderr, p.returncode)
            self._done.emit(job)

        threading.Thread(target=work, daemon=True).start()

    @Slot(int)
    def _deliver(self, job):
        cb, (out, err, code) = self.jobs.pop(job)
        # Wrapped: PySide fails to convert some plain str arguments here.
        cb.call([QJSValue(out), QJSValue(err), QJSValue(code)])


runner = Runner()
engine.rootContext().setContextProperty("pyRunner", runner)
component = QQmlComponent(engine)
component.setData(sys.argv[1].encode(), QUrl.fromLocalFile(sys.argv[2]))
root = component.create()
if root is None:
    print(json.dumps({"error": [e.toString() for e in component.errors()]}))
    sys.exit(1)
state = root.findChild(QObject, "appState")

def finish():
    s = state.property("settings").toVariant()
    print(json.dumps({
        "warnings": warnings,
        "ready": state.property("providerDefaultsReady"),
        "loading": state.property("loading"),
        "providers": [p["id"] for p in state.property("providers").toVariant()],
        "errorText": state.property("errorText"),
        "languages": state.property("availableLanguages").toVariant(),
        "translated": state.property("pillSlots").toVariant()[0]["tooltip"] if state.property("pillSlots").toVariant() else "",
        "settingsApplied": s.get("providerDefaultsApplied"),
        "commands": [arg for c in runner.ran for arg in c[5:]],
        "pinned": state.property("pinnedTabs").toVariant(),
        "panel": [g["id"] for g in state.property("panelGroups").toVariant()],
    }))
    app.quit()

def poll(n=[0]):
    n[0] += 1
    if (state.property("providerDefaultsReady") and not state.property("loading")
            and state.property("availableLanguages").toVariant()) or n[0] > 300:
        QTimer.singleShot(300, finish)
    else:
        QTimer.singleShot(100, poll)

QTimer.singleShot(100, poll)
app.exec()
"""


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
@unittest.skipIf(sys.platform == "win32", "the command backend runs sh tools")
class CommandBackendTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def run_harness(self, settings):
        config = os.path.join(self.tmp, "settings.json")
        if settings is not None:
            with open(config, "w", encoding="utf-8") as fh:
                json.dump(settings, fh)
        qml = HARNESS % {"ui": "file://" + os.path.join(REPO, "ui"), "repo": REPO, "config": config}
        script = os.path.join(self.tmp, "harness.py")
        with open(script, "w", encoding="utf-8") as fh:
            fh.write(SCRIPT)
        env = dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            AI_USAGE_CONFIG=config,
            HOME=self.tmp,
            XDG_CONFIG_HOME=os.path.join(self.tmp, "config"),
            XDG_DATA_HOME=os.path.join(self.tmp, "data"),
            XDG_CACHE_HOME=os.path.join(self.tmp, "cache"),
        )
        proc = subprocess.run(
            [sys.executable, script, qml, os.path.join(self.tmp, "Harness.qml")],
            capture_output=True,
            text=True,
            env=env,
            timeout=120,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return json.loads(proc.stdout.strip().splitlines()[-1]), config

    def test_first_start_initializes_defaults_then_refreshes(self):
        result, config = self.run_harness(None)
        self.assertEqual(result["warnings"], [])
        self.assertTrue(result["ready"])
        self.assertTrue(result["settingsApplied"])
        self.assertEqual(result["errorText"], "")
        self.assertIn("fr", result["languages"])
        # Settings, catalog list, history, defaults, then the usage fetch,
        # which keeps its answer for the next start's replay.
        self.assertIn("--initialize-provider-defaults", result["commands"])
        self.assertIn("--all", result["commands"])
        self.assertIn("--save-snapshot", result["commands"])
        self.assertIn("--last-snapshot", result["commands"])

    def test_latched_defaults_go_straight_to_the_fetch(self):
        result, _ = self.run_harness({"providerDefaultsApplied": True, "providers": {}})
        self.assertEqual(result["warnings"], [])
        self.assertTrue(result["ready"])
        self.assertNotIn("--initialize-provider-defaults", result["commands"])
        self.assertIn("--all", result["commands"])

    def test_pins_keep_only_enabled_providers_on_the_panel(self):
        result, _ = self.run_harness({"providerDefaultsApplied": True, "providers": {"claude": True}, "pinnedTabs": ["claude", "gone", "sessions"]})
        self.assertEqual(result["warnings"], [])
        # A pin for a provider no longer enabled, or for a feature tab, drops out.
        self.assertEqual(result["pinned"], ["claude"])
        self.assertEqual(result["panel"], ["claude"])


if __name__ == "__main__":
    unittest.main()
