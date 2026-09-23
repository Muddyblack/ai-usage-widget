"""Benchmark the real session index with safe synthetic source rows."""

# How to run: python3 benchmarks/session_index.py

from __future__ import annotations

import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from time import perf_counter_ns
from typing import Callable, NamedTuple

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY_ROOT / "package" / "contents" / "tools"))

from aiusage.session_index import SessionIndex  # noqa: E402

SIZES = (100, 1000, 10000)
WARMUPS = 3
ITERATIONS = 7
SOURCE_ID = "synthetic-source"
PROVIDER = "openai"
QUERY = "needle"
QUERY_LIMIT = 60
START_TIME = 1700000000000

Row = dict[str, str | int]


class Source(NamedTuple):
    """The safe source descriptor consumed by SessionIndex."""

    path: str
    source_id: str
    mtime_ns: int
    size: int


def make_source(root: Path, count: int) -> Source:
    """Create a deterministic source fixture inside the temporary directory."""
    path = root / "synthetic-source.jsonl"
    path.write_text("safe synthetic benchmark fixture\n", encoding="utf-8")
    return Source(str(path), SOURCE_ID, 1700000000000000000 + count, path.stat().st_size)


def make_parser(count: int) -> Callable[[Source], list[Row]]:
    """Return a parser callback that produces safe, redacted-shaped rows."""

    def parse(_source: Source) -> list[Row]:
        return [
            {
                "provider": PROVIDER,
                "title": f"Safe needle session-{index:05d}",
                "sessionName": "Synthetic fixture",
                "state": "idle",
                "lastActivityAt": START_TIME + index,
                "detail": "Safe deterministic benchmark row",
            }
            for index in range(count)
        ]

    return parse


def assert_query_result(index: SessionIndex, count: int) -> None:
    """Validate query totals, page, ordering, and continuation metadata."""
    result = index.query(QUERY, limit=QUERY_LIMIT, offset=0)
    sessions = result["sessions"]
    assert result["total"] == count
    assert result["totalExact"] is True
    assert result["offset"] == 0
    assert result["limit"] == QUERY_LIMIT
    assert result["hasMore"] is (count > QUERY_LIMIT)
    assert len(sessions) == min(count, QUERY_LIMIT)
    assert [row["lastActivityAt"] for row in sessions] == list(range(START_TIME + count - 1, START_TIME + count - len(sessions) - 1, -1))
    assert [row["title"] for row in sessions] == [f"Safe needle session-{index:05d}" for index in range(count - 1, count - len(sessions) - 1, -1)]


def timed_reconcile(count: int) -> int:
    """Reconcile one fresh temporary index and return elapsed nanoseconds."""
    with TemporaryDirectory(prefix="kde-ai-usage-session-") as directory:
        root = Path(directory)
        source = make_source(root, count)
        index = SessionIndex(root / "sessions.sqlite3")
        started = perf_counter_ns()
        index.reconcile([source], make_parser(count))
        return perf_counter_ns() - started


def timed_query(count: int) -> int:
    """Query one reconciled temporary index and return elapsed nanoseconds."""
    with TemporaryDirectory(prefix="kde-ai-usage-session-") as directory:
        root = Path(directory)
        source = make_source(root, count)
        index = SessionIndex(root / "sessions.sqlite3")
        index.reconcile([source], make_parser(count))
        started = perf_counter_ns()
        index.query(QUERY, limit=QUERY_LIMIT, offset=0)
        return perf_counter_ns() - started


def median_nanoseconds(samples: list[int]) -> int:
    """Return the middle sample from a fixed odd-sized sample set."""
    return sorted(samples)[len(samples) // 2]


def benchmark_reconcile(count: int) -> int:
    """Measure initial reconcile after a correctness preflight."""
    with TemporaryDirectory(prefix="kde-ai-usage-session-check-") as directory:
        root = Path(directory)
        source = make_source(root, count)
        index = SessionIndex(root / "sessions.sqlite3")
        index.reconcile([source], make_parser(count))
        assert_query_result(index, count)

    for _ in range(WARMUPS):
        timed_reconcile(count)
    samples = [timed_reconcile(count) for _ in range(ITERATIONS)]
    return median_nanoseconds(samples)


def benchmark_query(count: int) -> int:
    """Measure a fixed non-empty query after a correctness preflight."""
    with TemporaryDirectory(prefix="kde-ai-usage-session-check-") as directory:
        root = Path(directory)
        source = make_source(root, count)
        index = SessionIndex(root / "sessions.sqlite3")
        index.reconcile([source], make_parser(count))
        assert_query_result(index, count)

        for _ in range(WARMUPS):
            index.query(QUERY, limit=QUERY_LIMIT, offset=0)
        samples = []
        for _ in range(ITERATIONS):
            started = perf_counter_ns()
            index.query(QUERY, limit=QUERY_LIMIT, offset=0)
            samples.append(perf_counter_ns() - started)
    return median_nanoseconds(samples)


def main() -> None:
    """Write stable JSON objects for reconcile and query in size order."""
    for count in SIZES:
        for operation, median_ns in (
            ("reconcile", benchmark_reconcile(count)),
            ("query", benchmark_query(count)),
        ):
            print(
                json.dumps(
                    {
                        "benchmark": "session_index",
                        "operation": operation,
                        "points": count,
                        "median_ns": median_ns,
                        "warmups": WARMUPS,
                        "iterations": ITERATIONS,
                    },
                    separators=(",", ":"),
                )
            )


if __name__ == "__main__":
    main()
