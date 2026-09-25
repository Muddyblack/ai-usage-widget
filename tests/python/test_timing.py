from __future__ import annotations

import contextlib
import io
import json
import os
import re
import unittest
from contextlib import ExitStack
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Final, TypeAlias, TypedDict
from unittest import mock

from _support import IsolatedHomeTest, raw_fixture
from aiusage import __main__ as backend
from aiusage import envelope
from aiusage.config import ALL_PROVIDERS
from aiusage.timing import (
    TIMING_ENV_VAR,
    ProviderTimingCollector,
    diagnostic_payload,
)

JsonValue: TypeAlias = str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]


class FixtureState(str, Enum):
    SUCCESS = "success"
    MISSING_CREDENTIALS = "missing-credentials"
    MALFORMED = "malformed"
    TIMEOUT = "timeout"
    RATE_LIMITED = "rate-limited"
    STALE_CACHE = "stale-cache"


class FixtureEnvelope(TypedDict):
    id: str
    label: str
    accent: str
    ok: bool
    stale: bool
    error: str
    updatedAt: int
    summary: dict[str, JsonValue]
    quotaWindows: list[JsonValue]
    chartWindows: list[JsonValue]
    slots: list[JsonValue]
    historyValues: dict[str, JsonValue]
    details: dict[str, JsonValue]


class SessionFixtureRow(TypedDict):
    provider: str
    title: str
    sessionName: str
    state: str
    lastActivityAt: int
    detail: str


@dataclass(frozen=True, slots=True)
class FixtureMalformedError(RuntimeError):
    provider_id: str

    def __str__(self) -> str:
        return f"{self.provider_id}: malformed offline fixture"


@dataclass(frozen=True, slots=True)
class FixtureTimeoutError(TimeoutError):
    provider_id: str

    def __str__(self) -> str:
        return f"{self.provider_id}: offline timeout"


def _row(provider_id: str, now: float, ok: bool, stale: bool, error: str, details: dict[str, JsonValue]) -> FixtureEnvelope:
    return {
        "id": provider_id,
        "label": provider_id,
        "accent": "#64748b",
        "ok": ok,
        "stale": stale,
        "error": error,
        "updatedAt": int(now),
        "summary": {"pct": 0, "text": "", "detail": error, "hasChart": False},
        "quotaWindows": [],
        "chartWindows": [],
        "slots": [],
        "historyValues": {},
        "details": details,
    }


def _success(provider_id: str, now: float) -> FixtureEnvelope:
    return _row(provider_id, now, True, False, "", {"status": {"indicator": "none"}})


def _missing(provider_id: str, now: float) -> FixtureEnvelope:
    return _row(provider_id, now, False, False, f"{provider_id}: not configured", {"status": {"indicator": "none"}})


def _malformed(provider_id: str, _now: float) -> FixtureEnvelope:
    raise FixtureMalformedError(provider_id)


def _timeout(provider_id: str, _now: float) -> FixtureEnvelope:
    raise FixtureTimeoutError(provider_id)


def _rate_limited(provider_id: str, now: float) -> FixtureEnvelope:
    return _row(provider_id, now, False, True, f"{provider_id}: rate limited", {"status": {"indicator": "minor"}})


def _stale_cache(provider_id: str, now: float) -> FixtureEnvelope:
    return _row(
        provider_id,
        now,
        True,
        True,
        "",
        {"status": {"indicator": "none"}, "cache": {"source": "offline", "ageSeconds": 90}},
    )


FixtureBuilder: TypeAlias = Callable[[str, float], FixtureEnvelope]
_FIXTURE_BUILDERS: Final[dict[FixtureState, FixtureBuilder]] = {
    FixtureState.SUCCESS: _success,
    FixtureState.MISSING_CREDENTIALS: _missing,
    FixtureState.MALFORMED: _malformed,
    FixtureState.TIMEOUT: _timeout,
    FixtureState.RATE_LIMITED: _rate_limited,
    FixtureState.STALE_CACHE: _stale_cache,
}


