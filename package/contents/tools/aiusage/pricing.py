"""Cached standard token rates from LiteLLM's public JSON catalog.

Only data is downloaded; LiteLLM is not a runtime dependency. Collection owns
this IO so normalization and recorded fixtures remain completely offline.
"""

import json
import math
import os
import tempfile
import time

from . import config
from .http import as_json, fetch_json

SOURCE_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
REFRESH_SECONDS = 86400
RETRY_SECONDS = 900
PROVIDERS = ("anthropic", "openai")


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


def _valid_tables(tables):
    if not isinstance(tables, dict) or set(tables) != set(PROVIDERS):
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


def load_catalog(*, force=False):
    """Refresh daily, retry failures after 15 minutes, retain last good rates.

    The returned error describes a failed refresh even when cached rates exist.
    """
    path = os.path.join(config.cache_dir(), "pricing-litellm-v1.json")
    cached = _read_cache(path)
    now = time.time()
    ttl = RETRY_SECONDS if cached.get("error") else REFRESH_SECONDS
    age = now - cached.get("checkedAt", 0)
    if cached and not force and 0 <= age < ttl:
        return cached
    snapshot = {
        "version": 1,
        "source": SOURCE_URL,
        "fetchedAt": cached.get("fetchedAt", 0),
        "checkedAt": now,
        "providers": cached.get("providers", {}),
        "error": "",
    }
    try:
        response = fetch_json(SOURCE_URL, timeout=10)
        if response.status != 200:
            raise ValueError(f"pricing download failed (HTTP {response.status})")
        data = as_json(response.body)
        snapshot["providers"] = parse_catalog(data)
        snapshot["fetchedAt"] = now
    except (OSError, ValueError) as e:
        snapshot["error"] = str(e)
    _write_cache(path, snapshot)
    return snapshot


def get_pricing(provider):
    return load_catalog()["providers"].get(provider, {})
