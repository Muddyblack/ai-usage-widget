"""Identity-scoped persistence for validated Codex rate-limit snapshots."""

import hashlib
import hmac
import json
import math
import os
import tempfile
import time

from .. import config

TTL_SECONDS = 120
_FIELDS = ("rateLimits", "rate_limit", "rateLimitsByLimitId", "additional_rate_limits", "_codexNoLimits")


def identity_key(token: str, home: str) -> str:
    """Return an opaque key for the access token and normalized Codex home."""
    normalized_home = os.path.normcase(os.path.realpath(os.path.abspath(os.path.expanduser(home))))
    return hashlib.sha256((token + "\0" + normalized_home).encode("utf-8")).hexdigest()


def snapshot(raw: dict, token: str, home: str, now: float | None = None) -> tuple[dict, str, int | None]:
    """Write meaningful validated live data or return a bounded stale snapshot."""
    checked_at = time.time() if now is None else now
    key = identity_key(token, home)
    path = os.path.join(config.cache_dir(), f"codex-last-good-{key}.json")
    safe = {field: raw[field] for field in _FIELDS if field in raw}
    fresh = _has_limits(safe)
    if fresh:
        payload = {"version": 1, "identity": key, "savedAt": checked_at, "data": safe}
        _atomic_write(path, payload)
        return safe, "live", 0

    cached = _read(path, key)
    if cached is None:
        return {}, "unavailable", None
    age = checked_at - cached["savedAt"]
    if age < 0 or age > TTL_SECONDS:
        return {}, "unavailable", None
    return cached["data"], "stale", int(age)


def _has_limits(data: dict) -> bool:
    """Recognize a well-formed limit payload, including an explicit empty result."""
    if data.get("_codexNoLimits") is True:
        return True
    if "rateLimits" in data:
        return isinstance(data["rateLimits"], dict)
    if "rate_limit" in data:
        return isinstance(data["rate_limit"], dict)
    if "rateLimitsByLimitId" in data:
        return isinstance(data["rateLimitsByLimitId"], dict)
    if "additional_rate_limits" in data:
        return isinstance(data["additional_rate_limits"], list)
    return False


def _read(path: str, key: str) -> dict | None:
    try:
        with open(path, encoding="utf-8") as stream:
            payload = json.load(stream)
    except (OSError, ValueError):
        return None
    if not isinstance(payload, dict) or payload.get("version") != 1:
        return None
    stored_identity = payload.get("identity")
    if not isinstance(stored_identity, str) or not hmac.compare_digest(stored_identity, key):
        return None
    saved_at = payload.get("savedAt")
    data = payload.get("data")
    if isinstance(saved_at, bool) or not isinstance(saved_at, (int, float)) or not math.isfinite(saved_at):
        return None
    if not isinstance(data, dict) or not _has_limits(data):
        return None
    return {"savedAt": float(saved_at), "data": {field: data[field] for field in _FIELDS if field in data}}


def _atomic_write(path: str, payload: dict) -> None:
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=".codex-last-good-", dir=directory)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(payload, stream, separators=(",", ":"))
            os.replace(temporary, path)
        except OSError:
            try:
                os.unlink(temporary)
            except OSError:
                pass
            raise
    except OSError:
        return
