from __future__ import annotations

from typing import Final

from performance_harness import _parse_sample, _report
from performance_harness_types import (
    CALLER_DECLARED,
    DEFAULT_SAMPLE_COUNT,
    CaptureMetadata,
    CaptureReport,
    ComparisonReport,
    JsonObject,
    ParsedSample,
)

CAPTURE_SCHEMA: Final = "kde-ai-usage.performance-capture.v1"
COMPARISON_SCHEMA: Final = "kde-ai-usage.performance-comparison.v1"

RSS_SOURCE: Final = "getrusage(RUSAGE_CHILDREN).ru_maxrss"
RSS_UNIT: Final = "kB"
RSS_SCOPE: Final = "max resident set size of benchmark child processes; monotonic across samples"

_TOP_LEVEL_FIELDS: Final = ("schema", "verdict", "reasons", "metadata", "runtime", "sample_count", "samples", "aggregates")
_METADATA_FIELDS: Final = (
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
)
_RSS_FIELDS: Final = ("available", "unit", "source", "scope")
_SAMPLE_FIELDS: Final = ("source", "returncode", "stdout", "stderr", "duration_ns", "rss_kb", "records", "reasons")
_AGGREGATE_FIELDS: Final = ("tuple", "samples", "statistics")


def report_to_json(report: CaptureReport) -> JsonObject:
    return {
        "schema": CAPTURE_SCHEMA,
        "verdict": report.verdict,
        "reasons": list(report.reasons),
        "metadata": {
            "command": report.metadata.command,
            "fixture": report.metadata.fixture,
            "fixture_dimensions": dict(report.metadata.fixture_dimensions),
            "warmth": report.metadata.warmth,
            "warmth_source": report.metadata.warmth_source,
            "cache_state": report.metadata.cache_state,
            "cache_state_source": report.metadata.cache_state_source,
            "metric": report.metadata.metric,
            "requested_samples": report.metadata.requested_samples,
            "rss": {
                "available": any(sample.rss_kb is not None for sample in report.samples),
                "unit": RSS_UNIT,
                "source": RSS_SOURCE,
                "scope": RSS_SCOPE,
            },
            "timing_attribution": {
                "launcher": "samples[*].duration_ns",
                "in_process": f"records[*].{report.metadata.metric}",
            },
        },
        "runtime": report.runtime,
        "sample_count": len(report.samples),
        "samples": [
            {
                "source": sample.source,
                "returncode": sample.returncode,
                "stdout": sample.stdout,
                "stderr": sample.stderr,
                "duration_ns": sample.duration_ns,
                "rss_kb": sample.rss_kb,
                "records": sample.records,
                "reasons": list(sample.reasons),
            }
            for sample in report.samples
        ],
        "aggregates": [
            {
                "tuple": aggregate.tuple_fields,
                "samples": aggregate.samples,
                "statistics": aggregate.statistics,
            }
            for aggregate in report.aggregates
        ],
    }


def comparison_to_json(comparison: ComparisonReport) -> JsonObject:
    return {
        "schema": COMPARISON_SCHEMA,
        "verdict": comparison.verdict,
        "reasons": list(comparison.reasons),
        "results": [
            {
                "tuple": result.tuple_fields,
                "label": result.label,
                "before": result.before,
                "after": result.after,
                "median_delta": result.median_delta,
            }
            for result in comparison.results
        ],
    }


