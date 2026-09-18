"""Cached standard token rates from LiteLLM's public JSON catalog.

Only data is downloaded; LiteLLM is not a runtime dependency. Collection owns
this IO so normalization and recorded fixtures remain completely offline.
"""

import json
import math
import os
import tempfile
import threading
import time

from . import config
from .http import as_json, fetch_json
from .pricing_lock import acquire as _acquire_lock
from .pricing_lock import release as _release_lock

SOURCE_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
OPENROUTER_SOURCE_URL = "https://openrouter.ai/api/v1/models"
REFRESH_SECONDS = 604800
RETRY_SECONDS = 900
PROVIDERS = ("anthropic", "openai")
_PROCESS_LOCK = threading.RLock()
_CURRENT_SNAPSHOTS = {}
_REFRESH_GENERATIONS = {}


def valid_rate(value):
    return type(value) in (int, float) and 0 <= value <= 1_000_000 and math.isfinite(value)


def parse_catalog(data):
    """Select direct-provider text rates and convert USD/token to USD/million.

    Exact model IDs only: reseller, regional, batch and fine-tuned prices must
    never become the default rate for another model by trimming their names.
    Unknown/incomplete rows remain unpriced.
    """
    if not isinstance(data, dict):
        raise ValueError("pricing catalog must be a JSON object")
    tables = {provider: {} for provider in PROVIDERS}
    for model, row in data.items():
        if not isinstance(model, str) or not model or "/" in model or not isinstance(row, dict):
            continue
        provider = row.get("litellm_provider")
        if not isinstance(provider, str) or provider not in tables or row.get("mode") not in ("chat", "completion", "responses", "embedding"):
            continue
        rates = {key: row.get(key + "_cost_per_token") for key in ("input", "output")}
        if not all(valid_rate(value) and value <= 1 for value in rates.values()):
            continue
        price = {key: value * 1_000_000 for key, value in rates.items()}
        cached = row.get("cache_read_input_token_cost")
        if cached is not None:
            if not valid_rate(cached) or cached > 1:
                continue
            price["cached"] = cached * 1_000_000
        tables[provider][model] = price
    if not all(tables.values()):
        raise ValueError("pricing catalog has no usable rates for one or both providers")
    return tables


def parse_openrouter_catalog(data):
    if not isinstance(data, dict) or not isinstance(data.get("data"), list):
        raise ValueError("OpenRouter pricing catalog must contain a data list")
    tables = {provider: {} for provider in PROVIDERS}
    for row in data["data"]:
        if not isinstance(row, dict):
            continue
        model_id = row.get("id")
        pricing = row.get("pricing")
        if not isinstance(model_id, str) or not model_id or not isinstance(pricing, dict):
            continue
        provider, separator, _ = model_id.partition("/")
        if not separator or provider not in tables:
            continue
        prompt = pricing.get("prompt")
        completion = pricing.get("completion")
        try:
            prompt = float(prompt)
            completion = float(completion)
        except (TypeError, ValueError):
            continue
        if any(type(value) is bool for value in (pricing.get("prompt"), pricing.get("completion"))):
            continue
        if not valid_rate(prompt) or not valid_rate(completion) or prompt > 1 or completion > 1:
            continue
        price = {"input": prompt * 1_000_000, "output": completion * 1_000_000}
        cached = pricing.get("input_cache_read")
        if cached is not None:
            if type(cached) is bool:
                continue
            try:
                cached = float(cached)
            except (TypeError, ValueError):
                continue
            if not valid_rate(cached) or cached > 1:
                continue
            price["cached"] = cached * 1_000_000
        tables[provider][model_id] = price
    return tables


def _requested_models(models):
    if not isinstance(models, dict):
        return []
    return [
        (provider, model)
        for provider in PROVIDERS
        for model in ((models.get(provider),) if isinstance(models.get(provider), str) else (models.get(provider) or ()))
        if isinstance(model, str) and model
    ]


def _merge_openrouter_missing(tables, fallback, models):
    missing = []
    for provider, model in _requested_models(models):
        if model in tables.get(provider, {}):
            continue
        candidates = (model, f"{provider}/{model}")
        row = next((fallback.get(provider, {}).get(candidate) for candidate in candidates if candidate in fallback.get(provider, {})), None)
        if row is None:
            missing.append((provider, model))
            continue
        tables.setdefault(provider, {})[model] = row
    return missing


def _valid_tables(tables):
    if not isinstance(tables, dict) or not tables or not set(tables) <= set(PROVIDERS):
        return False
    for table in tables.values():
        if not isinstance(table, dict) or not table:
            return False
        for model, price in table.items():
            if not isinstance(model, str) or not isinstance(price, dict) or not {"input", "output"} <= price.keys():
                return False
            if not all(valid_rate(value) for value in price.values()):
                return False
    return True


