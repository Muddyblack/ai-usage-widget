from __future__ import annotations

from dataclasses import dataclass
from typing import Final, TypeAlias

JsonValue: TypeAlias = str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]
DEFAULT_SAMPLE_COUNT: Final = 5
NON_MEASUREMENT_FIELDS: Final = frozenset({"median_ns"})
CALLER_DECLARED: Final = "caller-declared"


@dataclass(frozen=True)
class CaptureMetadata:
    command: str
    fixture: str
    fixture_dimensions: tuple[tuple[str, str], ...]
    warmth: str
    cache_state: str
    metric: str = "median_ns"
    requested_samples: int = DEFAULT_SAMPLE_COUNT
    warmth_source: str = CALLER_DECLARED
    cache_state_source: str = CALLER_DECLARED


@dataclass(frozen=True)
class ParsedSample:
    source: str
    stdout: str
    stderr: str
    returncode: int
    duration_ns: int | None
    rss_kb: int | None
    records: tuple[JsonObject, ...]
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class Aggregate:
    tuple_key: str
    tuple_fields: JsonObject
    samples: tuple[float, ...]
    statistics: dict[str, float]


@dataclass(frozen=True)
class CaptureReport:
    metadata: CaptureMetadata
    runtime: dict[str, str]
    samples: tuple[ParsedSample, ...]
    aggregates: tuple[Aggregate, ...]
    verdict: str
    reasons: tuple[str, ...]


@dataclass(frozen=True)
class ComparisonResult:
    tuple_key: str
    tuple_fields: JsonObject
    label: str
    before: dict[str, float]
    after: dict[str, float]
    median_delta: float


@dataclass(frozen=True)
class ComparisonReport:
    verdict: str
    reasons: tuple[str, ...]
    results: tuple[ComparisonResult, ...]
