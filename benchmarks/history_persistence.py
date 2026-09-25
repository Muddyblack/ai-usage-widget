"""Benchmark the real history autosave path with synthetic points only."""

# How to run: python3 benchmarks/history_persistence.py

from __future__ import annotations

import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from time import perf_counter_ns

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY_ROOT / "package" / "contents" / "tools"))

from aiusage import historyio  # noqa: E402

SIZES = (100, 1000, 10000)
WARMUPS = 3
ITERATIONS = 7
START_TIME = 1700000000000
STEP_MS = 300000


def make_points(count: int) -> list[dict[str, int]]:
    """Build one deterministic history series."""
    return [
        {
            "t": START_TIME + index * STEP_MS,
            "w": (index * 17) % 101,
            "cp": (index * 31) % 101,
        }
        for index in range(count)
    ]


def assert_autosave_output(output: str, count: int) -> None:
    """Verify one autosave response without putting checks in timed loops."""
    result = json.loads(output)
    assert result["ok"] is True
    assert len(result["data"]) == count
    assert result["data"][0]["t"] == START_TIME
    assert result["data"][-1]["t"] == START_TIME + (count - 1) * STEP_MS


def timed_autosave(payload: str) -> int:
    """Run one isolated autosave and return its elapsed nanoseconds."""
    with TemporaryDirectory(prefix="kde-ai-usage-history-") as directory:
        started = perf_counter_ns()
        historyio.run("autosave", payload, directory)
        return perf_counter_ns() - started


def median_nanoseconds(samples: list[int]) -> int:
    """Return the middle sample from a fixed odd-sized sample set."""
    return sorted(samples)[len(samples) // 2]


def benchmark(count: int) -> int:
    """Measure autosave for one deterministic point count."""
    points = make_points(count)
    payload = json.dumps(points, separators=(",", ":"))
    with TemporaryDirectory(prefix="kde-ai-usage-history-check-") as directory:
        output = historyio.run("autosave", payload, directory)
    assert_autosave_output(output, count)

    for _ in range(WARMUPS):
        timed_autosave(payload)
    samples = [timed_autosave(payload) for _ in range(ITERATIONS)]
    return median_nanoseconds(samples)


def main() -> None:
    """Write one stable JSON object per benchmark case."""
    for count in SIZES:
        median_ns = benchmark(count)
        print(
            json.dumps(
                {
                    "benchmark": "history_persistence",
                    "operation": "autosave",
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
