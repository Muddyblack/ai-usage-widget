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


class CacheReadBillingTest(unittest.TestCase):
    """Anthropic reports cache reads *alongside* input, not inside it, so
    clamping the billed amount to the input count dropped the bulk of a
    cache-heavy session's tokens and priced it at a fraction of its real
    cost (a four-figure month read as tens of dollars)."""

    PRICE = {"input": 3.0, "output": 15.0, "cached": 0.30}

    def test_cache_reads_beyond_input_are_billed_not_discarded(self):
        # Shape of a real Claude Code session: a small prompt against a very
        # large cache.
        bucket = billing.UsageBucket(
            "anthropic",
            "claude-sonnet-5",
            "id",
            input_tokens=429_000,
            output_tokens=606_200,
            cache_read_tokens=155_200_000,
            cache_write_tokens=2_800_000,
        )
        cost = billing._bucket_cost(bucket, self.PRICE)

        # Every cache-read token is billed at the cached rate.
        self.assertAlmostEqual(cost, (2_800_000 / 1e6) * 3.0 + (155_200_000 / 1e6) * 0.30 + (606_200 / 1e6) * 15.0, places=6)
        # The old clamp produced this; anything near it means tokens vanished.
        self.assertGreater(cost, 20.0)

    def test_cache_reads_inside_input_are_not_double_billed(self):
        # OpenAI-style: cached tokens are a subset of the prompt, so the
        # full-rate remainder is input minus cached, never negative.
        bucket = billing.UsageBucket(
            "openai",
            "gpt-5",
            "id",
            input_tokens=1_000_000,
            output_tokens=0,
            cache_read_tokens=400_000,
        )
        cost = billing._bucket_cost(bucket, self.PRICE)

        self.assertAlmostEqual(cost, (600_000 / 1e6) * 3.0 + (400_000 / 1e6) * 0.30, places=6)