def _int_or(value: object, default: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        return default
    return value


def _integrity_reasons(metadata_document: JsonObject, samples: tuple[ParsedSample, ...]) -> list[str]:
    reasons: list[str] = []
    rss_document = metadata_document.get("rss")
    if not isinstance(rss_document, dict):
        reasons.append("rss_metadata_mismatch")
    else:
        available = rss_document.get("available")
        collected = any(sample.rss_kb is not None for sample in samples)
        if not isinstance(available, bool) or available != collected:
            reasons.append("rss_metadata_mismatch")
        if rss_document.get("unit") != RSS_UNIT:
            reasons.append("rss_metadata_mismatch")
        if rss_document.get("source") != RSS_SOURCE:
            reasons.append("rss_metadata_mismatch")
        if rss_document.get("scope") != RSS_SCOPE:
            reasons.append("rss_metadata_mismatch")
    if metadata_document.get("warmth_source") != CALLER_DECLARED:
        reasons.append("warmth_source_mismatch")
    if metadata_document.get("cache_state_source") != CALLER_DECLARED:
        reasons.append("cache_state_source_mismatch")
    return reasons


def report_from_json(document: JsonObject) -> CaptureReport:
    reasons: list[str] = []
    if not isinstance(document, dict):
        reasons.append("missing_field")
        document = {}
    if document.get("schema") != CAPTURE_SCHEMA:
        reasons.append("schema_mismatch")
    for field in _TOP_LEVEL_FIELDS:
        if field not in document:
            reasons.append("missing_field")
    metadata_document = document.get("metadata")
    if not isinstance(metadata_document, dict):
        reasons.append("missing_field")
        metadata_document = {}
    for field in _METADATA_FIELDS:
        if field not in metadata_document:
            reasons.append("missing_field")
    rss_document = metadata_document.get("rss")
    if not isinstance(rss_document, dict):
        reasons.append("missing_field")
        rss_document = {}
    for field in _RSS_FIELDS:
        if field not in rss_document:
            reasons.append("missing_field")
    dimensions_document = metadata_document.get("fixture_dimensions")
    if not isinstance(dimensions_document, dict):
        reasons.append("missing_field")
        dimensions_document = {}
    requested_samples_document = metadata_document.get("requested_samples", DEFAULT_SAMPLE_COUNT)
    if isinstance(requested_samples_document, bool) or not isinstance(requested_samples_document, int):
        reasons.append("missing_field")
        requested_samples_document = DEFAULT_SAMPLE_COUNT
    metadata = CaptureMetadata(
        command=str(metadata_document.get("command", "")),
        fixture=str(metadata_document.get("fixture", "")),
        fixture_dimensions=tuple(sorted((str(key), str(value)) for key, value in dimensions_document.items())),
        warmth=str(metadata_document.get("warmth", "")),
        cache_state=str(metadata_document.get("cache_state", "")),
        metric=str(metadata_document.get("metric", "median_ns")),
        requested_samples=requested_samples_document,
        warmth_source=str(metadata_document.get("warmth_source", "caller-declared")),
        cache_state_source=str(metadata_document.get("cache_state_source", "caller-declared")),
    )
    samples_document = document.get("samples")
    if not isinstance(samples_document, list):
        reasons.append("missing_field")
        samples_document = []
    samples = []
    for sample_document in samples_document:
        if not isinstance(sample_document, dict):
            reasons.append("missing_field")
            continue
        for field in _SAMPLE_FIELDS:
            if field not in sample_document:
                reasons.append("missing_field")
        duration_ns = sample_document.get("duration_ns")
        if duration_ns is not None and (isinstance(duration_ns, bool) or not isinstance(duration_ns, int)):
            reasons.append("invalid_duration_ns")
            duration_ns = None
        rss_kb = sample_document.get("rss_kb")
        if rss_kb is not None and (isinstance(rss_kb, bool) or not isinstance(rss_kb, int) or rss_kb <= 0):
            reasons.append("invalid_rss_kb")
            rss_kb = None
        samples.append(
            _parse_sample(
                source=str(sample_document.get("source", "")),
                stdout=str(sample_document.get("stdout", "")),
                stderr=str(sample_document.get("stderr", "")),
                returncode=_int_or(sample_document.get("returncode"), 1),
                metadata=metadata,
                duration_ns=duration_ns,
                rss_kb=rss_kb,
            )
        )
    sample_count_document = document.get("sample_count")
    if isinstance(sample_count_document, bool) or not isinstance(sample_count_document, int):
        reasons.append("missing_field")
    elif sample_count_document != len(samples):
        reasons.append("sample_count_mismatch")
    aggregates_document = document.get("aggregates")
    if not isinstance(aggregates_document, list):
        reasons.append("missing_field")
    else:
        for aggregate_document in aggregates_document:
            if not isinstance(aggregate_document, dict):
                reasons.append("missing_field")
                continue
            for field in _AGGREGATE_FIELDS:
                if field not in aggregate_document:
                    reasons.append("missing_field")
    runtime_document = document.get("runtime", {})
    runtime = {str(key): str(value) for key, value in runtime_document.items()} if isinstance(runtime_document, dict) else {}
    report = _report(metadata, tuple(samples), runtime)
    integrity_reasons = _integrity_reasons(metadata_document, tuple(samples))
    all_reasons = tuple(sorted(set(report.reasons + tuple(reasons) + tuple(integrity_reasons))))
    if all_reasons:
        return CaptureReport(metadata, report.runtime, report.samples, report.aggregates, "non-pass", all_reasons)
    return report