def _expected_shape(state: FixtureState) -> tuple[bool, bool, bool]:
    """The (ok, stale, has_error) triple each offline state must produce."""
    if state is FixtureState.SUCCESS:
        return (True, False, False)
    if state is FixtureState.MISSING_CREDENTIALS:
        return (False, False, True)
    if state is FixtureState.MALFORMED:
        return (False, True, True)
    if state is FixtureState.TIMEOUT:
        return (False, True, True)
    if state is FixtureState.RATE_LIMITED:
        return (False, True, True)
    if state is FixtureState.STALE_CACHE:
        return (True, True, False)
    raise AssertionError(f"unhandled fixture state: {state}")


@dataclass(frozen=True, slots=True)
class OfflineProviderDouble:
    provider_id: str
    state: FixtureState

    def collect(self, now: float) -> FixtureEnvelope:
        return _FIXTURE_BUILDERS[self.state](self.provider_id, now)


def fixture_doubles() -> tuple[OfflineProviderDouble, ...]:
    return tuple(OfflineProviderDouble(provider_id, state) for provider_id in ALL_PROVIDERS for state in FixtureState)


def large_local_store(size: int = 10_000) -> tuple[SessionFixtureRow, ...]:
    return tuple(
        {
            "provider": "claude",
            "title": f"Fixture session {index}",
            "sessionName": "Offline fixture",
            "state": "idle",
            "lastActivityAt": index,
            "detail": "safe detail",
        }
        for index in range(size)
    )


class OfflineFixtureCoverageTest(unittest.TestCase):
    def _build(self, double: OfflineProviderDouble) -> tuple[dict[str, JsonValue], ProviderTimingCollector]:
        timings = ProviderTimingCollector()
        with (
            mock.patch.object(envelope, "collect", side_effect=lambda _provider_id, now: double.collect(now)),
            mock.patch.object(envelope, "normalize", side_effect=lambda value: value),
            mock.patch.object(envelope, "_local_spend", return_value={}),
        ):
            result = envelope.build([double.provider_id], now=1_800_000_000, timing=timings)
        return result, timings

    def test_every_provider_state_pair_executes_through_build(self):
        cases = fixture_doubles()
        self.assertEqual(len(cases), len(ALL_PROVIDERS) * len(FixtureState))
        for double in cases:
            with self.subTest(provider=double.provider_id, state=double.state.value):
                result, timings = self._build(double)
                self.assertEqual(len(result["providers"]), 1)
                provider = result["providers"][0]
                self.assertEqual(provider["id"], double.provider_id)
                ok, stale, has_error = _expected_shape(double.state)
                self.assertEqual(provider["ok"], ok)
                self.assertEqual(provider["stale"], stale)
                self.assertEqual(bool(provider["error"]), has_error)
                records = timings.records()
                self.assertEqual(len(records), 1)
                self.assertEqual(records[0].provider_id, double.provider_id)

    def test_fixture_builder_map_is_complete(self):
        # Mutation guard: dropping any builder from the map must fail this
        # test and the execution test above (KeyError on collect).
        self.assertEqual(set(_FIXTURE_BUILDERS), set(FixtureState))

    def test_provider_failure_isolated_and_timed(self):
        malformed = OfflineProviderDouble("claude", FixtureState.MALFORMED)
        healthy = OfflineProviderDouble("openai", FixtureState.SUCCESS)
        timings = ProviderTimingCollector()

        def collect(provider_id: str, now: float) -> FixtureEnvelope:
            return (malformed if provider_id == "claude" else healthy).collect(now)

        with (
            mock.patch.object(envelope, "collect", side_effect=collect),
            mock.patch.object(envelope, "normalize", side_effect=lambda value: value),
            mock.patch.object(envelope, "_local_spend", return_value={}),
        ):
            result = envelope.build(["claude", "openai"], now=1_800_000_000, timing=timings)

        self.assertFalse(result["providers"][0]["ok"])
        self.assertTrue(result["providers"][1]["ok"])
        self.assertEqual({row.provider_id for row in timings.records()}, {"claude", "openai"})

    def test_timeout_and_rate_limit_shapes_are_timed(self):
        for state in (FixtureState.TIMEOUT, FixtureState.RATE_LIMITED):
            with self.subTest(state=state):
                result, timings = self._build(OfflineProviderDouble("claude", state))
                provider = result["providers"][0]
                self.assertEqual([row.provider_id for row in timings.records()], ["claude"])
                if state is FixtureState.TIMEOUT:
                    self.assertFalse(provider["ok"])
                    self.assertTrue(provider["stale"])
                else:
                    self.assertFalse(provider["ok"])
                    self.assertTrue(provider["stale"])

    def test_stale_cache_shape_is_preserved_and_timed(self):
        result, timings = self._build(OfflineProviderDouble("claude", FixtureState.STALE_CACHE))
        provider = result["providers"][0]
        self.assertTrue(provider["ok"])
        self.assertTrue(provider["stale"])
        self.assertEqual(provider["details"]["cache"], {"source": "offline", "ageSeconds": 90})
        self.assertEqual([row.provider_id for row in timings.records()], ["claude"])

    def test_timing_payload_is_whitelisted_and_secret_free(self):
        timings = ProviderTimingCollector()
        timings.record("claude", 0.004)
        timings.record("openai", 0.008)
        payload = diagnostic_payload(timings.records())
        encoded = json.dumps(payload, sort_keys=True)
        self.assertEqual(set(payload), {"diagnostic", "providers"})
        self.assertEqual({"id", "elapsedMs"}, set(payload["providers"][0]))
        self.assertNotRegex(encoded, re.compile(r"(?i)token|secret|key|password|prompt|transcript|path|session"))
        self.assertEqual({row["id"] for row in payload["providers"]}, {"claude", "openai"})

    def test_large_local_store_fixture_is_deterministic_and_redacted(self):
        rows = large_local_store()
        self.assertEqual(len(rows), 10_000)
        self.assertEqual(rows[0]["title"], "Fixture session 0")
        self.assertEqual(rows[-1]["lastActivityAt"], 9_999)
        self.assertNotRegex(json.dumps(rows), re.compile(r"(?i)token|secret|key|password|prompt|transcript|path|session-id"))


