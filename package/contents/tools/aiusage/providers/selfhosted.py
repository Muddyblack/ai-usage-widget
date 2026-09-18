"""Read local inference servers without issuing an inference request."""

import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit

from .. import config
from ..http import as_json, fetch_json

DEFAULTS = {"ollama": "http://127.0.0.1:11434", "vllm": "http://127.0.0.1:8000", "llama.cpp": "http://127.0.0.1:8080"}


def _request(base, path, headers):
    return fetch_json(base + path, headers=headers, timeout=1)


def _local_gpu():
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=0.3,
            check=False,
        )
        if result.returncode:
            return {}
        first = result.stdout.splitlines()[0].split(",")
        if len(first) != 5:
            return {}
        return {
            "name": first[0].strip(),
            "usedMiB": float(first[1]),
            "totalMiB": float(first[2]),
            "utilization": float(first[3]),
            "temperature": float(first[4]),
        }
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return {}


def _probe(base, engine, headers):
    for name in DEFAULTS if engine == "auto" else (engine,):
        parsed = urlsplit(base)
        if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            return {"url": base, "error": "Invalid local server URL"}
        probe = {"ollama": "/api/version", "vllm": "/v1/models", "llama.cpp": "/slots"}[name]
        result = _request(base, probe, headers)
        if result.status != 200:
            continue
        body = as_json(result.body)
        gpu = _local_gpu() if parsed.hostname in ("localhost", "127.0.0.1", "::1") else {}
        if name == "ollama" and isinstance(body, dict) and "version" in body:
            ps = _request(base, "/api/ps", headers)
            ps_body = as_json(ps.body) if ps.status == 200 else None
            return {
                "url": base,
                "engine": name,
                "version": body.get("version"),
                "gpu": gpu,
                "models": ps_body.get("models", []) if isinstance(ps_body, dict) else [],
            }
        if name == "vllm" and isinstance(body, dict) and isinstance(body.get("data"), list):
            metrics = _request(base, "/metrics", headers)
            return {"url": base, "engine": name, "gpu": gpu, "models": body["data"], "metrics": metrics.body if metrics.status == 200 else ""}
        if name == "llama.cpp" and isinstance(body, list):
            metrics = _request(base, "/metrics", headers)
            return {"url": base, "engine": name, "gpu": gpu, "slots": body, "metrics": metrics.body if metrics.status == 200 else ""}
    return {"url": base, "error": "Offline or unsupported"}


def get_selfhosted_usage():
    cfg = config.load_settings()
    endpoints = os.environ.get("WIDGET_SELFHOSTED_ENDPOINT") or cfg.get("selfhostedEndpoint") or ""
    engine = (os.environ.get("WIDGET_SELFHOSTED_ENGINE") or cfg.get("selfhostedEngine") or "auto").lower()
    if engine not in ("auto", *DEFAULTS):
        return {"error": "Unknown local engine"}
    key = os.environ.get("WIDGET_SELFHOSTED_KEY") or (cfg.get("keys") or {}).get("selfhosted", "")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in key):
        return {"error": "Invalid local server key"}
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    urls = (
        list(dict.fromkeys(url.rstrip("/") for url in re.split(r"[,\s]+", endpoints.strip()) if url))
        if endpoints.strip()
        else list(DEFAULTS.values())
    )
    if len(urls) > 8:
        return {"error": "At most eight local server URLs are supported"}
    jobs = [(url, engine) for url in urls] if endpoints.strip() else list(zip(DEFAULTS.values(), DEFAULTS.keys()))
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        instances = list(pool.map(lambda job: _probe(job[0], job[1], headers), jobs))
    if not endpoints.strip():
        instances = [instance for instance in instances if not instance.get("error")]
    if not instances:
        return {"error": "Local model servers offline or unsupported"}
    if len(instances) == 1:
        return instances[0]
    return {"instances": instances}
