"""Pieces of the tray app that need no window: putting the environment back
after a refresh, and the single-instance name. Needs PySide6 (app.py imports
it), but no display."""

import importlib.util
import os
import sys
import unittest
from unittest import mock

from _support import REPO

HAS_PYSIDE = importlib.util.find_spec("PySide6") is not None

if HAS_PYSIDE:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    sys.path.insert(0, os.path.join(REPO, "windows"))
    import app

KEYS = ("AIUSAGE_TEST_ADDED", "AIUSAGE_TEST_CHANGED", "AIUSAGE_TEST_REMOVED")


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
class RestoreEnvironTest(unittest.TestCase):
    def setUp(self):
        self.addCleanup(lambda: [os.environ.pop(key, None) for key in KEYS])

    def test_puts_back_only_what_changed(self):
        os.environ["AIUSAGE_TEST_CHANGED"] = "old"
        os.environ["AIUSAGE_TEST_REMOVED"] = "kept"
        saved = dict(os.environ)
        # What a refresh does: the settings' keys exported, one cleared.
        os.environ["AIUSAGE_TEST_ADDED"] = "1"
        os.environ["AIUSAGE_TEST_CHANGED"] = "new"
        del os.environ["AIUSAGE_TEST_REMOVED"]

        deleted = []
        real_delitem = type(os.environ).__delitem__

        def spy(env, key):
            deleted.append(key)
            real_delitem(env, key)

        with mock.patch.object(type(os.environ), "__delitem__", spy):
            app._restore_environ(saved)

        self.assertEqual(dict(os.environ), saved)
        # PATH and the rest were never taken away, not even for a moment.
        self.assertEqual(deleted, ["AIUSAGE_TEST_ADDED"])


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
class ServerNameTest(unittest.TestCase):
    def test_one_per_user(self):
        self.assertRegex(app.SERVER_NAME, r"^ai-usage-widget-tray(-[A-Za-z0-9_.-]+)?$")
        with mock.patch("getpass.getuser", return_value="Jane Doe\\x"):
            self.assertEqual(app._server_name(), "ai-usage-widget-tray-Jane_Doe_x")

    def test_without_a_user_name(self):
        with mock.patch("getpass.getuser", side_effect=OSError):
            self.assertEqual(app._server_name(), "ai-usage-widget-tray")


@unittest.skipUnless(HAS_PYSIDE, "PySide6 not installed")
class CatalogTest(unittest.TestCase):
    """Which translate/*.po Main.qml gets to parse."""

    def test_the_setting_wins_over_the_environment(self):
        with mock.patch.dict(os.environ, {"LANGUAGE": "en"}):
            self.assertIn('msgstr "Paramètres"', app.catalog_text("fr"))

    def test_follows_language_when_nothing_is_chosen(self):
        with mock.patch.dict(os.environ, {"LANGUAGE": "fr_FR:en"}):
            self.assertIn("Language: fr", app.catalog_text(""))

    def test_english_and_odd_names_have_no_catalog(self):
        self.assertEqual(app.catalog_text("en"), "")
        self.assertEqual(app.catalog_text("../fr"), "")

    def test_lists_the_catalogs_present(self):
        self.assertIn("fr", app.catalog_languages())


if __name__ == "__main__":
    unittest.main()
