"""Mistral Vibe local stats: an unchanged log store skips the recursive parse.

The cache is keyed by an opaque digest of the canonical session directory and
invalidated by a shared source fingerprint over every ``meta.json`` file, so a
changed, added, renamed, or deleted log recomputes while a steady store serves
the cached aggregate. It never stores the API response or any key material.
"""

import json
import os
import time
import unittest
from unittest import mock

import _support  # noqa: F401  (sys.path)
from aiusage.http import HttpResult
from aiusage.providers import mistral
from aiusage.providers.mistral import get_mistral_usage


def _meta(session_id, title="refactor", cost=0.4, tokens=1000, start="2026-09-10T10:00:00Z"):
    return {
        "session_id": session_id,
        "title": title,
        "start_time": start,
        "end_time": "2026-09-10T11:00:00Z",
        "environment": {"working_directory": "/home/user/project"},
        "config": {"active_model": "codestral"},
        "stats": {
            "session_cost": cost,
            "session_total_llm_tokens": tokens,
            "session_prompt_tokens": 600,
            "session_completion_tokens": 400,
            "session_cached_tokens": 100,
            "steps": 5,
            "tool_calls_succeeded": 4,
            "tool_calls_failed": 1,
        },
    }


def _write_meta(home, session_id, **fields):
    directory = os.path.join(home, ".vibe", "logs", "session", session_id)
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, "meta.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(_meta(session_id, **fields), fh)
    return path


