"""Settings, history and caches move from the pre-rename folders to tidesi/."""

import os
import tempfile
import unittest
from unittest import mock

from _support import env_without_xdg
from tidesi import paths


def write(path, text="x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(__import__("shutil").rmtree, self.root, True)
        env = env_without_xdg(
            XDG_CONFIG_HOME=os.path.join(self.root, "config"),
            XDG_DATA_HOME=os.path.join(self.root, "data"),
            XDG_CACHE_HOME=os.path.join(self.root, "cache"),
        )
        patcher = mock.patch.dict(os.environ, env, clear=True)
        patcher.start()
        self.addCleanup(patcher.stop)
        paths._MIGRATED.clear()
        self.addCleanup(paths._MIGRATED.clear)

    def path(self, *parts):
        return os.path.join(self.root, *parts)

    def test_old_folder_is_renamed(self):
        write(self.path("config", "ai-usage-widget", "hyprland-settings.json"), "{}")
        self.assertEqual(paths.config_dir(), self.path("config", "tidesi"))
        self.assertTrue(os.path.isfile(self.path("config", "tidesi", "hyprland-settings.json")))
        self.assertFalse(os.path.exists(self.path("config", "ai-usage-widget")))

    def test_both_kde_ai_usage_and_app_folder_merge_into_one(self):
        write(self.path("data", "ai-usage-widget", "usage-history-latest.json"))
        write(self.path("data", "kde-ai-usage", "claude-stats.json"))
        data = paths.data_dir()
        self.assertEqual(sorted(os.listdir(data)), ["claude-stats.json", "usage-history-latest.json"])

    def test_existing_new_files_win(self):
        write(self.path("config", "tidesi", "hyprland-settings.json"), "new")
        write(self.path("config", "ai-usage-widget", "hyprland-settings.json"), "old")
        write(self.path("config", "ai-usage-widget", "other.json"), "kept")
        paths.config_dir()
        with open(self.path("config", "tidesi", "hyprland-settings.json"), encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "new")
        self.assertTrue(os.path.isfile(self.path("config", "tidesi", "other.json")))
        # The clashing old copy is left behind as a backup, never deleted.
        self.assertEqual(os.listdir(self.path("config", "ai-usage-widget")), ["hyprland-settings.json"])

    def test_widget_settings_follow_the_new_widget_id(self):
        write(self.path("config", "ai-usage-widget", "plasma-shared-settings-org.muddyblack.aiUsageWidget.json"))
        write(self.path("config", "ai-usage-widget", "plasma-shared-settings-org.muddyblack.aiUsageWidgetTest.json"))
        names = sorted(os.listdir(paths.config_dir()))
        self.assertEqual(
            names,
            [
                "plasma-shared-settings-org.muddyblack.tidesi.json",
                "plasma-shared-settings-org.muddyblack.tidesiTest.json",
            ],
        )

    def test_nothing_to_migrate_creates_nothing(self):
        paths.cache_dir()
        self.assertFalse(os.path.exists(self.path("cache", "tidesi")))


if __name__ == "__main__":
    unittest.main()
