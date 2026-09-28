"""The shared settings file is parsed once per unchanged identity.

Every provider and the CLI reach ``config.load_settings()``; re-reading and
re-parsing the same JSON each time is wasted work. The memo is invalidated by
file identity, so a changed — or newly created — settings file is always
re-read, and a returned dict is still safe to mutate without poisoning the
memo.
"""

import json
import os
import time
import unittest
from unittest import mock

from _support import IsolatedHomeTest  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import config


class SettingsCacheTest(IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        config.reset_settings_cache()
        self.addCleanup(config.reset_settings_cache)
        self.path = os.path.join(self.home, "settings.json")

    def _write(self, payload):
        with open(self.path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)

    def test_unchanged_file_is_parsed_once(self):
        self._write({"keys": {"mistral": "sk-1"}, "providers": {"grok": True}})
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path}):
            real_open = open
            opens = []

            def counting_open(path, *args, **kwargs):
                if str(path) == self.path:
                    opens.append(1)
                return real_open(path, *args, **kwargs)

            with mock.patch("builtins.open", side_effect=counting_open):
                first = config.load_settings()
                second = config.load_settings()
                third = config.load_settings()
        self.assertEqual(len(opens), 1)
        self.assertEqual(first, second)
        self.assertEqual(second, third)

    def test_changed_content_is_reread(self):
        self._write({"keys": {"mistral": "sk-1"}})
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path}):
            self.assertEqual(config.load_settings()["keys"]["mistral"], "sk-1")
            self._write({"keys": {"mistral": "sk-2"}})
            future = time.time_ns() + 5_000_000_000
            os.utime(self.path, ns=(future, future))
            self.assertEqual(config.load_settings()["keys"]["mistral"], "sk-2")

    def test_new_file_after_a_miss_is_read(self):
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path}):
            self.assertEqual(config.load_settings(), {})
            self._write({"providers": {"cline": True}})
            self.assertEqual(config.load_settings()["providers"]["cline"], True)

    def test_malformed_file_returns_empty_and_is_not_poisoned(self):
        self._write({"ok": True})
        with open(self.path, "w", encoding="utf-8") as fh:
            fh.write("{not json")
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path}):
            self.assertEqual(config.load_settings(), {})
            self._write({"ok": True})
            future = time.time_ns() + 5_000_000_000
            os.utime(self.path, ns=(future, future))
            self.assertEqual(config.load_settings(), {"ok": True})

    def test_returned_dict_is_isolated_from_the_memo(self):
        self._write({"providers": {"grok": True}})
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path}):
            first = config.load_settings()
            first["providers"]["grok"] = False
            first["injected"] = True
            second = config.load_settings()
        self.assertEqual(second["providers"]["grok"], True)
        self.assertNotIn("injected", second)

    def test_reset_forces_a_fresh_read(self):
        self._write({"ok": True})
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path}):
            config.load_settings()
            config.reset_settings_cache()
            real_open = open
            opens = []

            def counting_open(path, *args, **kwargs):
                if str(path) == self.path:
                    opens.append(1)
                return real_open(path, *args, **kwargs)

            with mock.patch("builtins.open", side_effect=counting_open):
                config.load_settings()
        self.assertEqual(len(opens), 1)

    def test_env_override_still_wins_over_the_file(self):
        self._write({"keys": {"mistral": "from-file"}})
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": self.path, "WIDGET_MISTRAL_API_KEY": "from-env"}):
            config.reset_settings_cache()
            cfg = config.load_settings()
            config.apply_widget_env(cfg)
            self.assertEqual(os.environ["WIDGET_MISTRAL_API_KEY"], "from-env")


if __name__ == "__main__":
    unittest.main()
