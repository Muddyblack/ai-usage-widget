"""Portable checks for screenshot composition; rendering is verified by macOS CI."""

import unittest
from pathlib import Path

from _support import REPO

SOURCES = Path(REPO) / "macos/Sources/AIUsage"


class ScreenshotCompositionTests(unittest.TestCase):
    def test_provider_artwork_is_outside_the_native_menu_label(self):
        source = (SOURCES / "Views/UsageView.swift").read_text()
        header = source.split("private var header: some View", 1)[1].split("@ViewBuilder", 1)[0]
        self.assertLess(header.index("providerIcon"), header.index("providerPicker"))
        icon = source.split("private var providerIcon: some View", 1)[1].split("private var providerPicker", 1)[0]
        self.assertIn("Artwork.providerImage", icon)
        self.assertIn("Artwork.fallbackSymbol", icon)
        self.assertIn(".renderingMode(.original)", icon)
        picker = source.split("private var providerPicker: some View", 1)[1].split("private var overflowMenu", 1)[0]
        self.assertNotIn("Image(nsImage:", picker)

    def test_only_expanded_popover_is_captured_in_both_appearances(self):
        source = (SOURCES / "App/ScreenshotSession.swift").read_text()
        self.assertIn('"popover-expanded-\\(scheme.name)"', source)
        for name in ("popover", "screen", "settings"):
            self.assertIn(f'"{name}-dark"', source)
            self.assertNotIn(f'"{name}-light"', source)
            self.assertNotIn(f'"{name}-\\(scheme.name)"', source)
