from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "benchmarks"))

from performance_harness import (  # noqa: E402
    CaptureMetadata,
    CaptureReport,
    capture_command,
    compare_reports,
    summarize_paths,
)
from performance_harness_io import report_from_json, report_to_json  # noqa: E402
from performance_harness_types import JsonObject  # noqa: E402

BASELINE_OUTPUT = REPOSITORY_ROOT / "tests" / "fixtures" / "benchmark-baseline.jsonl"


class BenchmarkOutputCharacterizationTests(unittest.TestCase):
    def test_benchmark_baseline_is_fifteen_jsonl_timing_records(self) -> None:
        lines = BASELINE_OUTPUT.read_text(encoding="utf-8").splitlines()

        self.assertEqual(len(lines), 15)
        records = [json.loads(line) for line in lines]
        self.assertTrue(all(isinstance(record, dict) for record in records))
        for record in records:
            self.assertIsInstance(record["benchmark"], str)
            self.assertIsInstance(record["operation"], str)
            self.assertIsInstance(record["points"], int)
            self.assertIsInstance(record["median_ns"], int)
            self.assertIsInstance(record["warmups"], int)
            self.assertIsInstance(record["iterations"], int)


class PerformanceHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="benchmark-harness-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def metadata(self, *, fixture: str = "fixture", cache_state: str = "warm") -> CaptureMetadata:
        return CaptureMetadata(
            command="fixture command",
            fixture=fixture,
            fixture_dimensions=(("points", "100"),),
            warmth="warm",
            cache_state=cache_state,
            requested_samples=5,
        )

    def write_samples(self, values: list[int], name: str = "sample") -> list[Path]:
        paths = []
        for index, value in enumerate(values, start=1):
            path = self.root / f"{name}-{index}.jsonl"
            path.write_text(
                json.dumps(
                    {
                        "benchmark": "fixture",
                        "operation": "query",
                        "points": 100,
                        "median_ns": value,
                        "warmups": 3,
                        "iterations": 7,
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            paths.append(path)
        return paths

    def serialize(self, report: CaptureReport) -> JsonObject:
        return json.loads(json.dumps(report_to_json(report)))

    def test_valid_self_comparison_reports_statistics_and_noise(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])

        report = summarize_paths(paths, self.metadata())
        comparison = compare_reports(report, report)

        self.assertEqual(report.verdict, "pass")
        self.assertEqual(report.aggregates[0].statistics["median"], 30)
        self.assertEqual(report.aggregates[0].statistics["p95"], 50)
        self.assertEqual(report.aggregates[0].statistics["min"], 10)
        self.assertEqual(report.aggregates[0].statistics["max"], 50)
        self.assertEqual(comparison.verdict, "pass")
        self.assertEqual(comparison.results[0].label, "noise")

    def test_missing_sample_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        paths.pop()

        report = summarize_paths(paths, self.metadata())

        self.assertEqual(report.verdict, "non-pass")
        self.assertIn("missing_sample", report.reasons)

    def test_malformed_jsonl_is_non_pass(self) -> None:
        path = self.root / "malformed.jsonl"
        path.write_text("{not-json}\n", encoding="utf-8")

        report = summarize_paths([path] * 5, self.metadata())

        self.assertEqual(report.verdict, "non-pass")
        self.assertIn("malformed_jsonl", report.reasons)

    def test_fixture_mismatch_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        before = summarize_paths(paths, self.metadata(fixture="before"))
        after = summarize_paths(paths, self.metadata(fixture="after"))

        comparison = compare_reports(before, after)

        self.assertEqual(comparison.verdict, "non-pass")
        self.assertIn("fixture_mismatch", comparison.reasons)

    def test_cache_state_mismatch_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        before = summarize_paths(paths, self.metadata(cache_state="cold"))
        after = summarize_paths(paths, self.metadata(cache_state="warm"))

        comparison = compare_reports(before, after)

        self.assertEqual(comparison.verdict, "non-pass")
        self.assertIn("cache_state_mismatch", comparison.reasons)

    def test_warmth_mismatch_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        before_metadata = self.metadata()
        after_metadata = CaptureMetadata(
            command=before_metadata.command,
            fixture=before_metadata.fixture,
            fixture_dimensions=before_metadata.fixture_dimensions,
            warmth="cold",
            cache_state=before_metadata.cache_state,
            requested_samples=before_metadata.requested_samples,
        )
        before = summarize_paths(paths, before_metadata)
        after = summarize_paths(paths, after_metadata)

        comparison = compare_reports(before, after)

        self.assertEqual(comparison.verdict, "non-pass")
        self.assertIn("warmth_mismatch", comparison.reasons)

    def test_missing_tuple_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        paths[-1].write_text(
            json.dumps(
                {
                    "benchmark": "fixture",
                    "operation": "query",
                    "points": 200,
                    "median_ns": 50,
                    "warmups": 3,
                    "iterations": 7,
                }
            )
            + "\n",
            encoding="utf-8",
        )

        report = summarize_paths(paths, self.metadata())

        self.assertEqual(report.verdict, "non-pass")
        self.assertIn("missing_tuple", report.reasons)

    def test_command_failure_is_non_pass(self) -> None:
        metadata = CaptureMetadata(
            command=f"{sys.executable} -c 'import sys; sys.exit(7)'",
            fixture="fixture",
            fixture_dimensions=(),
            warmth="warm",
            cache_state="warm",
            requested_samples=5,
        )

        report = capture_command(metadata)

        self.assertEqual(report.verdict, "non-pass")
        self.assertIn("command_failure", report.reasons)

    def test_tampered_verdict_is_recomputed_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        document["samples"][0]["stdout"] = "{not-json}\n"
        document["verdict"] = "pass"
        document["reasons"] = []

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("malformed_jsonl", reloaded.reasons)

    def test_tampered_verdict_pass_is_recomputed(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        document["verdict"] = "non-pass"
        document["reasons"] = ["input_non_pass"]

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "pass")
        self.assertEqual(reloaded.reasons, ())

    def test_command_mismatch_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        before = summarize_paths(paths, self.metadata())
        after_metadata = CaptureMetadata(
            command="different command",
            fixture="fixture",
            fixture_dimensions=(("points", "100"),),
            warmth="warm",
            cache_state="warm",
            requested_samples=5,
        )
        after = summarize_paths(paths, after_metadata)

        comparison = compare_reports(before, after)

        self.assertEqual(comparison.verdict, "non-pass")
        self.assertIn("command_mismatch", comparison.reasons)

    def test_requested_samples_mismatch_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        before = summarize_paths(paths, self.metadata())
        after_metadata = CaptureMetadata(
            command="fixture command",
            fixture="fixture",
            fixture_dimensions=(("points", "100"),),
            warmth="warm",
            cache_state="warm",
            requested_samples=4,
        )
        after = summarize_paths(paths[:4], after_metadata)

        comparison = compare_reports(before, after)

        self.assertEqual(comparison.verdict, "non-pass")
        self.assertIn("requested_samples_mismatch", comparison.reasons)

    def test_missing_median_field_is_structured_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        record = json.loads(document["samples"][0]["stdout"].strip())
        del record["median_ns"]
        document["samples"][0]["stdout"] = json.dumps(record) + "\n"

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("malformed_jsonl", reloaded.reasons)

    def test_rss_unavailable_is_labeled_not_collected(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))

        self.assertFalse(document["metadata"]["rss"]["available"])
        self.assertTrue(all(sample["rss_kb"] is None for sample in document["samples"]))

    def test_rss_labeling_matches_collection(self) -> None:
        metadata = CaptureMetadata(
            command=f"{sys.executable} -c 'pass'",
            fixture="fixture",
            fixture_dimensions=(),
            warmth="warm",
            cache_state="warm",
            requested_samples=1,
        )
        document = self.serialize(capture_command(metadata))

        available = document["metadata"]["rss"]["available"]
        collected = any(sample["rss_kb"] is not None for sample in document["samples"])
        self.assertEqual(available, collected)

    def test_warmth_is_caller_declared_metadata(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))

        self.assertEqual(document["metadata"]["warmth"], "warm")
        self.assertEqual(document["metadata"]["warmth_source"], "caller-declared")
        self.assertEqual(document["metadata"]["cache_state_source"], "caller-declared")

    def test_valid_round_trip_preserves_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "pass")
        self.assertEqual(reloaded.reasons, ())

    def test_rss_available_tamper_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        document["metadata"]["rss"]["available"] = True

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("rss_metadata_mismatch", reloaded.reasons)

    def test_rss_source_tamper_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        document["metadata"]["rss"]["source"] = "psutil"

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("rss_metadata_mismatch", reloaded.reasons)

    def test_warmth_source_tamper_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        document["metadata"]["warmth_source"] = "harness-controlled"

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("warmth_source_mismatch", reloaded.reasons)

    def test_cache_state_source_tamper_is_non_pass(self) -> None:
        paths = self.write_samples([10, 20, 30, 40, 50])
        document = self.serialize(summarize_paths(paths, self.metadata()))
        document["metadata"]["cache_state_source"] = "measured"

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("cache_state_source_mismatch", reloaded.reasons)


