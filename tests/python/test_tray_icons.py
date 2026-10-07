"""Which icons the tray shows for a published state, and that each one draws.
Needs PySide6 (app.py imports it), but no display: offscreen is enough."""

import importlib.util
import os
import sys
import unittest

from _support import REPO

HAS_PYSIDE = importlib.util.find_spec("PySide6") is not None
CLAUDE_LOGO = "file://" + os.path.join(REPO, "assets", "icons", "claude-color.svg")

if HAS_PYSIDE:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    sys.path.insert(0, os.path.join(REPO, "hosts", "desktop"))
    import app
    from PySide6.QtGui import QColor, QGuiApplication


def slot(pct, color="#ff4d4d", text=None, tooltip=""):
    return {"pct": pct, "color": color, "text": text, "tooltip": tooltip}


TWO = [slot(5, text="5%", tooltip="5-hour: 5%"), slot(83, "#ffa64d")]


def kinds(entries):
    return [e["kind"] for e in entries]


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
class TrayEntriesTest(unittest.TestCase):
    def test_default_is_the_ring_on_windows_only(self):
        self.assertEqual(app.DEFAULT_TRAY_STYLE, "ring" if os.name == "nt" else "icons")
        self.assertEqual(app.tray_style({}), app.DEFAULT_TRAY_STYLE)
        self.assertEqual(app.tray_style({"style": "bogus"}), app.DEFAULT_TRAY_STYLE)

    def test_icons_style_reads_like_the_panel_pill(self):
        entries = app.tray_entries({"style": "icons", "icon": CLAUDE_LOGO, "slots": TWO})
        self.assertEqual(kinds(entries), ["tinted", "percent", "tinted", "percent"])
        self.assertEqual([(e["value"], e["color"]) for e in entries if e["kind"] == "percent"], [(5, "#ff4d4d"), (83, "#ffa64d")])
        self.assertEqual([e["color"] for e in entries if e["kind"] == "tinted"], ["#ff4d4d", "#ffa64d"])
        self.assertEqual(entries[0]["tooltip"], "5-hour: 5%")

    def test_numbers_are_neutral_until_worth_a_look(self):
        # As on the panel pill: the logo has the provider's colour, the number
        # stays neutral ("") below 70 %, then amber, then red from 90 %.
        values = [slot(5), slot(83), slot(95)]
        entries = app.tray_entries({"style": "icons", "slots": values})
        self.assertEqual([e["textColor"] for e in entries if e["kind"] == "percent"], ["", "#ffa64d", "#ff4d4d"])
        if os.name != "nt":
            # Windows reads its taskbar's light/dark setting instead.
            self.assertEqual(app.neutral_text_colour(), "#f8fafc")

    def test_numbers_style_is_the_logo_then_digits(self):
        entries = app.tray_entries({"style": "numbers", "icon": CLAUDE_LOGO, "tooltip": "AI Usage\nClaude: 5%", "slots": TWO})
        self.assertEqual(kinds(entries), ["logo", "number", "number"])
        self.assertEqual(entries[0]["tooltip"], "AI Usage\nClaude: 5%")

    def test_ring_style_and_the_old_numbers_off_switch(self):
        ring = [{"kind": "ring", "value": 5, "color": "#ff4d4d", "icon": CLAUDE_LOGO, "tooltip": app.APP_NAME}]
        self.assertEqual(app.tray_entries({"style": "ring", "icon": CLAUDE_LOGO, "slots": TWO}), ring)
        self.assertEqual(app.tray_entries({"numbers": False, "icon": CLAUDE_LOGO, "slots": TWO}), ring)

    def test_full_windows_and_non_percentages(self):
        self.assertEqual(app.tray_entries({"style": "icons", "slots": [slot(99.7)]})[1]["value"], 100)
        self.assertEqual(kinds(app.tray_entries({"style": "icons", "slots": [slot(0, text="$49.59")]})), ["ring"])
        self.assertEqual(app.tray_entries({})[0]["value"], -1)

    def test_every_kind_draws(self):
        QGuiApplication.instance() or QGuiApplication([])
        for entry in (
            {"kind": "percent", "value": 5, "textColor": "#ff4d4d"},
            {"kind": "percent", "value": 83, "textColor": "#ff4d4d"},
            {"kind": "percent", "value": 100, "textColor": "#ff4d4d"},
            {"kind": "tinted", "icon": CLAUDE_LOGO, "color": "#ff4d4d"},
            {"kind": "number", "value": 93, "textColor": "#ff4d4d"},
            {"kind": "ring", "value": 40, "color": "#ff4d4d", "icon": CLAUDE_LOGO},
        ):
            with self.subTest(entry=entry):
                image = app.render_entry(entry).pixmap(64, 64).toImage()
                reds = sum(
                    1
                    for x in range(0, 64, 2)
                    for y in range(0, 64, 2)
                    if QColor(image.pixel(x, y)).red() > 200 and QColor(image.pixel(x, y)).green() < 120 and QColor(image.pixel(x, y)).alpha() > 128
                )
                self.assertGreater(reds, 10, "hardly any of the slot's colour was drawn")
        for icon in (CLAUDE_LOGO, ""):
            with self.subTest(logo=icon):
                self.assertFalse(app.render_entry({"kind": "logo", "icon": icon}).pixmap(32, 32).isNull())


if __name__ == "__main__":
    unittest.main()
