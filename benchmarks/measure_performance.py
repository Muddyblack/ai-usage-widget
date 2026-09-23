from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from performance_harness import capture_command, compare_reports, summarize_paths
from performance_harness_io import comparison_to_json, report_from_json, report_to_json
from performance_harness_types import CaptureMetadata, CaptureReport, JsonObject


def _dimensions(values: list[str]) -> tuple[tuple[str, str], ...]:
    dimensions = []
    for value in values:
        key, separator, item = value.partition("=")
        if not separator or not key or not item:
            raise ValueError(f"fixture dimension must be key=value: {value}")
        dimensions.append((key, item))
    return tuple(sorted(dimensions))


def _metadata(args: argparse.Namespace, command: str) -> CaptureMetadata:
    return CaptureMetadata(
        command=command,
        fixture=args.fixture,
        fixture_dimensions=_dimensions(args.fixture_dimension),
        warmth=args.warmth,
        cache_state=args.cache_state,
        metric=args.metric,
        requested_samples=args.samples,
    )


def _write_document(document: JsonObject, output: Path | None) -> None:
    text = json.dumps(document, indent=2, sort_keys=True) + "\n"
    if output is None:
        sys.stdout.write(text)
    else:
        output.write_text(text, encoding="utf-8")


def _write_raw_samples(report: CaptureReport, directory: Path | None) -> None:
    if directory is None:
        return
    directory.mkdir(parents=True, exist_ok=True)
    for index, sample in enumerate(report.samples, start=1):
        (directory / f"sample-{index}.stdout").write_text(sample.stdout, encoding="utf-8")
        (directory / f"sample-{index}.stderr").write_text(sample.stderr, encoding="utf-8")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Capture and compare benchmark JSONL samples.")
    commands = parser.add_subparsers(dest="action", required=True)
    for name in ("capture", "summarize"):
        command = commands.add_parser(name)
        command.add_argument("--command", default="existing benchmark artifacts")
        command.add_argument("--fixture", default="unspecified")
        command.add_argument("--fixture-dimension", action="append", default=[])
        command.add_argument("--warmth", choices=("cold", "warm"), default="warm")
        command.add_argument("--cache-state", choices=("cold", "warm", "unknown"), default="unknown")
        command.add_argument("--metric", default="median_ns")
        command.add_argument("--samples", type=int, default=5)
        command.add_argument("--output", type=Path)
        command.add_argument("--raw-output-dir", type=Path)
        if name == "capture":
            command.add_argument("--cwd", type=Path)
        else:
            command.add_argument("--input", type=Path, action="append", required=True)
    compare = commands.add_parser("compare")
    compare.add_argument("--before", type=Path, required=True)
    compare.add_argument("--after", type=Path, required=True)
    compare.add_argument("--output", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.action == "capture":
            if args.samples < 1:
                raise ValueError("samples must be positive")
            report = capture_command(_metadata(args, args.command), args.cwd)
            _write_raw_samples(report, args.raw_output_dir)
            _write_document(report_to_json(report), args.output)
            return 0 if report.verdict == "pass" else 1
        if args.action == "summarize":
            if args.samples < 1:
                raise ValueError("samples must be positive")
            report = summarize_paths(args.input, _metadata(args, args.command))
            _write_raw_samples(report, args.raw_output_dir)
            _write_document(report_to_json(report), args.output)
            return 0 if report.verdict == "pass" else 1
        before_document: JsonObject = json.loads(args.before.read_text(encoding="utf-8"))
        after_document: JsonObject = json.loads(args.after.read_text(encoding="utf-8"))
        comparison = compare_reports(report_from_json(before_document), report_from_json(after_document))
        _write_document(comparison_to_json(comparison), args.output)
        return 0 if comparison.verdict == "pass" else 1
    except (OSError, ValueError, json.JSONDecodeError) as error:
        sys.stderr.write(f"performance harness: {error}\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
