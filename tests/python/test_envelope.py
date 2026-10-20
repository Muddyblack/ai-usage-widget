"""A provider whose fetch raises costs that provider its tab, not the whole
envelope — in the Windows tray app one exception there used to blank every
provider's data at once."""

import unittest
from unittest import mock

import _support  # noqa: F401 — puts the backend package on sys.path
from tidesi import envelope


def _collect(id_, now):
    if id_ == "claude":
        # What writing a status page with "→" in it through a cp1252 file raised.
        raise UnicodeEncodeError("charmap", "→", 0, 1, "character maps to <undefined>")
    return {"id": id_, "now": now, "inputs": {}}


class ProviderCrashTest(unittest.TestCase):
    def build(self, selected):
        with mock.patch.object(envelope, "collect", _collect):
            return envelope.build(selected, now=1_700_000_000)

    def test_crash_becomes_that_providers_error(self):
        env = self.build(["claude", "elsewhere"])
        claude, other = env["providers"]
        self.assertEqual(claude["id"], "claude")
        self.assertEqual(claude["label"], "Claude")
        self.assertIs(claude["ok"], False)
        self.assertIn("UnicodeEncodeError", claude["error"])
        self.assertIsInstance(claude["details"]["status"], dict)
        # The other provider still came through, crash or not.
        self.assertEqual(other["id"], "elsewhere")

    def test_every_default_provider_has_a_crash_label(self):
        from tidesi import config

        self.assertEqual(sorted(envelope._CRASH_LABELS), sorted(config.ALL_PROVIDERS))


if __name__ == "__main__":
    unittest.main()
