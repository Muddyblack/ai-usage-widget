import json
import os
import sqlite3
import tempfile
import unittest
from unittest import mock

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)
from aiusage import billing
from aiusage.providers import opencode

_SESSION_SCHEMA = """
CREATE TABLE session (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    directory TEXT NOT NULL,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL
);
"""
_MESSAGE_SCHEMA = """
CREATE TABLE message (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    data TEXT NOT NULL
);
"""
_PART_SCHEMA = """
CREATE TABLE part (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    data TEXT NOT NULL
);
"""
_V2_MESSAGE_SCHEMA = """
CREATE TABLE session_message (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    type TEXT NOT NULL,
    seq INTEGER NOT NULL,
    data TEXT NOT NULL
);
"""
TokenShape = dict[str, int | dict[str, int]]


def _create_database(
    root: str,
    *,
    messages: list[tuple[str, str, str]] | None = None,
    parts: list[tuple[str, str, str]] | None = None,
    include_usage_tables: bool = True,
) -> str:
    path = os.path.join(root, "opencode.db")
    connection = sqlite3.connect(path)
    try:
        with connection:
            connection.executescript(_SESSION_SCHEMA)
            connection.execute(
                "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                ("session-1", "Synthetic session", "/synthetic/project", 1, 2_000),
            )
            if include_usage_tables:
                connection.executescript(_MESSAGE_SCHEMA + _PART_SCHEMA)
                connection.executemany("INSERT INTO message VALUES (?, ?, ?)", messages or [])
                connection.executemany("INSERT INTO part VALUES (?, ?, ?)", parts or [])
    finally:
        connection.close()
    return path


def _assistant_message(
    message_id: str = "message-1",
    *,
    model: str = "gpt-test",
    provider_id: str | None = "anthropic",
    tokens: TokenShape | None = None,
    cost: int | float | None = None,
    session_id: str = "session-1",
) -> tuple[str, str, str]:
    data: dict[str, str | dict[str, str] | TokenShape | int | float] = {
        "role": "assistant",
        "modelID": model,
        "providerID": provider_id,
    }
    if tokens is not None:
        data["tokens"] = tokens
    if cost is not None:
        data["cost"] = cost
    return (message_id, session_id, json.dumps(data, allow_nan=True))


def _part(part_id: str = "part-1", message_id: str = "message-1") -> tuple[str, str, str]:
    return (
        part_id,
        message_id,
        json.dumps(
            {
                "type": "step-finish",
                "cost": 0.42,
                "tokens": {"input": 800, "output": 100, "reasoning": 10, "cache": {"read": 200, "write": 20}},
            }
        ),
    )


def _read_record(path: str) -> opencode.OpenCodeSession:
    with mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True):
        return opencode.read_recent_sessions()[0]


def _create_v2_database(root: str) -> str:
    path = os.path.join(root, "opencode.db")
    connection = sqlite3.connect(path)
    try:
        with connection:
            connection.executescript(_SESSION_SCHEMA + _V2_MESSAGE_SCHEMA)
            connection.execute(
                "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                ("session-1", "Synthetic V2 session", "/synthetic/project", 1, 2_000),
            )
            connection.execute(
                "INSERT INTO session_message VALUES (?, ?, ?, ?, ?)",
                (
                    "message-v2",
                    "session-1",
                    "assistant",
                    1,
                    json.dumps(
                        {
                            "model": {"providerID": "openai", "id": "gpt-test"},
                            "tokens": {"input": 3, "output": 4, "reasoning": 1, "cache": {"read": 2, "write": 0}},
                            "content": [{"type": "text", "text": "must not be parsed"}],
                        }
                    ),
                ),
            )
    finally:
        connection.close()
    return path