def _read_cache(path):
    try:
        with open(path, encoding="utf-8") as f:
            cached = json.load(f)
        if not isinstance(cached, dict) or cached.get("source") != SOURCE_URL or cached.get("version") != 1:
            return {}
        if not all(type(cached.get(key)) in (int, float) and 0 <= cached[key] <= 1e12 for key in ("fetchedAt", "checkedAt")):
            return {}
        if not _valid_tables(cached.get("providers")) and cached.get("providers") != {}:
            return {}
        return cached
    except (OSError, ValueError):
        return {}


def _write_cache(path, snapshot):
    temporary = None
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=os.path.dirname(path), delete=False) as f:
            temporary = f.name
            json.dump(snapshot, f, allow_nan=False, separators=(",", ":"))
        os.replace(temporary, path)
    except OSError:
        # Read-only caches must not prevent pricing this refresh.
        pass
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def _snapshot(path):
    disk = _read_cache(path)
    memory = _CURRENT_SNAPSHOTS.get(path, {})
    return memory if memory.get("checkedAt", 0) >= disk.get("checkedAt", 0) else disk


def _fetch_openrouter():
    response = fetch_json(OPENROUTER_SOURCE_URL, timeout=10)
    if response.status != 200:
        raise ValueError(f"OpenRouter pricing download failed (HTTP {response.status})")
    data = as_json(response.body)
    return parse_openrouter_catalog(data)


def load_catalog(*, force=False, models=None):
    """Refresh weekly, retry failures after 15 minutes, and retain last-good rates."""
    path = os.path.join(config.cache_dir(), "pricing-litellm-v1.json")
    generation = _REFRESH_GENERATIONS.get(path, 0)
    with _PROCESS_LOCK:
        cached = _snapshot(path)
        initial = cached
        now = time.time()
        ttl = RETRY_SECONDS if cached.get("error") else REFRESH_SECONDS
        age = now - cached.get("checkedAt", 0)
        handle = _acquire_lock(path)
        if handle is None:
            return _snapshot(path)
        try:
            cached = _snapshot(path)
            if force and (_REFRESH_GENERATIONS.get(path, 0) != generation or cached.get("checkedAt") != initial.get("checkedAt")):
                return cached
            now = time.time()
            ttl = RETRY_SECONDS if cached.get("error") else REFRESH_SECONDS
            age = now - cached.get("checkedAt", 0)
            fresh = bool(cached) and not force and 0 <= age < ttl
            if fresh:
                missing = _merge_openrouter_missing(cached["providers"], {}, models)
                if not missing or cached.get("error"):
                    return cached
            snapshot = {
                "version": 1,
                "source": SOURCE_URL,
                "fetchedAt": cached.get("fetchedAt", 0),
                "checkedAt": now,
                "providers": cached.get("providers", {}),
                "error": "",
            }
            primary_error = ""
            if not fresh:
                try:
                    response = fetch_json(SOURCE_URL, timeout=10)
                    if response.status != 200:
                        raise ValueError(f"pricing download failed (HTTP {response.status})")
                    data = as_json(response.body)
                    snapshot["providers"] = parse_catalog(data)
                except (OSError, ValueError) as error:
                    primary_error = str(error)

            if not primary_error:
                missing = _merge_openrouter_missing(snapshot["providers"], {}, models)
                if missing:
                    try:
                        missing = _merge_openrouter_missing(snapshot["providers"], _fetch_openrouter(), models)
                    except (OSError, ValueError):
                        snapshot["error"] = "OpenRouter pricing fallback unavailable"
                snapshot["error"] = "OpenRouter pricing fallback unavailable" if missing else snapshot["error"]
            elif _requested_models(models):
                try:
                    fallback = _fetch_openrouter()
                    missing = _merge_openrouter_missing(snapshot["providers"], fallback, models)
                    if missing:
                        snapshot["error"] = primary_error + "; OpenRouter pricing fallback unavailable"
                except (OSError, ValueError) as fallback_error:
                    snapshot["error"] = primary_error + "; " + str(fallback_error)
            else:
                snapshot["error"] = primary_error
            if not snapshot["error"]:
                snapshot["fetchedAt"] = now
            _CURRENT_SNAPSHOTS[path] = snapshot
            _REFRESH_GENERATIONS[path] = _REFRESH_GENERATIONS.get(path, 0) + 1
            _write_cache(path, snapshot)
            return snapshot
        finally:
            _release_lock(path, handle)


def cached_catalog():
    path = os.path.join(config.cache_dir(), "pricing-litellm-v1.json")
    return _snapshot(path).get("providers", {})


def get_pricing(provider, models=None):
    requested = {provider: models} if models is not None else None
    return load_catalog(models=requested)["providers"].get(provider, {})
