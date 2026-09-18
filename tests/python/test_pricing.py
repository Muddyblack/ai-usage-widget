"""Catalog units, provider isolation, cache refresh/failure and collector wiring."""

import copy
import json
import os
import tempfile
import threading
from unittest import mock

from _support import IsolatedHomeTest, raw_fixture
from aiusage import billing, collect, pricing, sessions
from aiusage.http import HttpResult
from aiusage.normalize.claude import normalize_claude
from aiusage.normalize.openai import normalize_openai


def catalog():
    # Synthetic upstream data: assertions exercise conversion, not live prices.
    return {
        "claude-test": {
            "litellm_provider": "anthropic",
            "mode": "chat",
            "input_cost_per_token": 0.000002,
            "output_cost_per_token": 0.000008,
            "cache_read_input_token_cost": 0.0000002,
        },
        "gpt-test": {
            "litellm_provider": "openai",
            "mode": "responses",
            "input_cost_per_token": 0.000004,
            "output_cost_per_token": 0.000012,
        },
    }


class PricingTest(IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        self.clock = mock.patch("aiusage.pricing.time.time", return_value=1_800_000_000).start()
        self.addCleanup(mock.patch.stopall)
        self.fetch = mock.patch("aiusage.pricing.fetch_json", return_value=HttpResult(200, json.dumps(catalog()))).start()

    def test_units_and_provider_isolation(self):
        data = catalog()
        for key, provider, mode in (
            ("bedrock/claude-test", "bedrock", "chat"),
            ("openrouter/gpt-test", "openrouter", "chat"),
            ("region/claude-test", "anthropic", "chat"),
            ("gpt-image", "openai", "image_generation"),
            ("sample_spec", "example", "chat"),
        ):
            data[key] = {**data["gpt-test"], "litellm_provider": provider, "mode": mode}
        tables = pricing.parse_catalog(data)
        self.assertEqual(set(tables["anthropic"]), {"claude-test"})
        self.assertEqual(tables["anthropic"]["claude-test"]["input"], 2)
        self.assertEqual(tables["anthropic"]["claude-test"]["output"], 8)
        self.assertAlmostEqual(tables["anthropic"]["claude-test"]["cached"], 0.2)
        self.assertEqual(tables["openai"], {"gpt-test": {"input": 4, "output": 12}})

    def test_existing_billing_keeps_unknown_models_visible_and_unpriced(self):
        result = billing.price_models(
            [{"model": "known", "input_tokens": 1_000, "output_tokens": 200}, {"model": "unknown", "input_tokens": 50}],
            {"known": {"input": 1, "output": 2}},
        )

        self.assertEqual(set(result["models"]), {"known", "unknown"})
        self.assertTrue(result["models"]["known"]["priced"])
        self.assertFalse(result["models"]["unknown"]["priced"])
        self.assertGreater(result["totalCostUSD"], 0)

    def test_incomplete_and_invalid_rates_do_not_become_free_models(self):
        for value in (None, True, "0.001", -1, float("nan"), float("inf"), 10**400):
            with self.subTest(value=str(value)):
                data = catalog()
                data["bad"] = {**data["gpt-test"], "input_cost_per_token": value}
                data["bad-cache"] = {**data["gpt-test"], "cache_read_input_token_cost": value}
                tables = pricing.parse_catalog(data)
                self.assertNotIn("bad", tables["openai"])
                if value is not None:
                    self.assertNotIn("bad-cache", tables["openai"])
        data = catalog()
        data["free"] = {**data["gpt-test"], "input_cost_per_token": 0, "output_cost_per_token": 0}
        self.assertEqual(pricing.parse_catalog(data)["openai"]["free"], {"input": 0, "output": 0})
        for data in (None, [], {}, {"model": {"litellm_provider": []}}, {"gpt-test": catalog()["gpt-test"]}):
            with self.assertRaises(ValueError):
                pricing.parse_catalog(data)

    def test_shared_daily_cache_updates_new_models_and_prices(self):
        self.assertEqual(pricing.get_pricing("anthropic")["claude-test"]["input"], 2)
        self.assertEqual(pricing.get_pricing("openai")["gpt-test"]["output"], 12)
        self.fetch.assert_called_once_with(pricing.SOURCE_URL, timeout=10)
        self.clock.return_value += pricing.REFRESH_SECONDS
        data = catalog()
        data["gpt-test"]["input_cost_per_token"] = 0.000006
        data["new-model"] = data["gpt-test"]
        self.fetch.return_value = HttpResult(200, json.dumps(data))
        self.assertEqual(pricing.get_pricing("openai")["new-model"]["input"], 6)
        self.assertEqual(self.fetch.call_count, 2)

    def test_normal_refresh_boundary_is_exactly_seven_days(self):
        pricing.load_catalog()
        self.clock.return_value += pricing.REFRESH_SECONDS - 1
        pricing.load_catalog()
        self.assertEqual(self.fetch.call_count, 1)
        self.clock.return_value += 1
        pricing.load_catalog()
        self.assertEqual(self.fetch.call_count, 2)

    def test_force_refresh_bypasses_a_fresh_cache(self):
        pricing.load_catalog()
        pricing.load_catalog(force=True)
        self.assertEqual(self.fetch.call_count, 2)

    def test_concurrent_forced_refreshes_share_one_upstream_fetch(self):
        entered = threading.Event()
        release = threading.Event()
        calls = 0
        calls_lock = threading.Lock()

        def fetch(_url, timeout):
            nonlocal calls
            with calls_lock:
                calls += 1
            entered.set()
            release.wait()
            return HttpResult(200, json.dumps(catalog()))

        self.fetch.side_effect = fetch
        threads = [threading.Thread(target=lambda: pricing.load_catalog(force=True)) for _ in range(2)]
        for thread in threads:
            thread.start()
        try:
            self.assertTrue(entered.wait(2))
        finally:
            release.set()
        for thread in threads:
            thread.join(2)
            self.assertFalse(thread.is_alive())
        self.assertEqual(calls, 1)

    def test_litellm_hit_does_not_consult_openrouter(self):
        pricing.load_catalog(models={"anthropic": ["claude-test"]})
        self.assertEqual(self.fetch.call_count, 1)

    def test_fresh_cache_requested_miss_consults_openrouter_without_litellm_refetch(self):
        pricing.load_catalog()
        self.fetch.reset_mock()
        self.fetch.return_value = HttpResult(200, json.dumps(raw_fixture("pricing-openrouter-response")))
        result = pricing.load_catalog(models={"anthropic": ["claude-missing"]})
        self.assertEqual(result["providers"]["anthropic"]["claude-test"]["input"], 2)
        self.assertEqual(result["providers"]["anthropic"]["claude-missing"]["output"], 9.0)
        self.fetch.assert_called_once_with(pricing.OPENROUTER_SOURCE_URL, timeout=10)

    def test_openrouter_prices_an_exact_litellm_miss(self):
        self.fetch.side_effect = [
            HttpResult(200, json.dumps(catalog())),
            HttpResult(200, json.dumps(raw_fixture("pricing-openrouter-response"))),
        ]
        result = pricing.load_catalog(models={"anthropic": ["claude-missing"]})
        self.assertEqual(result["providers"]["anthropic"]["claude-missing"], {"input": 3.0, "output": 9.0, "cached": 0.3})
        self.assertEqual(self.fetch.call_count, 2)

    def test_openrouter_fallback_creates_provider_bucket_after_litellm_failure(self):
        self.fetch.side_effect = [
            HttpResult(503, ""),
            HttpResult(200, json.dumps(raw_fixture("pricing-openrouter-response"))),
        ]
        result = pricing.load_catalog(models={"anthropic": ["claude-missing"]})
        self.assertEqual(result["providers"]["anthropic"]["claude-missing"]["input"], 3.0)
        self.assertEqual(result["providers"]["anthropic"]["claude-missing"]["output"], 9.0)
        self.assertEqual(self.fetch.call_count, 2)

    def test_both_pricing_sources_fail_without_cache(self):
        self.fetch.side_effect = [HttpResult(503, ""), HttpResult(503, "")]
        result = pricing.load_catalog(models={"anthropic": ["missing"]})
        self.assertEqual(result["providers"], {})
        self.assertTrue(result["error"])
        self.assertEqual(self.fetch.call_count, 2)

    def test_failed_requested_refresh_retains_last_good_rates(self):
        pricing.load_catalog()
        self.clock.return_value += pricing.REFRESH_SECONDS
        self.fetch.side_effect = [HttpResult(503, ""), HttpResult(503, "")]
        result = pricing.load_catalog(models={"anthropic": "missing"})
        self.assertEqual(result["providers"]["openai"]["gpt-test"]["input"], 4)
        self.assertTrue(result["error"])

    def test_cached_token_math_and_unknown_model_status(self):
        result = billing.aggregate_session_usage(
            [
                billing.UsageBucket("anthropic", "known", "session", 1_000, 200, 400),
                billing.UsageBucket("anthropic", "unknown", "session", 100, 10),
            ],
            {"anthropic": {"known": {"input": 2, "output": 8, "cached": 0.2}}},
        )
        self.assertAlmostEqual(result["costUSD"], 0.00288)
        self.assertEqual(result["costStatus"], "partial")

    def test_missing_usage_is_unavailable(self):
        result = billing.aggregate_session_usage([], {"anthropic": {}})
        self.assertEqual(result, {"costStatus": "unavailable"})

    def test_session_rows_keep_cost_out_of_redacted_detail(self):
        with mock.patch.object(pricing, "cached_catalog", return_value={"anthropic": {"claude-test": {"input": 2, "output": 8}}}):
            entry = sessions._entry("claude", "Title", 2_000, session_id="id", detail="$secret")
            entry = sessions._with_usage_cost(entry, "anthropic", [billing.UsageBucket("anthropic", "claude-test", "id", 100, 50)])
        self.assertEqual(entry["costStatus"], "exact")
        self.assertAlmostEqual(entry["costUSD"], 0.0006)
        self.assertEqual(entry["detail"], "$secret")

    def test_claude_session_sums_multiple_models_and_marks_partial(self):
        with tempfile.TemporaryDirectory() as root:
            project = os.path.join(root, "projects", "-tmp-widget")
            os.makedirs(project)
            path = os.path.join(project, "session.jsonl")
            with open(path, "w", encoding="utf-8") as stream:
                stream.write(json.dumps({"message": {"model": "known-a", "usage": {"input_tokens": 100, "output_tokens": 50}}}) + "\n")
                stream.write(json.dumps({"message": {"model": "known-b", "usage": {"input_tokens": 200, "output_tokens": 25}}}) + "\n")
                stream.write(json.dumps({"message": {"model": "unknown", "usage": {"input_tokens": 1, "output_tokens": 1}}}) + "\n")
            with (
                mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": root}, clear=True),
                mock.patch.object(
                    pricing,
                    "cached_catalog",
                    return_value={"anthropic": {"known-a": {"input": 1, "output": 2}, "known-b": {"input": 3, "output": 4}}},
                ),
            ):
                entry = sessions._claude_entries()[0]
        self.assertEqual(entry["costStatus"], "partial")
        self.assertAlmostEqual(entry["costUSD"], 0.0009)

    def test_cache_write_failure_keeps_current_process_rates(self):
        with mock.patch("aiusage.pricing.os.replace", side_effect=PermissionError):
            pricing.load_catalog(force=True)
        self.assertEqual(pricing.cached_catalog()["openai"]["gpt-test"]["input"], 4)

    def test_failed_refresh_retains_rates_and_backs_off(self):
        original = pricing.load_catalog()
        for response in (HttpResult(0, ""), HttpResult(200, "<html>broken</html>"), HttpResult(200, "{}")):
            self.clock.return_value += pricing.REFRESH_SECONDS
            self.fetch.return_value = response
            failed = pricing.load_catalog()
            self.assertTrue(failed["error"])
            self.assertEqual(failed["providers"], original["providers"])
            self.assertEqual(failed["fetchedAt"], original["fetchedAt"])
            calls = self.fetch.call_count
            self.assertEqual(pricing.load_catalog(), failed)
            self.assertEqual(self.fetch.call_count, calls)
        self.clock.return_value += pricing.RETRY_SECONDS
        self.fetch.return_value = HttpResult(200, json.dumps(catalog()))
        self.assertEqual(pricing.load_catalog()["error"], "")

    def test_first_offline_fetch_and_corrupt_cache_remain_unpriced(self):
        self.write("cache/pricing-litellm-v1.json", "broken")
        self.fetch.return_value = HttpResult(503, "")
        self.assertEqual(pricing.get_pricing("anthropic"), {})
        self.assertEqual(pricing.get_pricing("openai"), {})
        self.assertEqual(self.fetch.call_count, 1)

    def test_unwritable_cache_still_uses_download(self):
        with mock.patch("aiusage.pricing.os.replace", side_effect=PermissionError):
            self.assertEqual(pricing.get_pricing("openai")["gpt-test"]["input"], 4)
        self.assertEqual(list((self.home / "cache").iterdir()), [])

    def test_normalizers_use_supplied_rates_without_io(self):
        for name, normalize, model in (
            ("claude-success", normalize_claude, "claude-sonnet-4"),
            ("openai-api-key-only", normalize_openai, "gpt-4o-mini"),
        ):
            raw = copy.deepcopy(raw_fixture(name))
            raw["inputs"]["pricing"] = {model: {"input": 7, "output": 11}}
            org = normalize(raw)["details"]["organizationUsage"]
            row = org["models"][model]
            self.assertTrue(row["priced"])
            self.assertAlmostEqual(row["cost_usd"], row["input_tokens"] * 7e-6 + row["output_tokens"] * 11e-6)
            del raw["inputs"]["pricing"]
            self.assertFalse(normalize(raw)["details"]["organizationUsage"]["models"][model]["priced"])
        self.fetch.assert_not_called()

    def test_collectors_only_load_prices_when_org_usage_exists(self):
        with (
            mock.patch.object(collect, "get_claude_credentials", return_value={"claudeAdminApiKey": "test"}),
            mock.patch.object(collect, "get_openai_credentials", return_value={"openaiApiKey": "test"}),
            mock.patch.object(collect, "get_codex_rate_limits", return_value={}),
            mock.patch.object(collect, "get_codex_stats", return_value={}),
            mock.patch.object(collect, "provider_status", return_value=None),
            mock.patch.object(collect, "fetch_json") as usage,
        ):
            usage.return_value = HttpResult(200, '{"data": []}')
            for collector in (collect.collect_claude, collect.collect_openai):
                self.assertEqual(collector(1_800_000_000)["inputs"]["pricing"], {})
            self.fetch.assert_not_called()
            usage.return_value = HttpResult(200, '{"data": [{"model": "test"}]}')
            self.assertIn("claude-test", collect.collect_claude(1_800_000_000)["inputs"]["pricing"])
            self.assertIn("gpt-test", collect.collect_openai(1_800_000_000)["inputs"]["pricing"])
            self.assertEqual(self.fetch.call_count, 1)
