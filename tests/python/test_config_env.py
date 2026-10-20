"""TIDESI_* environment variables, with the pre-rename AI_USAGE_* names as fallback."""

import os
import unittest
from unittest import mock

from _support import IsolatedHomeTest  # noqa: F401  (ensures TOOLS is on sys.path)
from tidesi import config


class EnvFallbackTest(unittest.TestCase):
    def test_new_name_wins(self):
        with mock.patch.dict(os.environ, {"TIDESI_CONFIG": "/new", "AI_USAGE_CONFIG": "/old"}):
            self.assertEqual(config.config_path(), "/new")

    def test_legacy_name_still_works(self):
        with mock.patch.dict(os.environ, {"AI_USAGE_CONFIG": "/old"}):
            os.environ.pop("TIDESI_CONFIG", None)
            self.assertEqual(config.config_path(), "/old")

    def test_default_when_unset(self):
        with mock.patch.dict(os.environ, {}):
            os.environ.pop("TIDESI_STATUS_TTL", None)
            os.environ.pop("AI_USAGE_STATUS_TTL", None)
            self.assertEqual(config.status_ttl(), 300)


if __name__ == "__main__":
    unittest.main()
