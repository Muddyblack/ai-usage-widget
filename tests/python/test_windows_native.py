"""Native Windows API failure paths without needing a Windows desktop."""

import ctypes
import importlib.util
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from _support import REPO


def load_native(name, api):
    spec = importlib.util.spec_from_file_location(name, Path(REPO) / "hosts" / "windows" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    with patch.object(ctypes, "windll", api, create=True):
        spec.loader.exec_module(module)
    return module


class BackdropTest(unittest.TestCase):
    def setUp(self):
        self.api = Mock()
        self.api.dwmapi.DwmSetWindowAttribute.return_value = 0
        self.api.dwmapi.DwmExtendFrameIntoClientArea.return_value = 0
        self.module = load_native("backdrop", self.api)
        self.window = Mock()
        self.window.winId.return_value = 0x123456789

    def apply(self, build=22621, light=False):
        with (
            patch.object(ctypes, "windll", self.api, create=True),
            patch.object(self.module.sys, "platform", "win32"),
            patch.object(self.module.sys, "getwindowsversion", return_value=SimpleNamespace(build=build), create=True),
        ):
            return self.module.apply(self.window, light)

    def test_windows_10_does_not_call_dwm(self):
        self.assertFalse(self.apply(build=19045))
        self.api.dwmapi.DwmSetWindowAttribute.assert_not_called()
        self.window.winId.assert_not_called()

    def test_full_width_handle_and_theme_are_passed(self):
        values = {}

        def record(hwnd, attribute, pointer, size):
            self.assertEqual(hwnd.value, 0x123456789)
            self.assertEqual(size, ctypes.sizeof(ctypes.c_int))
            values[attribute] = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_int)).contents.value
            return 0

        self.api.dwmapi.DwmSetWindowAttribute.side_effect = record
        self.assertTrue(self.apply(light=True))
        self.assertEqual(values[20], 0)
        self.assertEqual(values[38], 3)
        self.assertTrue(self.apply(light=False))
        self.assertEqual(values[20], 1)

    def test_failed_backdrop_preserves_qml_fallback(self):
        self.api.dwmapi.DwmSetWindowAttribute.return_value = -1
        self.assertFalse(self.apply())

    def test_failed_frame_does_not_enable_backdrop(self):
        self.api.dwmapi.DwmExtendFrameIntoClientArea.return_value = -1
        self.assertFalse(self.apply())
        self.api.dwmapi.DwmSetWindowAttribute.assert_not_called()


class TaskbarTest(unittest.TestCase):
    def setUp(self):
        self.api = Mock()
        self.api.user32.FindWindowW.return_value = 0x123456789
        self.api.user32.FindWindowExW.return_value = 0x23456789A
        self.api.shell32.SHAppBarMessage.return_value = 0
        self.module = load_native("taskbar", self.api)

    def place(self, bar=(0, 1032, 1920, 1080), tray=(1600, 1032, 1920, 1080)):
        with patch.object(self.module, "_rect", side_effect=[bar, tray]):
            return self.module.place()

    def test_horizontal_taskbar_finds_notification_edge(self):
        self.assertEqual(self.place(), ((0, 1032, 1920, 1080), 1600))

    def test_missing_or_vertical_taskbar_uses_floating_placement(self):
        self.assertIsNone(self.place(bar=None))
        self.assertIsNone(self.place(bar=(0, 0, 48, 1080)))
        self.assertIsNone(self.place(tray=None))

    def test_auto_hide_taskbar_uses_floating_placement(self):
        self.api.shell32.SHAppBarMessage.return_value = 1
        self.assertIsNone(self.place())

    def test_tray_outside_taskbar_is_rejected(self):
        self.assertIsNone(self.place(tray=(-100, 1032, 0, 1080)))

    def test_raise_does_not_activate_or_resize_pill(self):
        window = Mock()
        window.winId.return_value = 0x123456789
        self.module.keep_on_top(window)
        args = self.api.user32.SetWindowPos.call_args.args
        self.assertEqual(args[0].value, 0x123456789)
        self.assertEqual(args[-1], 0x13)


@unittest.skipUnless(importlib.util.find_spec("PySide6"), "PySide6 not installed")
class DockPlacementTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("desktop_dock_test", Path(REPO) / "hosts" / "desktop" / "app.py")
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.tray = self.module.TrayApp.__new__(self.module.TrayApp)
        self.tray.backend = Mock()
        self.tray.backend.loadSettings.return_value = '{"windowsTaskbar":true}'
        self.tray.taskbar_action = Mock()
        self.tray.pill = Mock()
        self.tray.pill.isVisible.return_value = True
        self.tray.pill.width.return_value = 128
        self.tray.pill.height.return_value = 38
        self.properties = {"taskbarDocked": False}
        self.tray.pill.property.side_effect = self.properties.get
        self.tray.pill.setProperty.side_effect = self.properties.__setitem__
        self.tray._place_floating_pill = Mock()
        self.taskbar = Mock()
        self.taskbar.place.return_value = ((0, 1032, 1920, 1080), 1600)
        self.screen = Mock()
        self.screen.geometry.return_value = SimpleNamespace(x=lambda: 0, y=lambda: 0)

    def dock(self, scale=1):
        self.screen.devicePixelRatio.return_value = scale
        with (
            patch.object(self.module, "taskbar", self.taskbar),
            patch.object(self.module.QGuiApplication, "primaryScreen", return_value=self.screen),
            patch.object(self.module, "neutral_text_colour", return_value="#1f1f1f"),
        ):
            return self.tray._dock_pill()

    def test_display_scaling_keeps_pill_next_to_tray(self):
        for scale in (1, 1.25, 1.5):
            with self.subTest(scale=scale):
                self.taskbar.place.return_value = ((0, round(1032 * scale), round(1920 * scale), round(1080 * scale)), round(1600 * scale))
                self.assertTrue(self.dock(scale))
                self.tray.pill.setPosition.assert_called_with(1466, 1037)
                self.assertTrue(self.properties["taskbarLight"])

    def test_docking_disabled_restores_floating_pill(self):
        self.properties["taskbarDocked"] = True
        self.tray.backend.loadSettings.return_value = "{}"
        self.assertFalse(self.dock())
        self.assertFalse(self.properties["taskbarDocked"])
        self.tray._place_floating_pill.assert_called_once()
        self.taskbar.place.assert_not_called()

    def test_pill_too_tall_restores_floating_placement(self):
        self.properties["taskbarDocked"] = True
        self.assertFalse(self.dock(scale=1.5))
        self.tray._place_floating_pill.assert_called_once()
