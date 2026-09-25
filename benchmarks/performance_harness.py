from __future__ import annotations

import json
import math
import platform
import shlex
import subprocess
import time
from pathlib import Path
from statistics import median

from performance_harness_types import (
    NON_MEASUREMENT_FIELDS,
    Aggregate,
    CaptureMetadata,
    CaptureReport,
    ComparisonReport,
    ComparisonResult,
    JsonObject,
    ParsedSample,
)


def _runtime_metadata() -> dict[str, str]:
    return {
        "python": platform.python_version(),
        "implementation": platform.python_implementation(),
        "platform": platform.platform(),
    }


def _collect_rss_kb() -> int | None:
    try:
        import resource

        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    except (ImportError, AttributeError, OSError, ValueError):
        return None
    value = usage.ru_maxrss
    if not isinstance(value, int) or value <= 0:
        return None
    if platform.system() == "Darwin":
        value //= 1024
    return value


def _parse_record(line: str, metric: str) -> JsonObject | None:
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(value, dict) or not isinstance(value.get(metric), (int, float)):
        return None
    metric_value = value[metric]
    if isinstance(metric_value, bool) or not math.isfinite(float(metric_value)):
        return None
    return value


def _parse_sample(
    source: str,
    stdout: str,
    stderr: str,
    returncode: int,
    metadata: CaptureMetadata,
    duration_ns: int | None = None,
    rss_kb: int | None = None,
) -> ParsedSample:
    records: list[JsonObject] = []
    reasons: list[str] = []
    for _line_number, line in enumerate(stdout.splitlines(), start=1):
        if not line.strip():
            continue
        record = _parse_record(line, metadata.metric)
        if record is None:
            reasons.append("malformed_jsonl")
        else:
            records.append(record)
    if returncode != 0:
        reasons.append("command_failure")
    if not records:
        reasons.append("missing_sample")
    return ParsedSample(source, stdout, stderr, returncode, duration_ns, rss_kb, tuple(records), tuple(reasons))


def _tuple_fields(record: JsonObject, metric: str) -> JsonObject:
    return {key: value for key, value in record.items() if key != metric and key not in NON_MEASUREMENT_FIELDS}


def _tuple_key(fields: JsonObject) -> str:
    return json.dumps(fields, sort_keys=True, separators=(",", ":"))


def _aggregate(samples: tuple[ParsedSample, ...], metadata: CaptureMetadata) -> tuple[tuple[Aggregate, ...], tuple[str, ...]]:
    reasons: list[str] = []
    by_tuple: dict[str, list[float]] = {}
    fields_by_tuple: dict[str, JsonObject] = {}
    expected_keys: set[str] | None = None
    for sample in samples:
        sample_keys: set[str] = set()
        for record in sample.records:
            metric_value = record.get(metadata.metric)
            if isinstance(metric_value, bool) or not isinstance(metric_value, (int, float)) or not math.isfinite(float(metric_value)):
                reasons.append("malformed_jsonl")
                continue
            fields = _tuple_fields(record, metadata.metric)
            key = _tuple_key(fields)
            if key in sample_keys:
                reasons.append("duplicate_tuple")
            sample_keys.add(key)
            fields_by_tuple[key] = fields
            by_tuple.setdefault(key, []).append(float(metric_value))
        if expected_keys is None:
            expected_keys = sample_keys
        elif sample_keys != expected_keys:
            reasons.append("missing_tuple")
    aggregates = []
    for key in sorted(by_tuple):
        values = tuple(by_tuple[key])
        ordered = sorted(values)
        p95_index = min(len(ordered) - 1, max(0, math.ceil(len(ordered) * 0.95) - 1))
        aggregates.append(
            Aggregate(
                key,
                fields_by_tuple[key],
                values,
                {
                    "median": float(median(values)),
                    "p95": ordered[p95_index],
                    "min": ordered[0],
                    "max": ordered[-1],
                },
            )
        )
    return tuple(aggregates), tuple(sorted(set(reasons)))