class PersistedSchemaEnforcementTests(PerformanceHarnessTests):
    def valid_document(self) -> JsonObject:
        paths = self.write_samples([10, 20, 30, 40, 50])
        return self.serialize(summarize_paths(paths, self.metadata()))

    def test_missing_top_level_field_is_non_pass(self) -> None:
        document = self.valid_document()
        for field in ("schema", "verdict", "reasons", "metadata", "runtime", "sample_count", "samples", "aggregates"):
            with self.subTest(field=field):
                tampered = json.loads(json.dumps(document))
                del tampered[field]
                reloaded = report_from_json(tampered)
                self.assertEqual(reloaded.verdict, "non-pass")
                self.assertIn("missing_field", reloaded.reasons)

    def test_missing_metadata_field_is_non_pass(self) -> None:
        document = self.valid_document()
        for field in (
            "command",
            "fixture",
            "fixture_dimensions",
            "warmth",
            "warmth_source",
            "cache_state",
            "cache_state_source",
            "metric",
            "requested_samples",
            "rss",
            "timing_attribution",
        ):
            with self.subTest(field=field):
                tampered = json.loads(json.dumps(document))
                del tampered["metadata"][field]
                reloaded = report_from_json(tampered)
                self.assertEqual(reloaded.verdict, "non-pass")
                self.assertIn("missing_field", reloaded.reasons)

    def test_missing_rss_field_is_non_pass(self) -> None:
        document = self.valid_document()
        for field in ("available", "unit", "source", "scope"):
            with self.subTest(field=field):
                tampered = json.loads(json.dumps(document))
                del tampered["metadata"]["rss"][field]
                reloaded = report_from_json(tampered)
                self.assertEqual(reloaded.verdict, "non-pass")
                self.assertIn("missing_field", reloaded.reasons)

    def test_missing_sample_field_is_non_pass(self) -> None:
        document = self.valid_document()
        for field in ("source", "returncode", "stdout", "stderr", "duration_ns", "rss_kb", "records", "reasons"):
            with self.subTest(field=field):
                tampered = json.loads(json.dumps(document))
                del tampered["samples"][0][field]
                reloaded = report_from_json(tampered)
                self.assertEqual(reloaded.verdict, "non-pass")
                self.assertIn("missing_field", reloaded.reasons)

    def test_missing_aggregate_field_is_non_pass(self) -> None:
        document = self.valid_document()
        for field in ("tuple", "samples", "statistics"):
            with self.subTest(field=field):
                tampered = json.loads(json.dumps(document))
                del tampered["aggregates"][0][field]
                reloaded = report_from_json(tampered)
                self.assertEqual(reloaded.verdict, "non-pass")
                self.assertIn("missing_field", reloaded.reasons)

    def test_wrong_schema_literal_is_non_pass(self) -> None:
        document = self.valid_document()
        document["schema"] = "kde-ai-usage.performance-capture.v2"

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("schema_mismatch", reloaded.reasons)

    def test_sample_count_mismatch_is_non_pass(self) -> None:
        document = self.valid_document()
        document["sample_count"] = 4

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("sample_count_mismatch", reloaded.reasons)

    def test_invalid_rss_kb_values_are_non_pass(self) -> None:
        document = self.valid_document()
        for value in (True, False, 0, -5, "123", 1.5):
            with self.subTest(value=value):
                tampered = json.loads(json.dumps(document))
                tampered["samples"][0]["rss_kb"] = value
                reloaded = report_from_json(tampered)
                self.assertEqual(reloaded.verdict, "non-pass")
                self.assertIn("invalid_rss_kb", reloaded.reasons)

    def test_bool_duration_ns_is_non_pass(self) -> None:
        document = self.valid_document()
        document["samples"][0]["duration_ns"] = True

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("invalid_duration_ns", reloaded.reasons)

    def test_non_dict_document_is_non_pass(self) -> None:
        reloaded = report_from_json([])  # type: ignore[arg-type]

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("missing_field", reloaded.reasons)

    def test_rss_kb_without_available_label_is_non_pass(self) -> None:
        document = self.valid_document()
        for sample in document["samples"]:
            sample["rss_kb"] = 12345

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "non-pass")
        self.assertIn("rss_metadata_mismatch", reloaded.reasons)

    def test_valid_rss_kb_with_available_label_passes(self) -> None:
        document = self.valid_document()
        document["metadata"]["rss"]["available"] = True
        for sample in document["samples"]:
            sample["rss_kb"] = 12345

        reloaded = report_from_json(document)

        self.assertEqual(reloaded.verdict, "pass")
        self.assertEqual(reloaded.reasons, ())


if __name__ == "__main__":
    unittest.main()