class TimingCliContractTest(IsolatedHomeTest):
    def _run(self, opt_in: str | None, freeze_clock: bool = True) -> tuple[str, str]:
        output = io.StringIO()
        errors = io.StringIO()
        env = {TIMING_ENV_VAR: "" if opt_in is None else opt_in}
        patches = [
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(envelope, "collect", return_value=raw_fixture("claude-success")),
            mock.patch.object(envelope, "_local_spend", return_value={}),
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(errors),
        ]
        if freeze_clock:
            patches.append(mock.patch.object(envelope.time, "time", return_value=1_800_000_000))
        with ExitStack() as stack:
            for patch in patches:
                stack.enter_context(patch)
            self.assertEqual(backend.main(["--provider", "claude"]), 0)
        return output.getvalue(), errors.getvalue()

    def test_default_output_keeps_current_contract_without_timing(self):
        stdout, stderr = self._run(None)
        payload = json.loads(stdout)
        self.assertEqual(set(payload), {"schemaVersion", "updatedAt", "active", "providers", "localSpend"})
        self.assertNotIn("elapsedMs", stdout)
        self.assertEqual(stderr, "")

    def test_opt_in_timing_preserves_stdout_bytes_with_frozen_clock(self):
        default_stdout, default_stderr = self._run(None, freeze_clock=True)
        diagnostic_stdout, diagnostic_stderr = self._run("1", freeze_clock=True)
        self.assertEqual(default_stdout, diagnostic_stdout)
        self.assertEqual(default_stderr, "")
        diagnostic = json.loads(diagnostic_stderr)
        self.assertEqual(diagnostic["diagnostic"], "provider-timings")
        self.assertEqual([row["id"] for row in diagnostic["providers"]], ["claude"])
        self.assertIsInstance(diagnostic["providers"][0]["elapsedMs"], (int, float))

    def test_opt_in_stdout_is_semantically_equivalent_without_frozen_clock(self):
        default_stdout, _ = self._run(None, freeze_clock=False)
        diagnostic_stdout, diagnostic_stderr = self._run("1", freeze_clock=False)
        default_payload = json.loads(default_stdout)
        diagnostic_payload = json.loads(diagnostic_stdout)
        for payload in (default_payload, diagnostic_payload):
            payload["updatedAt"] = 0
        self.assertEqual(default_payload, diagnostic_payload)
        diagnostic = json.loads(diagnostic_stderr)
        self.assertEqual(diagnostic["diagnostic"], "provider-timings")
        self.assertEqual([row["id"] for row in diagnostic["providers"]], ["claude"])


if __name__ == "__main__":
    unittest.main()
