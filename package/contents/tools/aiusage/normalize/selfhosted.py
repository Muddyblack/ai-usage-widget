"""Normalize local server capacity and token counters."""

import math
import re

from ..contract import chart_window, compact_tokens, epoch_of, flat_window, pct_clamp, provider_base, provider_error

ACCENT = "#38bdf8"
METRIC = re.compile(r"^([a-zA-Z_:][\w:]*)(?:\{[^}]*\})?\s+([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)$")


def _metrics(text):
    values = {}
    for line in text.splitlines():
        match = METRIC.match(line.strip())
        if match:
            value = float(match[2])
            if math.isfinite(value):
                values[match[1]] = values.get(match[1], 0) + value
    return values


def normalize_selfhosted(raw):
    now = raw["now"]
    body = raw["inputs"].get("usage") or {}
    if isinstance(body.get("instances"), list):
        instances = body["instances"]
        rows = [normalize_selfhosted({"now": now, "inputs": {"usage": instance}}) for instance in instances]
        healthy = [row for row in rows if row["ok"]]
        if not healthy:
            return provider_error(
                "selfhosted",
                "Local Models",
                ACCENT,
                now,
                "All local model servers offline",
                {"servers": [{"url": instance.get("url", ""), "error": row["error"]} for instance, row in zip(instances, rows)]},
            )
        r = provider_base("selfhosted", "Local Models", ACCENT, now)
        r["summary"] = dict(max(healthy, key=lambda row: row["summary"]["pct"])["summary"])
        r["summary"]["detail"] = f"{len(healthy)} of {len(rows)} servers online"
        r["summary"]["status"] = "active" if any(row["summary"].get("status") == "active" for row in healthy) else "ready"
        servers = []
        for index, (instance, row) in enumerate(zip(instances, rows)):
            server = {
                "url": instance.get("url", ""),
                "ok": row["ok"],
                "error": row["error"],
                "summary": row["summary"],
                "quotaWindows": row["quotaWindows"],
                **row["details"],
            }
            servers.append(server)
            for window in row["quotaWindows"]:
                r["quotaWindows"].append(
                    {**window, "key": f"server_{index}_{window['key']}", "label": f"{instance.get('url', 'Server')} · {window['label']}"}
                )
        r["slots"] = [
            {"pct": row["summary"]["pct"], "color": ACCENT, "text": None, "tooltip": f"{instance.get('url', 'Server')}: {row['summary']['text']}"}
            for instance, row in zip(instances, rows)
            if row["ok"]
        ]
        r["details"] = {"servers": servers, "online": len(healthy), "total": len(rows)}
        return r
    if body.get("error"):
        return provider_error("selfhosted", "Local Models", ACCENT, now, body["error"], {})
    engine = body.get("engine")
    if not engine:
        return provider_error("selfhosted", "Local Models", ACCENT, now, "No local model server", {})
    r = provider_base("selfhosted", "Local Models", ACCENT, now)
    windows, models, slots = [], [], []
    metrics = _metrics(body.get("metrics") or "")
    pct = None
    reset = 0
    running = 0
    gpu = body.get("gpu") or {}
    if gpu.get("totalMiB", 0) > 0:
        vram_pct = pct_clamp(gpu["usedMiB"] / gpu["totalMiB"] * 100)
        pct = vram_pct
        windows.append(flat_window("local_vram", "GPU VRAM", vram_pct, 0, f"{gpu['usedMiB'] / 1024:.1f} / {gpu['totalMiB'] / 1024:.1f} GB", True))
    if engine == "ollama":
        for model in body.get("models") or []:
            if not isinstance(model, dict):
                continue
            size = max(0, model.get("size_vram") or 0)
            models.append(
                {
                    "name": model.get("name") or "Model",
                    "sizeVram": size,
                    "quant": (model.get("details") or {}).get("quantization_level") or "",
                    "expiresAt": model.get("expires_at") or "",
                }
            )
            reset = max(reset, epoch_of(model.get("expires_at")))
        running = len(models)
        if gpu and reset and windows:
            windows[0]["resetAt"] = reset
        if models and not gpu:
            windows.append(
                flat_window("local_vram", "Model VRAM", 0, reset, f"{sum(m['sizeVram'] for m in models) / 1073741824:.1f} GB loaded", False)
            )
    elif engine == "vllm":
        models = [{"name": m.get("id", "Model")} for m in body.get("models") or [] if isinstance(m, dict)]
        fraction = metrics.get("vllm:gpu_cache_usage_factor")
        if fraction is not None:
            pct = pct_clamp(fraction * 100)
            windows.append(flat_window("local_kv", "KV cache", pct, 0, f"{pct:.1f}% used", True))
        running = int(metrics.get("vllm:num_requests_running", 0))
        waiting = int(metrics.get("vllm:num_requests_waiting", 0))
        windows.append(flat_window("local_requests", "Requests", 0, 0, f"{running} running · {waiting} waiting", False))
    else:
        for slot in body.get("slots") or []:
            if not isinstance(slot, dict):
                continue
            active = slot.get("is_processing") is True or slot.get("state") in (1, "processing")
            running += int(active)
            slots.append(
                {"id": slot.get("id"), "state": "generating" if active else "idle", "used": slot.get("n_past") or 0, "limit": slot.get("n_ctx") or 0}
            )
        if slots:
            pct = pct_clamp(running / len(slots) * 100)
            windows.append(flat_window("local_slots", "Active slots", pct, 0, f"{running} of {len(slots)} generating", True))
    prompt = metrics.get("vllm:prompt_tokens_total", metrics.get("llamacpp:prompt_tokens_total", 0))
    output = metrics.get("vllm:generation_tokens_total", metrics.get("llamacpp:predicted_tokens_total", 0))
    total = int(prompt + output)
    if total:
        windows.append(flat_window("local_tokens", "Server tokens", 0, 0, f"{compact_tokens(total)} tokens since server start", False))
        r["chartWindows"] = [
            chart_window("local_tokens_24h", "local_tokens", "24H", 86400000, "24h"),
            chart_window("local_tokens_7d", "local_tokens", "7D", 604800000, "7d"),
        ]
        r["historyValues"] = {"local_tokens": total}
    speed = metrics.get("vllm:avg_generation_throughput_tok_per_s")
    state = "active" if running else ("ready" if models else "idle")
    r["summary"] = {
        "pct": pct or 0,
        "text": f"{pct:.0f}%" if pct is not None else (f"{speed:.0f} t/s" if speed is not None else state),
        "detail": "KV cache" if engine == "vllm" else ("Active slots" if engine == "llama.cpp" else "Loaded models"),
        "hasChart": pct is not None,
        "resetsAt": reset,
        "status": state,
    }
    r["quotaWindows"] = windows
    r["slots"] = [{"pct": pct or 0, "color": ACCENT, "text": None, "tooltip": f"{engine}: {state}"}]
    r["details"] = {
        "url": body.get("url") or "",
        "engine": engine,
        "version": body.get("version") or "",
        "gpu": gpu,
        "models": models,
        "generationTokens": int(output),
        "promptTokens": int(prompt),
        "tokensPerSec": speed,
        "runtimeSlots": slots,
        "state": state,
    }
    return r