def _report(
    metadata: CaptureMetadata,
    samples: tuple[ParsedSample, ...],
    runtime: dict[str, str] | None = None,
) -> CaptureReport:
    reasons = [reason for sample in samples for reason in sample.reasons]
    if len(samples) != metadata.requested_samples:
        reasons.append("missing_sample")
    aggregates, aggregation_reasons = _aggregate(samples, metadata)
    reasons.extend(aggregation_reasons)
    return CaptureReport(
        metadata,
        runtime if runtime is not None else _runtime_metadata(),
        samples,
        aggregates,
        "pass" if not reasons else "non-pass",
        tuple(sorted(set(reasons))),
    )


def summarize_paths(paths: list[Path], metadata: CaptureMetadata) -> CaptureReport:
    samples = []
    for path in paths:
        try:
            stdout = path.read_text(encoding="utf-8")
            samples.append(_parse_sample(str(path), stdout, "", 0, metadata))
        except OSError:
            samples.append(ParsedSample(str(path), "", "", 1, None, None, (), ("command_failure",)))
    return _report(metadata, tuple(samples))


def capture_command(metadata: CaptureMetadata, cwd: Path | None = None) -> CaptureReport:
    samples = []
    command = shlex.split(metadata.command)
    for index in range(metadata.requested_samples):
        started = time.perf_counter_ns()
        try:
            completed = subprocess.run(command, capture_output=True, text=True, cwd=cwd, check=False)
        except OSError as error:
            samples.append(ParsedSample(f"sample-{index + 1}", "", str(error), 1, None, None, (), ("command_failure",)))
            continue
        duration_ns = time.perf_counter_ns() - started
        rss_kb = _collect_rss_kb()
        samples.append(
            _parse_sample(
                f"sample-{index + 1}",
                completed.stdout,
                completed.stderr,
                completed.returncode,
                metadata,
                duration_ns,
                rss_kb,
            )
        )
    return _report(metadata, tuple(samples))


def compare_reports(before: CaptureReport, after: CaptureReport) -> ComparisonReport:
    reasons: list[str] = []
    if before.verdict != "pass" or after.verdict != "pass":
        reasons.append("input_non_pass")
    reasons.extend(before.reasons)
    reasons.extend(after.reasons)
    if before.metadata.command != after.metadata.command:
        reasons.append("command_mismatch")
    if before.metadata.requested_samples != after.metadata.requested_samples:
        reasons.append("requested_samples_mismatch")
    if before.metadata.fixture != after.metadata.fixture:
        reasons.append("fixture_mismatch")
    if before.metadata.fixture_dimensions != after.metadata.fixture_dimensions:
        reasons.append("fixture_dimensions_mismatch")
    if before.metadata.warmth != after.metadata.warmth:
        reasons.append("warmth_mismatch")
    if before.metadata.cache_state != after.metadata.cache_state:
        reasons.append("cache_state_mismatch")
    if before.metadata.metric != after.metadata.metric:
        reasons.append("metric_mismatch")
    if len(before.samples) != len(after.samples):
        reasons.append("missing_sample")
    before_by_key = {aggregate.tuple_key: aggregate for aggregate in before.aggregates}
    after_by_key = {aggregate.tuple_key: aggregate for aggregate in after.aggregates}
    if set(before_by_key) != set(after_by_key):
        reasons.append("missing_tuple")
    results = []
    for key in sorted(set(before_by_key) & set(after_by_key)):
        before_aggregate = before_by_key[key]
        after_aggregate = after_by_key[key]
        before_median = before_aggregate.statistics["median"]
        after_median = after_aggregate.statistics["median"]
        if after_median == before_median:
            label = "noise"
        elif after_median < before_median:
            label = "improvement"
        else:
            label = "regression"
        results.append(
            ComparisonResult(
                key,
                before_aggregate.tuple_fields,
                label,
                before_aggregate.statistics,
                after_aggregate.statistics,
                after_median - before_median,
            )
        )
    return ComparisonReport("pass" if not reasons else "non-pass", tuple(sorted(set(reasons))), tuple(results))
