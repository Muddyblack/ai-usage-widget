import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "backend"))

from aiusage.normalize.antigravity import normalize_antigravity
from aiusage.providers import antigravity

ENABLED = "[RemoteControl] RemoteControlEnabled value: true\n"
CONNECTED = "[remote-control-x-v2] Connection status: Connected\n"
CLOSED = "[remote-control-x-v2] Connection loop exited: WebChannel connection closed\n"


class RemoteControlTest(unittest.TestCase):
    def read(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "language_server.log")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            return antigravity.remote_control([path])

    def test_connected(self):
        self.assertEqual(self.read("noise\n" + ENABLED + CONNECTED), {"enabled": True, "connected": True})

    def test_closed_connection_is_offline(self):
        self.assertEqual(self.read(ENABLED + CONNECTED + CLOSED), {"enabled": True, "connected": False})

    def test_disabled_is_never_connected(self):
        off = "RemoteControlEnabled value: false\n"
        self.assertEqual(self.read(ENABLED + CONNECTED + off), {"enabled": False, "connected": False})

    def test_no_events_or_no_log_is_unknown(self):
        self.assertIsNone(self.read("nothing relevant\n"))
        self.assertIsNone(antigravity.remote_control([os.path.join(tempfile.gettempdir(), "no-such-agy.log")]))

    def test_reported_in_details_for_the_tab(self):
        usage = {"models": [], "planType": "Starter", "remote": {"enabled": True, "connected": True}}
        result = normalize_antigravity({"now": 1, "inputs": {"usage": usage}})
        remote = result["details"]["remote"]
        self.assertEqual((remote["state"], remote["url"]), ("online", "https://antigravity.google.com/"))
        self.assertEqual([c["text"] for c in result["account"]["chips"]], ["Starter"])

    def test_no_log_means_no_remote_tab(self):
        result = normalize_antigravity({"now": 1, "inputs": {"usage": {"models": [], "planType": "Starter"}}})
        self.assertIsNone(result["details"]["remote"])


if __name__ == "__main__":
    unittest.main()