class VibeStatsCacheTest(_support.IsolatedHomeTest):
    def setUp(self):
        super().setUp()
        self.cache = os.path.join(self.home, "cache")
        self.env = {"XDG_CACHE_HOME": self.cache}

    def _cache_files(self):
        directory = os.path.join(self.cache, "kde-ai-usage")
        if not os.path.isdir(directory):
            return []
        return [name for name in os.listdir(directory) if name.startswith("vibe-stats-")]

    def _cache_payload(self):
        directory = os.path.join(self.cache, "kde-ai-usage")
        name = self._cache_files()[0]
        with open(os.path.join(directory, name), encoding="utf-8") as fh:
            return json.load(fh)

    def test_warm_cache_skips_json_parse(self):
        _write_meta(self.home, "sess-a")
        _write_meta(self.home, "sess-b", cost=1.2, tokens=2000)
        with mock.patch.dict(os.environ, self.env):
            cold = mistral._vibe_stats()
            self.assertEqual(cold["vibeSessionCount"], 2)
            self.assertEqual(cold["vibeTotalCost"], 1.6)
            calls = []

            def counting_parse(text):
                calls.append(text)
                return mistral.as_json(text)

            with mock.patch("aiusage.providers.mistral.as_json", side_effect=counting_parse):
                warm = mistral._vibe_stats()
        self.assertEqual(calls, [])
        self.assertEqual(warm, cold)

    def test_malformed_meta_is_skipped(self):
        _write_meta(self.home, "sess-a")
        directory = os.path.join(self.home, ".vibe", "logs", "session", "sess-b")
        os.makedirs(directory)
        with open(os.path.join(directory, "meta.json"), "w", encoding="utf-8") as fh:
            fh.write("{not json")
        with mock.patch.dict(os.environ, self.env):
            stats = mistral._vibe_stats()
        self.assertEqual(stats["vibeSessionCount"], 1)
        self.assertEqual(stats["vibeTotalCost"], 0.4)

    def test_missing_logs_return_empty_without_cache(self):
        with mock.patch.dict(os.environ, self.env):
            self.assertEqual(mistral._vibe_stats(), {})
        self.assertEqual(self._cache_files(), [])

    def test_changed_log_invalidates_cache(self):
        path = _write_meta(self.home, "sess-a", cost=0.4)
        with mock.patch.dict(os.environ, self.env):
            self.assertEqual(mistral._vibe_stats()["vibeTotalCost"], 0.4)
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(_meta("sess-a", cost=9.9), fh)
            future = time.time_ns() + 5_000_000_000
            os.utime(path, ns=(future, future))
            self.assertEqual(mistral._vibe_stats()["vibeTotalCost"], 9.9)

    def test_deleted_log_invalidates_cache(self):
        _write_meta(self.home, "sess-a")
        path = _write_meta(self.home, "sess-b")
        with mock.patch.dict(os.environ, self.env):
            self.assertEqual(mistral._vibe_stats()["vibeSessionCount"], 2)
            os.unlink(path)
            self.assertEqual(mistral._vibe_stats()["vibeSessionCount"], 1)

    def test_empty_logs_dir_stays_cached(self):
        os.makedirs(os.path.join(self.home, ".vibe", "logs", "session"))
        with mock.patch.dict(os.environ, self.env):
            self.assertEqual(mistral._vibe_stats(), {})
            cache_path = os.path.join(self.cache, "kde-ai-usage", self._cache_files()[0])
            before = os.stat(cache_path).st_mtime_ns
            self.assertEqual(mistral._vibe_stats(), {})
            after = os.stat(cache_path).st_mtime_ns
        self.assertEqual(before, after)

    def test_corrupt_cache_recovers(self):
        _write_meta(self.home, "sess-a")
        with mock.patch.dict(os.environ, self.env):
            expected = mistral._vibe_stats()
            cache_path = os.path.join(self.cache, "kde-ai-usage", self._cache_files()[0])
            with open(cache_path, "w", encoding="utf-8") as fh:
                fh.write("{not json")
            self.assertEqual(mistral._vibe_stats(), expected)

    def test_different_home_uses_separate_cache(self):
        home_a = os.path.join(self.home, "a")
        home_b = os.path.join(self.home, "b")
        _write_meta(home_a, "sess-a")
        _write_meta(home_b, "sess-b")
        with mock.patch.dict(os.environ, {"HOME": home_a, "XDG_CACHE_HOME": self.cache}):
            stats_a = mistral._vibe_stats()
        with mock.patch.dict(os.environ, {"HOME": home_b, "XDG_CACHE_HOME": self.cache}):
            stats_b = mistral._vibe_stats()
        self.assertEqual(stats_a["vibeSessionCount"], 1)
        self.assertEqual(stats_b["vibeSessionCount"], 1)
        self.assertEqual(len(self._cache_files()), 2)

    def test_cache_payload_has_no_key_or_raw_log_content(self):
        path = _write_meta(self.home, "sess-a")
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        data["origin_directory"] = "/secret/raw/log/marker"
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        with mock.patch.dict(os.environ, {**self.env, "MISTRAL_API_KEY": "sk-secret-value"}):
            with mock.patch("aiusage.providers.mistral.fetch_json", return_value=HttpResult(200, '{"data":[]}')):
                get_mistral_usage()
        raw = json.dumps(self._cache_payload())
        self.assertNotIn("sess-a", raw)
        self.assertNotIn("/secret/raw/log/marker", raw)
        self.assertNotIn(str(self.home), raw)
        self.assertNotIn("sk-secret-value", raw)

    def test_invalid_key_is_not_cached_as_healthy(self):
        _write_meta(self.home, "sess-a")
        with mock.patch.dict(os.environ, {**self.env, "MISTRAL_API_KEY": "sk-secret-value"}):
            with mock.patch("aiusage.providers.mistral.fetch_json", return_value=HttpResult(401, "")):
                result = get_mistral_usage()
        self.assertFalse(result["keyValid"])
        self.assertEqual(result["error"], "Invalid API key (401)")
        self.assertEqual(result["vibeSessionCount"], 1)
        raw = json.dumps(self._cache_payload())
        self.assertNotIn("keyValid", raw)
        self.assertNotIn("availableModels", raw)
        self.assertNotIn("Invalid API key", raw)

    def test_valid_key_response_is_not_cached(self):
        _write_meta(self.home, "sess-a")
        body = json.dumps({"data": [{"id": "codestral"}, {"id": "mistral-large"}]})
        with mock.patch.dict(os.environ, {**self.env, "MISTRAL_API_KEY": "sk-secret-value"}):
            with mock.patch("aiusage.providers.mistral.fetch_json", return_value=HttpResult(200, body)):
                result = get_mistral_usage()
        self.assertTrue(result["keyValid"])
        self.assertEqual(result["availableModels"], ["codestral", "mistral-large"])
        raw = json.dumps(self._cache_payload())
        self.assertNotIn("codestral", raw)
        self.assertNotIn("keyValid", raw)


if __name__ == "__main__":
    unittest.main()
