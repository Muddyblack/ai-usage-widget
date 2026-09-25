from __future__ import annotations

import json
import os
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from threading import Lock
from typing import Final, Protocol, TextIO, TypedDict

TIMING_ENV_VAR: Final = "AI_USAGE_PROVIDER_TIMINGS"
_ENABLED_VALUES: Final = frozenset(("1", "true", "yes", "on"))


@dataclass(frozen=True, slots=True)
class ProviderTiming:
    provider_id: str
    elapsed_ms: float


class TimingSink(Protocol):
    def record(self, provider_id: str, elapsed_seconds: float) -> None: ...


class ProviderTimingCollector:
    def __init__(self) -> None:
        self._records: dict[str, ProviderTiming] = {}
        self._lock = Lock()

    def record(self, provider_id: str, elapsed_seconds: float) -> None:
        elapsed_ms = round(max(0.0, elapsed_seconds * 1000), 3)
        with self._lock:
            self._records[provider_id] = ProviderTiming(provider_id, elapsed_ms)

    def records(self) -> tuple[ProviderTiming, ...]:
        with self._lock:
            return tuple(sorted(self._records.values(), key=lambda record: record.provider_id))


class DiagnosticRow(TypedDict):
    id: str
    elapsedMs: float


class DiagnosticPayload(TypedDict):
    diagnostic: str
    providers: list[DiagnosticRow]


def timing_enabled(environment: Mapping[str, str] | None = None) -> bool:
    values = os.environ if environment is None else environment
    return values.get(TIMING_ENV_VAR, "").strip().lower() in _ENABLED_VALUES


def diagnostic_payload(records: Sequence[ProviderTiming]) -> DiagnosticPayload:
    return {
        "diagnostic": "provider-timings",
        "providers": [{"id": record.provider_id, "elapsedMs": record.elapsed_ms} for record in records],
    }


def emit_diagnostics(records: Sequence[ProviderTiming], stream: TextIO) -> None:
    stream.write(json.dumps(diagnostic_payload(records), separators=(",", ":"), ensure_ascii=False) + "\n")
