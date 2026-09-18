import math
import unittest

from _support import REPO  # noqa: F401
from aiusage import billing


class FiniteBillingTest(unittest.TestCase):
    def test_nonfinite_and_negative_bucket_tokens_are_zero(self):
        bucket = billing.UsageBucket("anthropic", "bad", "id", math.nan, math.inf, -1, -math.inf, math.nan)

        self.assertEqual(billing._bucket_tokens(bucket), {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "reasoning": 0})

    def test_valid_bucket_survives_nonfinite_unknown_bucket(self):
        buckets = [billing.UsageBucket("anthropic", "known", "good", 100, 50), billing.UsageBucket("anthropic", "unknown", "bad", math.nan, math.inf)]

        result = billing.aggregate_session_usage(buckets, {"anthropic": {"known": {"input": 2, "output": 8}}})

        self.assertEqual(result["costStatus"], "exact")
        self.assertTrue(math.isfinite(result["costUSD"]))

    def test_baseline_actual_and_estimated_cost_math_is_unchanged(self):
        actual = billing.aggregate_session_usage(
            [billing.UsageBucket("anthropic", "known", "actual", provider_cost_usd=0.42)],
            {"anthropic": {"known": {"input": 2, "output": 8}}},
        )
        estimated = billing.aggregate_session_usage(
            [billing.UsageBucket("anthropic", "known", "estimated", 100, 50)],
            {"anthropic": {"known": {"input": 2, "output": 8}}},
        )

        self.assertEqual(actual["costUSD"], 0.42)
        self.assertEqual(actual["costStatus"], "exact")
        self.assertEqual(actual["costProvenance"], "actual")
        self.assertEqual(estimated["costStatus"], "exact")
        self.assertEqual(estimated["costProvenance"], "estimated")
        self.assertAlmostEqual(estimated["costUSD"], 0.0006)

    def test_positive_provider_cost_is_actual(self):
        result = billing.aggregate_session_usage(
            [billing.UsageBucket("anthropic", "known", "actual", provider_cost_usd=0.42)],
            {"anthropic": {"known": {"input": 2, "output": 8}}},
        )

        self.assertEqual(result["costStatus"], "exact")
        self.assertEqual(result["costProvenance"], "actual")
        self.assertEqual(result["costUSD"], 0.42)

    def test_complete_cached_token_pricing_is_estimated(self):
        result = billing.aggregate_session_usage(
            [billing.UsageBucket("anthropic", "known", "estimated", 100, 50)],
            {"anthropic": {"known": {"input": 2, "output": 8}}},
        )

        self.assertEqual(result["costStatus"], "exact")
        self.assertEqual(result["costProvenance"], "estimated")
        self.assertAlmostEqual(result["costUSD"], 0.0006)

    def test_actual_and_estimated_buckets_are_mixed(self):
        result = billing.aggregate_session_usage(
            [
                billing.UsageBucket("anthropic", "known", "actual", provider_cost_usd=0.42),
                billing.UsageBucket("anthropic", "known", "estimated", 100, 50),
            ],
            {"anthropic": {"known": {"input": 2, "output": 8}}},
        )

        self.assertEqual(result["costStatus"], "exact")
        self.assertEqual(result["costProvenance"], "mixed")
        self.assertAlmostEqual(result["costUSD"], 0.4206)
        self.assertEqual(result["costBreakdown"]["actualUSD"], 0.42)
        self.assertAlmostEqual(result["costBreakdown"]["estimatedUSD"], 0.0006)

    def test_partial_status_keeps_numeric_bucket_provenance(self):
        result = billing.aggregate_session_usage(
            [
                billing.UsageBucket("anthropic", "known", "estimated", 100, 50),
                billing.UsageBucket("anthropic", "unknown", "unpriced", 100, 50),
            ],
            {"anthropic": {"known": {"input": 2, "output": 8}}},
        )

        self.assertEqual(result["costStatus"], "partial")
        self.assertEqual(result["costProvenance"], "estimated")
        self.assertAlmostEqual(result["costUSD"], 0.0006)

    def test_zero_token_zero_cost_is_a_finite_actual_result(self):
        result = billing.aggregate_session_usage(
            [billing.UsageBucket("anthropic", "known", "zero", provider_cost_usd=0)],
            {"anthropic": {}},
        )

        self.assertEqual(result, {"costUSD": 0, "costStatus": "exact", "costProvenance": "actual"})

    def test_unavailable_result_omits_numeric_and_provenance_fields(self):
        result = billing.aggregate_session_usage(
            [billing.UsageBucket("anthropic", "unknown", "unpriced", 100, 50)],
            {"anthropic": {}},
        )

        self.assertEqual(result, {"costStatus": "unavailable"})

    def test_malformed_pricing_stays_unavailable_without_nonfinite_json(self):
        for price in (
            {"input": math.nan, "output": 8},
            {"input": 2, "output": math.inf},
            {"input": "bad", "output": 8},
        ):
            with self.subTest(price=price):
                result = billing.aggregate_session_usage(
                    [billing.UsageBucket("anthropic", "known", "malformed", 100, 50)],
                    {"anthropic": {"known": price}},
                )

                self.assertEqual(result, {"costStatus": "unavailable"})

    def test_legacy_model_pricing_ignores_nonfinite_tokens(self):
        result = billing.price_models(
            [{"model": "known", "input_tokens": 100, "output_tokens": 50}, {"model": "unknown", "input_tokens": math.nan, "output_tokens": math.inf}],
            {"known": {"input": 2, "output": 8}},
        )

        self.assertEqual(result["totalInputTokens"], 100)
        self.assertEqual(result["totalOutputTokens"], 50)
        self.assertEqual(result["models"]["unknown"]["input_tokens"], 0)
        self.assertTrue(math.isfinite(result["totalCostUSD"]))
