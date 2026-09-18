import json
import os
import tempfile
from unittest import mock

from _support import IsolatedHomeTest
from aiusage import pricing, pricing_lock
from aiusage.http import HttpResult


class PricingLockTest(IsolatedHomeTest):
    def test_catalog_does_not_refresh_without_lock_ownership(self):
        response = {"claude-test": {"litellm_provider": "anthropic", "mode": "chat", "input_cost_per_token": 2e-6, "output_cost_per_token": 8e-6}}
        with mock.patch.object(pricing, "fetch_json", return_value=HttpResult(200, json.dumps(response))):
            snapshot = pricing.load_catalog()
        with (
            mock.patch.object(pricing, "_acquire_lock", return_value=None),
            mock.patch.object(pricing, "fetch_json") as fetch,
            mock.patch.object(pricing, "_write_cache") as write,
        ):
            result = pricing.load_catalog(force=True)
        self.assertEqual(result["providers"], snapshot["providers"])
        fetch.assert_not_called()
        write.assert_not_called()

    def test_timeout_preserves_live_and_cleans_dead_lock(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "pricing.json")
            with open(path + ".lock", "w", encoding="ascii") as stream:
                stream.write(str(os.getpid()))
            os.utime(path + ".lock", (0, 0))
            with (
                mock.patch.object(pricing_lock.time, "monotonic", side_effect=[0, 31]),
                mock.patch.object(pricing_lock.time, "time", return_value=100),
            ):
                self.assertIsNone(pricing_lock.acquire(path))
            self.assertTrue(os.path.exists(path + ".lock"))
            with open(path + ".lock", "w", encoding="ascii") as stream:
                stream.write("999999999")
            os.utime(path + ".lock", (0, 0))
            with (
                mock.patch.object(pricing_lock.time, "monotonic", side_effect=[0, 31]),
                mock.patch.object(pricing_lock.time, "time", return_value=100),
                mock.patch.object(os, "kill", side_effect=ProcessLookupError),
            ):
                self.assertIsNone(pricing_lock.acquire(path))
            self.assertFalse(os.path.exists(path + ".lock"))
            handle = pricing_lock.acquire(path)
            pricing_lock.release(path, handle)
