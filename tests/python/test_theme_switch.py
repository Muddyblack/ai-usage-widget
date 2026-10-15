"""Exercise live appearance changes in the real Qt settings layout."""

import importlib.util
import os
import subprocess
import sys
import unittest
from pathlib import Path


class ThemeSwitchTests(unittest.TestCase):
    def test_live_theme_switch(self):
        if importlib.util.find_spec("PySide6") is None:
            if os.environ.get("REQUIRE_FRONTEND_QT") == "1":
                self.fail("PySide6 is required for frontend behavior CI")
            self.skipTest("PySide6 not installed; exercised in Qt CI")
        result = subprocess.run(
            [sys.executable, __file__, "--qml"],
            env={
                **os.environ,
                "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software",
                # Windows Qt sends console.log to the debugger, not stderr.
                "QT_LOGGING_TO_CONSOLE": "1",
            },
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Theme switching passed", result.stdout + result.stderr)


def check_qml():
    from PySide6.QtCore import QUrl, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine

    # Belt and braces for QT_LOGGING_TO_CONSOLE: always reach stderr.
    qInstallMessageHandler(lambda _mode, _ctx, message: print(message, file=sys.stderr, flush=True))
    app = QGuiApplication([])
    engine = QQmlApplicationEngine()
    warnings = []
    engine.warnings.connect(lambda errors: warnings.extend(e.toString() for e in errors))
    engine.quit.connect(app.quit)
    engine.exit.connect(app.exit)
    harness = Path(__file__).resolve().parents[1] / "behavior" / "ThemeSwitchHarness.qml"
    engine.load(QUrl.fromLocalFile(str(harness)))
    assert engine.rootObjects(), warnings
    result = app.exec()
    assert result == 0, result
    assert not warnings, warnings


if __name__ == "__main__":
    if "--qml" in sys.argv:
        check_qml()
    else:
        unittest.main()
