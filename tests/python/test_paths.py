import os
import unittest
from unittest import mock

from _support import env_without_xdg
from tidesi import paths


class PathsTest(unittest.TestCase):
    def platform(self, windows=False, macos=False):
        return mock.patch.multiple(paths, IS_WINDOWS=windows, IS_MACOS=macos)

    def test_xdg_wins_on_every_platform(self):
        env = env_without_xdg(XDG_CONFIG_HOME="/x/config", XDG_DATA_HOME="/x/data", XDG_CACHE_HOME="/x/cache")
        for windows, macos in ((False, False), (True, False), (False, True)):
            with self.subTest(windows=windows, macos=macos), mock.patch.dict(os.environ, env, clear=True), self.platform(windows, macos):
                self.assertEqual(paths.config_home(), "/x/config")
                self.assertEqual(paths.data_home(), "/x/data")
                self.assertEqual(paths.cache_home(), "/x/cache")
                self.assertEqual(paths.electron_app_data(), "/x/config")
                self.assertEqual(paths.history_dir(), os.path.join("/x/data", "tidesi"))

    def test_windows_known_folders(self):
        roaming, local = r"C:\Users\u\AppData\Roaming", r"C:\Users\u\AppData\Local"
        env = env_without_xdg(APPDATA=roaming, LOCALAPPDATA=local)
        with mock.patch.dict(os.environ, env, clear=True), self.platform(windows=True):
            self.assertEqual(paths.config_home(), roaming)
            self.assertEqual(paths.data_home(), local)
            # Kept apart from data_home(), which is %LOCALAPPDATA% itself.
            self.assertEqual(paths.cache_home(), os.path.join(local, "cache"))
            self.assertEqual(paths.electron_app_data(), roaming)

    def test_windows_without_the_variables(self):
        with mock.patch.dict(os.environ, env_without_xdg(), clear=True), self.platform(windows=True):
            os.environ.pop("APPDATA", None)
            os.environ.pop("LOCALAPPDATA", None)
            home = os.path.expanduser("~")
            self.assertEqual(paths.config_home(), os.path.join(home, "AppData", "Roaming"))
            self.assertEqual(paths.data_home(), os.path.join(home, "AppData", "Local"))

    def test_linux_defaults(self):
        with mock.patch.dict(os.environ, env_without_xdg(), clear=True), self.platform():
            self.assertEqual(paths.config_home(), os.path.expanduser("~/.config"))
            self.assertEqual(paths.data_home(), os.path.expanduser("~/.local/share"))
            self.assertEqual(paths.cache_home(), os.path.expanduser("~/.cache"))
            self.assertEqual(paths.electron_app_data(), os.path.expanduser("~/.config"))

    def test_macos_electron_app_data(self):
        with mock.patch.dict(os.environ, env_without_xdg(), clear=True), self.platform(macos=True):
            self.assertEqual(paths.electron_app_data(), os.path.expanduser("~/Library/Application Support"))

    def test_no_window(self):
        with self.platform():
            self.assertEqual(paths.no_window(), {})
        if os.name == "nt":
            import subprocess

            self.assertEqual(paths.no_window(), {"creationflags": subprocess.CREATE_NO_WINDOW})


if __name__ == "__main__":
    unittest.main()