def _create_mixed_database(
    root: str,
    messages: list[tuple[str, str, str]],
    v2_messages: list[tuple[str, str, str, int, str]],
) -> str:
    path = os.path.join(root, "opencode.db")
    connection = sqlite3.connect(path)
    try:
        with connection:
            connection.executescript(_SESSION_SCHEMA + _MESSAGE_SCHEMA + _V2_MESSAGE_SCHEMA)
            connection.execute(
                "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                ("session-1", "Synthetic mixed session", "/synthetic/project", 1, 2_000),
            )
            connection.executemany("INSERT INTO message VALUES (?, ?, ?)", messages)
            connection.executemany("INSERT INTO session_message VALUES (?, ?, ?, ?, ?)", v2_messages)
    finally:
        connection.close()
    return path


class OpenCodeUsageReaderTest(unittest.TestCase):
    def test_schema_present_empty_v2_falls_back_to_populated_v1_message_usage(self):
        message = _assistant_message(tokens={"input": 800, "output": 100}, cost=0.42)
        with tempfile.TemporaryDirectory() as root:
            path = _create_mixed_database(root, [message], [])
            record = _read_record(path)

        self.assertEqual(len(record.usage), 1)
        self.assertEqual(record.usage[0].provider_cost_usd, 0.42)
        self.assertEqual(record.usage[0].input_tokens, 800)

    def test_populated_v2_usage_remains_preferred_over_populated_v1_usage(self):
        v1_message = _assistant_message(tokens={"input": 800, "output": 100}, cost=0.42)
        v2_message = (
            "message-v2",
            "session-1",
            "assistant",
            1,
            json.dumps(
                {
                    "model": {"providerID": "openai", "id": "v2-model"},
                    "tokens": {"input": 3, "output": 4, "reasoning": 1, "cache": {"read": 2, "write": 0}},
                }
            ),
        )
        with tempfile.TemporaryDirectory() as root:
            path = _create_mixed_database(root, [v1_message], [v2_message])
            record = _read_record(path)

        self.assertEqual(len(record.usage), 1)
        self.assertEqual(record.usage[0].model, "v2-model")
        self.assertEqual(record.usage[0].input_tokens, 3)

    def test_reads_exact_assistant_message_usage_for_shared_billing(self):
        message = _assistant_message(
            tokens={
                "input": 800,
                "output": 100,
                "reasoning": 10,
                "cache": {"read": 200, "write": 20},
            }
        )
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            with mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True):
                record = opencode.read_recent_sessions()[0]

        self.assertEqual(
            record.usage,
            (
                billing.UsageBucket(
                    "anthropic",
                    "gpt-test",
                    "session-1",
                    input_tokens=800,
                    output_tokens=100,
                    cache_read_tokens=200,
                    cache_write_tokens=20,
                    reasoning_tokens=10,
                    source="opencode",
                ),
            ),
        )

    def test_malformed_provider_id_is_unavailable(self):
        for provider_id in (None, "bad provider!", "x" * 65):
            with self.subTest(provider_id=provider_id), tempfile.TemporaryDirectory() as root:
                record = _read_record(
                    _create_database(
                        root,
                        messages=[_assistant_message(provider_id=provider_id, tokens={"output": 100})],
                    )
                )

            self.assertEqual(record.usage, ())

    def test_accepts_any_safely_normalized_provider_id(self):
        for provider_id in ("ollama-cloud", "github-copilot", "zenmux"):
            with self.subTest(provider_id=provider_id), tempfile.TemporaryDirectory() as root:
                record = _read_record(
                    _create_database(
                        root,
                        messages=[_assistant_message(provider_id=provider_id, tokens={"output": 100})],
                    )
                )

            self.assertEqual(record.usage[0].provider, provider_id)
            self.assertEqual(record.usage[0].source, "opencode")

    def test_aggregates_more_than_240_messages_without_truncation(self):
        messages = [_assistant_message(f"message-{index:03d}", tokens={"input": 10, "output": 5}, cost=0.01) for index in range(300)]
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=messages))

        self.assertEqual(len(record.usage), 1)
        self.assertEqual(record.usage[0].input_tokens, 3000)
        self.assertEqual(record.usage[0].output_tokens, 1500)
        self.assertAlmostEqual(record.usage[0].provider_cost_usd, 3.0)

    def test_late_provider_usage_is_not_truncated_by_earlier_rows(self):
        messages = [_assistant_message(f"message-{index:03d}", provider_id="openai", tokens={"output": 1}) for index in range(240)]
        messages.append(_assistant_message("message-late", provider_id="ollama-cloud", tokens={"output": 7}))
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=messages))

        self.assertEqual({bucket.provider for bucket in record.usage}, {"openai", "ollama-cloud"})
        self.assertEqual(record.usage[1].provider, "ollama-cloud")

    def test_provider_id_is_case_normalized_for_billing_identity(self):
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(
                _create_database(
                    root,
                    messages=[_assistant_message(provider_id=" OPENAI ", tokens={"output": 100})],
                )
            )

        self.assertEqual(record.usage[0].provider, "openai")
        self.assertEqual(record.usage[0].source, "opencode")

    def test_prices_tokens_only_when_cached_model_pricing_exists(self):
        message = _assistant_message(tokens={"input": 800, "output": 100, "reasoning": 10, "cache": {"read": 200, "write": 20}})
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=[message]))

        result = billing.aggregate_session_usage(
            record.usage,
            {"anthropic": {"gpt-test": {"input": 2, "output": 8, "cached": 0.2}}},
        )
        self.assertEqual(result["costStatus"], "exact")
        self.assertEqual(result["costUSD"], 0.00216)

    def test_prices_positive_tokens_when_provider_cost_is_zero(self):
        message = _assistant_message(
            tokens={"input": 800, "output": 100, "reasoning": 10, "cache": {"read": 200, "write": 20}},
            cost=0,
        )
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=[message]))

        result = billing.aggregate_session_usage(
            record.usage,
            {"anthropic": {"gpt-test": {"input": 2, "output": 8, "cached": 0.2}}},
        )
        self.assertEqual(result["costStatus"], "exact")
        self.assertEqual(result["costUSD"], 0.00216)

    def test_keeps_provider_reported_finite_cost_without_pricing(self):
        cases = ((0, {"input": 0, "output": 0}), (0.42, {"input": 800, "output": 100}))
        for cost, tokens in cases:
            with self.subTest(cost=cost):
                message = _assistant_message(tokens=tokens, cost=cost)
                with tempfile.TemporaryDirectory() as root:
                    record = _read_record(_create_database(root, messages=[message]))

                result = billing.aggregate_session_usage(record.usage, {})
                self.assertEqual(result["costUSD"], cost)
                self.assertEqual(result["costStatus"], "exact")
                self.assertEqual(result["costProvenance"], "actual")

    def test_reports_partial_for_known_and_unknown_models(self):
        messages = [
            _assistant_message(tokens={"output": 100}),
            _assistant_message("message-2", model="unpriced", tokens={"output": 100}),
        ]
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=messages))

        result = billing.aggregate_session_usage(
            record.usage,
            {"anthropic": {"gpt-test": {"input": 0, "output": 8}}},
        )
        self.assertEqual(result["costStatus"], "partial")
        self.assertEqual(result["costUSD"], 0.0008)

    def test_leaves_unknown_model_unavailable_without_estimate(self):
        message = _assistant_message(model="unpriced", tokens={"output": 100})
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=[message]))

        self.assertEqual(billing.aggregate_session_usage(record.usage, {}), {"costStatus": "unavailable"})

    def test_leaves_metadata_only_session_unavailable(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, include_usage_tables=False)
            record = _read_record(path)

        self.assertEqual(record.usage, ())
        self.assertEqual(billing.aggregate_session_usage(record.usage, {}), {"costStatus": "unavailable"})

    def test_ignores_invalid_and_non_assistant_usage(self):
        invalid = _assistant_message(tokens={"input": float("nan"), "output": -1})
        user = ("message-user", "session-1", json.dumps({"role": "user", "tokens": {"output": 100}}))
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=[invalid, user]))

        self.assertEqual(record.usage, ())

    def test_prefers_step_finish_part_once_when_message_repeats_usage(self):
        message = _assistant_message(
            tokens={"input": 800, "output": 100, "reasoning": 10, "cache": {"read": 200, "write": 20}},
            cost=0.42,
        )
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_database(root, messages=[message], parts=[_part()]))

        self.assertEqual(len(record.usage), 1)
        self.assertEqual(record.usage[0].provider_cost_usd, 0.42)

    def test_returns_metadata_when_usage_query_deadline_has_elapsed(self):
        message = _assistant_message(tokens={"output": 100})
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=[message])
            with mock.patch.object(opencode, "_QUERY_TIMEOUT_SECONDS", -1):
                record = _read_record(path)

        self.assertEqual(record.title, "Synthetic session")
        self.assertEqual(record.usage, ())

    def test_expired_per_session_query_does_not_starve_later_sessions(self):
        messages = [
            _assistant_message(tokens={"output": 50}),
            _assistant_message("message-2", session_id="session-2", tokens={"output": 50}),
        ]
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=messages)
            connection = sqlite3.connect(path)
            try:
                with connection:
                    connection.execute(
                        "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                        ("session-2", "Synthetic session 2", "/synthetic/project", 1, 1_000),
                    )
            finally:
                connection.close()
            read_usage = opencode._read_usage

            def expire_first_session(connection, session_id):
                if session_id == "session-1":
                    with mock.patch.object(opencode, "_QUERY_TIMEOUT_SECONDS", -1):
                        return read_usage(connection, session_id)
                return read_usage(connection, session_id)

            with (
                mock.patch.object(opencode, "_read_usage", side_effect=expire_first_session),
                mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True),
            ):
                records = opencode.read_recent_sessions()

        self.assertEqual(len(records), 2)
        self.assertEqual(records[0].usage, ())
        self.assertEqual(records[1].usage[0].output_tokens, 50)

    def test_usage_enrichment_has_no_total_session_read_budget(self):
        messages = [
            _assistant_message(tokens={"output": 50}),
            _assistant_message("message-2", session_id="session-2", tokens={"output": 50}),
            _assistant_message("message-3", session_id="session-3", tokens={"output": 50}),
        ]
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, messages=messages)
            connection = sqlite3.connect(path)
            try:
                with connection:
                    connection.executemany(
                        "INSERT INTO session VALUES (?, ?, ?, ?, ?)",
                        [
                            ("session-2", "Synthetic session 2", "/synthetic/project", 1, 1_000),
                            ("session-3", "Synthetic session 3", "/synthetic/project", 1, 500),
                        ],
                    )
            finally:
                connection.close()
            with (
                mock.patch.object(opencode, "_read_usage", return_value=()) as read_usage,
                mock.patch.dict(os.environ, {"OPENCODE_DB": path}, clear=True),
            ):
                records = opencode.read_recent_sessions()

        self.assertEqual([record.session_id for record in records], ["session-1", "session-2", "session-3"])
        self.assertEqual(read_usage.call_count, 3)

    def test_connection_is_read_only_and_query_only(self):
        with tempfile.TemporaryDirectory() as root:
            path = _create_database(root, include_usage_tables=False)
            with opencode._connect_readonly(path) as connection:
                self.assertEqual(connection.execute("PRAGMA query_only").fetchone()[0], 1)
                with self.assertRaises(sqlite3.OperationalError):
                    connection.execute("CREATE TABLE forbidden (value TEXT)")

    def test_reads_current_v2_assistant_message_schema(self):
        with tempfile.TemporaryDirectory() as root:
            record = _read_record(_create_v2_database(root))

        self.assertEqual(record.title, "Synthetic V2 session")
        self.assertEqual(record.usage[0].provider, "openai")
        self.assertEqual(record.usage[0].source, "opencode")
        self.assertEqual(record.usage[0].model, "gpt-test")
        self.assertEqual(record.usage[0].input_tokens, 3)


if __name__ == "__main__":
    unittest.main()
