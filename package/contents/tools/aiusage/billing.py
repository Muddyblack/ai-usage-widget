"""Organization billing aggregation using rates supplied by collectors."""

import math

from .contract import num


def price_models(entries, pricing):
    """Group token entries by model and price them against `pricing`
    ({model: {input, output, optional cached}}, USD per million tokens).

    A model missing from `pricing` still shows up, just unpriced. A pricing row
    carrying `cached` bills `cached_tokens` at that lower rate and the rest of
    the prompt at the input rate. An entry without `cached_tokens` bills its
    entire prompt at the input rate, even if the catalog has a cache rate."""
    models = {}
    total_in = 0
    total_out = 0
    for entry in entries:
        name = entry.get("model") or "unknown"
        in_ = math.floor(num(entry.get("input_tokens")))
        out_ = math.floor(num(entry.get("output_tokens")))
        cached = math.floor(num(entry.get("cached_tokens")))
        price = pricing.get(name)
        m = models.setdefault(name, {"input_tokens": 0, "output_tokens": 0, "cost_usd": 0.0, "priced": False})
        m["input_tokens"] += in_
        m["output_tokens"] += out_
        if price is not None:
            # Cached tokens are a discounted subset of the prompt; clamp so a
            # provider that reports them *alongside* input rather than inside
            # it can never produce a negative full-rate remainder.
            billable_cached = min(cached, in_) if price.get("cached") is not None else 0
            m["cost_usd"] += ((in_ - billable_cached) / 1000000) * num(price["input"]) + (out_ / 1000000) * num(price["output"])
            if billable_cached:
                m["cost_usd"] += (billable_cached / 1000000) * num(price["cached"])
            m["priced"] = True
        total_in += in_
        total_out += out_
    total_cost = sum(m["cost_usd"] for m in models.values())
    return {
        "models": models,
        "totalInputTokens": total_in,
        "totalOutputTokens": total_out,
        "totalCostUSD": total_cost,
    }


def empty_org_usage():
    return {"models": {}, "totalInputTokens": 0, "totalOutputTokens": 0, "totalCostUSD": 0}
