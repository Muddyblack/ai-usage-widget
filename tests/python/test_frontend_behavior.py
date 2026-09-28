"""Shared expectations for backend output and the real Hyprland/Windows rows."""

import importlib.util
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

from _support import REPO


def scenarios():
    return json.loads(subprocess.check_output([sys.executable, str(Path(REPO) / "scripts/frontend-fixtures.py")], text=True))


class FrontendBehaviorTest(unittest.TestCase):
    def test_backend_matches_reviewed_expectations(self):
        for case in scenarios():
            with self.subTest(case=case["name"]):
                p = case["envelope"]["providers"][0]
                expected = case["expected"]
                self.assertEqual([r["key"] for r in p.get("quotaWindows", []) if r.get("available") is True], expected["rowKeys"])
                self.assertEqual([r["pct"] for r in p.get("quotaWindows", []) if r.get("available") is True], expected["rowValues"])
                self.assertEqual(p.get("historyValues", {}), expected["history"])

    def test_qml_quota_delegates(self):
        if importlib.util.find_spec("PySide6") is None:
            if os.environ.get("REQUIRE_FRONTEND_QT") == "1":
                self.fail("PySide6 is required for frontend behavior CI")
            self.skipTest("PySide6 not installed; exercised in Windows/Linux Qt CI")
        result = subprocess.run(
            [sys.executable, __file__, "--qml"],
            env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software"),
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_panel_and_stale_fixture_matrix_covers_requested_boundaries(self):
        cases = scenarios()
        threshold_cases = {case["name"]: case for case in cases if case["name"].startswith("panel-threshold-")}
        self.assertEqual(
            sorted(int(name.rsplit("-", 1)[1]) for name in threshold_cases),
            [0, 69, 70, 89, 90, 100],
        )
        for value, case in ((int(name.rsplit("-", 1)[1]), case) for name, case in threshold_cases.items()):
            self.assertEqual(case["expected"]["rowValues"], [value])
            self.assertEqual(case["expected"]["panelText"], [f"{value}%"])

        stale_path = Path(REPO) / "tests/behavior/stale-state.json"
        stale = json.loads(stale_path.read_text(encoding="utf-8"))
        self.assertEqual(
            {case["name"] for case in stale},
            {
                "valid-live",
                "transient-empty",
                "timeout-error",
                "stale-good-age",
                "expired-no-cache",
                "changed-account-identity",
                "late-request-generation",
            },
        )
        for case in stale[:-1]:
            self.assertEqual(set(case["expected"]), {"accountId", "pct", "available", "stale", "error"})
        self.assertEqual(stale[-1]["expected"], {"accepted": False, "lastGoodPct": 69})


def check_qml():
    from PySide6.QtCore import QObject, QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtQuick import QQuickItem

    app = QGuiApplication([])
    engine = QQmlEngine()
    warnings = []
    engine.warnings.connect(lambda errors: warnings.extend(e.toString() for e in errors))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(Path(REPO) / "tests/behavior/UsageRowsHarness.qml")))
    assert component.isReady(), [e.toString() for e in component.errors()]
    view = component.create()
    assert isinstance(view, QQuickItem)
    rows = view.findChild(QObject, "rows")
    assert rows is not None

    def quota_items(item):
        # Repeater delegates are visual children, not necessarily QObject
        # children of the layout (findChild does not reliably find them).
        found = [item] if item.objectName().startswith("quota-") else []
        for child in item.childItems():
            found.extend(quota_items(child))
        return found

    # Reuse one component to catch stale delegates when switching providers.
    for case in scenarios():
        assert view.setProperty("envelopeJson", json.dumps(case["envelope"]))
        app.processEvents()
        expected = case["expected"]["rowKeys"]
        assert rows.property("rowCount") == len(expected), case["name"]
        items = quota_items(view)
        assert [item.objectName()[6:] for item in items] == expected, case["name"]
        assert [item.property("value") for item in items] == case["expected"]["rowValues"], case["name"]
        provider = case["envelope"]["providers"][0]
        for key, row in zip(expected, items):
            source = next(w for w in provider["quotaWindows"] if w["key"] == key)
            assert row.property("value") == source["pct"], (case["name"], key)
            assert row.property("label") == source["label"], (case["name"], key)
            assert row.property("showMeter") == source.get("showMeter", True)
    assert not warnings, warnings
    del view
    del component
    del engine


if __name__ == "__main__":
    if "--qml" in sys.argv:
        check_qml()
    else:
        unittest.main()
