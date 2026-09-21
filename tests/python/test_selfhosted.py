import os
from unittest.mock import patch

from aiusage.http import HttpResult
from aiusage.normalize.selfhosted import normalize_selfhosted
from aiusage.providers.selfhosted import get_selfhosted_usage


def test_ollama_custom_endpoint_and_gpu():
    responses = {
        "http://127.0.0.1:1234/api/version": HttpResult(200, '{"version":"0.5"}'),
        "http://127.0.0.1:1234/api/ps": HttpResult(200, '{"models":[{"name":"qwen","size_vram":1073741824,"expires_at":"2026-09-18T11:25:00Z"}]}'),
    }
    env = {"WIDGET_SELFHOSTED_ENDPOINT": "http://127.0.0.1:1234", "WIDGET_SELFHOSTED_ENGINE": "ollama"}
    with (
        patch.dict(os.environ, env),
        patch("aiusage.providers.selfhosted._request", side_effect=lambda base, path, _: responses[base + path]),
        patch("aiusage.providers.selfhosted._local_gpu", return_value={"name": "GPU", "usedMiB": 4, "totalMiB": 8}),
    ):
        body = get_selfhosted_usage()
    row = normalize_selfhosted({"now": 1, "inputs": {"usage": body}})
    assert row["summary"]["pct"] == 50
    assert row["summary"]["resetsAt"] > 0
    assert row["details"]["models"][0]["name"] == "qwen"


def test_vllm_metrics_and_llama_slots():
    vllm = normalize_selfhosted(
        {
            "now": 1,
            "inputs": {
                "usage": {
                    "engine": "vllm",
                    "models": [{"id": "m"}],
                    "metrics": "vllm:gpu_cache_usage_factor 0.75\nvllm:num_requests_running 2\nvllm:prompt_tokens_total 100\nvllm:generation_tokens_total 40",  # noqa: E501
                }
            },
        }
    )
    assert vllm["summary"]["pct"] == 75
    assert vllm["details"]["generationTokens"] == 40
    llama = normalize_selfhosted(
        {"now": 1, "inputs": {"usage": {"engine": "llama.cpp", "slots": [{"id": 0, "is_processing": True}, {"id": 1, "is_processing": False}]}}}
    )
    assert llama["summary"]["pct"] == 50
    assert llama["details"]["runtimeSlots"][0]["state"] == "generating"


def test_multiple_servers_keep_metrics_separate_and_offline_visible():
    responses = {
        "http://127.0.0.1:1234/api/version": HttpResult(200, '{"version":"0.5"}'),
        "http://127.0.0.1:1234/api/ps": HttpResult(200, '{"models":[{"name":"qwen","size_vram":1073741824}]}'),
    }
    env = {"WIDGET_SELFHOSTED_ENDPOINT": "http://127.0.0.1:1234, http://127.0.0.1:9999", "WIDGET_SELFHOSTED_ENGINE": "ollama"}
    with (
        patch.dict(os.environ, env),
        patch("aiusage.providers.selfhosted._request", side_effect=lambda base, path, _: responses.get(base + path, HttpResult(0, ""))),
        patch("aiusage.providers.selfhosted._local_gpu", return_value={}),
    ):
        body = get_selfhosted_usage()
    row = normalize_selfhosted({"now": 1, "inputs": {"usage": body}})
    assert row["ok"] is True
    assert row["details"]["online"] == 1
    assert row["details"]["total"] == 2
    assert row["details"]["servers"][1]["error"]
    assert row["details"]["servers"][0]["models"][0]["name"] == "qwen"


def test_multi_server_summary_uses_highest_saturation():
    row = normalize_selfhosted(
        {
            "now": 1,
            "inputs": {
                "usage": {
                    "instances": [
                        {"url": "http://one", "engine": "vllm", "models": [], "metrics": "vllm:gpu_cache_usage_factor 0.25"},
                        {"url": "http://two", "engine": "vllm", "models": [], "metrics": "vllm:gpu_cache_usage_factor 0.8"},
                    ]
                }
            },
        }
    )
    assert row["summary"]["pct"] == 80
    assert len(row["details"]["servers"]) == 2
    assert row["quotaWindows"][0]["label"].startswith("http://one")


def test_endpoint_of_only_separators_reports_instead_of_crashing():
    """A setting like ", " strips to nothing: probing zero URLs used to raise
    ValueError out of ThreadPoolExecutor(max_workers=0)."""
    with patch.dict(os.environ, {"WIDGET_SELFHOSTED_ENDPOINT": " , "}):
        assert get_selfhosted_usage() == {"error": "No local server URL configured"}
