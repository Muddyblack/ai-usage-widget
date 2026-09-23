"""Shared local-CLI statistics normalization (Claude Code and Codex CLI agree
on the shape)."""

import datetime

from .contract import epoch_of, num


def day_epoch(date):
    if isinstance(date, str) and date != "":
        return epoch_of(date[0:10] + "T00:00:00Z")
    return 0


def activity_streaks(dates, now):
    d = sorted({x for x in dates if x != ""})
    run = 0
    longest = 0
    prev = None
    for day in d:
        cur = day_epoch(day)
        if prev is not None and round((cur - prev) / 86400) == 1:
            run = run + 1
        else:
            run = 1
        longest = max(longest, run)
        prev = cur
    today = day_epoch(datetime.datetime.fromtimestamp(now).strftime("%Y-%m-%d"))
    if len(d) == 0:
        current = 0
    elif round((today - day_epoch(d[-1])) / 86400) <= 1:
        current = run
    else:
        current = 0
    return {"longest": longest, "current": current}


def span_days_since(first, now):
    start = day_epoch(first)
    if start == 0:
        return 0
    return max(1, round((now - start) / 86400) + 1)


def peak_hour(counts):
    """JS iterates integer-like object keys in ascending numeric order and
    keeps the first strictly-greatest bucket; mirror that so the peak hour
    never drifts between the two frontends."""
    if not isinstance(counts, dict):
        return -1
    entries = []
    for k, v in counts.items():
        try:
            h = int(k)
        except (ValueError, TypeError):
            h = -1
        if h >= 0:
            entries.append((h, num(v)))
    entries.sort(key=lambda e: e[0])
    best_h, best_c = -1, -1
    for h, c in entries:
        if c > best_c:
            best_h, best_c = h, c
    return best_h


def activity_base(s, now, daily_series, unit, tool_calls=None):
    """The half of a stats blob that is identical for every local CLI: what was
    done, when, and how consistently. Each provider adds its own token, model
    and cost fields on top.

    `tool_calls` overrides the top-level count for a blob that only records
    tool calls per day (Claude's cache does).
    """
    dates = [(a.get("date") or "") for a in (s.get("dailyActivity") or []) if a is not None and (a.get("date") or "") != ""]
    streaks = activity_streaks(dates, now)
    longest = s.get("longestSession") or {}
    first = s.get("firstSessionDate") or ""

    return {
        "available": True,
        "totalSessions": num(s.get("totalSessions")),
        "totalMessages": num(s.get("totalMessages")),
        "totalToolCalls": num(s.get("totalToolCalls")) if tool_calls is None else tool_calls,
        "firstDate": first,
        "computedDate": s.get("lastComputedDate") or "",
        "activeDays": len(set(dates)),
        "spanDays": span_days_since(first, now),
        "currentStreak": streaks["current"],
        "longestStreak": streaks["longest"],
        "longestSessionMs": num(longest.get("duration")),
        "longestSessionMessages": num(longest.get("messageCount")),
        "peakHour": peak_hour(s.get("hourCounts") or {}),
        # The frontends draw one per-day sparkline for every provider. The
        # series is named separately from the token totals because a provider
        # can record activity without recording tokens (see copilot_stats).
        "dailySeries": daily_series,
        "dailyUnit": unit,
    }


def claude_stats(s, now):
    if not isinstance(s, dict) or not s:
        return {"available": False}

    usage = s.get("modelUsage") or {}
    models = {}
    total = 0
    cost = 0
    searches = 0
    favorite = ""
    favorite_total = -1
    for key, e in usage.items():
        e = e or {}
        in_ = num(e.get("inputTokens"))
        out_ = num(e.get("outputTokens"))
        model_total = in_ + out_
        model_cost = num(e.get("costUSD"))
        model_searches = num(e.get("webSearchRequests"))
        models[key] = {
            "input": in_,
            "output": out_,
            "cacheRead": num(e.get("cacheReadInputTokens")),
            "cacheCreation": num(e.get("cacheCreationInputTokens")),
            "total": model_total,
            "cost": model_cost,
            "webSearches": model_searches,
            "contextWindow": num(e.get("contextWindow")),
        }
        total += model_total
        cost += model_cost
        searches += model_searches
        if model_total > favorite_total:
            favorite, favorite_total = key, model_total

    daily_tokens = [
        {
            "date": a.get("date") or "",
            "total": sum(num(v) for v in (a.get("tokensByModel") or {}).values()),
        }
        for a in (s.get("dailyModelTokens") or [])
    ]
    daily_tokens.sort(key=lambda a: a["date"])

    total_tool_calls = sum(num(a.get("toolCallCount")) for a in (s.get("dailyActivity") or []))

    r = activity_base(s, now, daily_tokens, "tokens", tool_calls=total_tool_calls)
    r.update(
        {
            "version": num(s.get("version")),
            "totalTokens": total,
            "totalCostUSD": cost,
            "totalWebSearches": searches,
            "favoriteModel": favorite,
            "models": models,
            "dailyTokens": daily_tokens,
        }
    )
    return r


def muse_stats(s, now):
    """Normalize the providers/muse.py aggregate blob.

    Muse is the only provider whose price list is on disk, so this is also the
    only stats blob that can carry a cost it computed itself — the shared
    "spend" tile renders it with no extra frontend code.
    """
    if not isinstance(s, dict) or num(s.get("totalSessions")) + num(s.get("subagentSessions")) == 0:
        return {"available": False}

    models = {}
    favorite = ""
    # Starts at zero, not -1: a model with no recorded output is never the
    # "favourite", and Muse does not always record usage (see providers/muse.py).
    favorite_total = 0
    for key, e in (s.get("modelUsage") or {}).items():
        e = e or {}
        out = num(e.get("outputTokens"))
        models[key] = {
            "input": num(e.get("inputTokens")),
            "output": out,
            "cached": num(e.get("cachedTokens")),
            "reasoning": num(e.get("reasoningTokens")),
            "total": num(e.get("totalTokens")),
            "sessions": num(e.get("sessions")),
            "contextWindow": num(e.get("contextWindow")),
            "cost": num(e.get("costUSD")),
        }
        # Output tokens, not the total: input is context resent on every call,
        # so ranking by it would just name whichever model ran longest.
        if out > favorite_total:
            favorite, favorite_total = key, out

    daily_tokens = [{"date": a.get("date") or "", "total": num(a.get("total"))} for a in (s.get("dailyModelTokens") or [])]
    daily_tokens.sort(key=lambda a: a["date"])

    workspaces = [w for w in (s.get("topWorkspaces") or []) if isinstance(w, dict)]

    r = activity_base(s, now, daily_tokens, "tokens")
    r.update(
        {
            "subagentSessions": num(s.get("subagentSessions")),
            "totalTokens": num(s.get("totalTokens")),
            "totalInputTokens": num(s.get("totalInputTokens")),
            "totalOutputTokens": num(s.get("totalOutputTokens")),
            "totalCachedTokens": num(s.get("totalCachedTokens")),
            "totalReasoningTokens": num(s.get("totalReasoningTokens")),
            "totalCostUSD": num(s.get("totalCostUSD")),
            "totalModelCalls": num(s.get("totalModelCalls")),
            "contextWindow": num(s.get("contextWindow")),
            "workspaceCount": num(s.get("workspaceCount")),
            "topWorkspaces": [{"name": w.get("name") or "", "sessions": num(w.get("sessions"))} for w in workspaces],
            "favoriteModel": favorite,
            "models": models,
            "dailyTokens": daily_tokens,
            "model": s.get("model") or "",
            "currency": s.get("currency") or "USD",
        }
    )
    return r


def cursor_stats(s, now):
    """Normalize the providers/cursor.py stats blob: the dashboard's per-model
    aggregate plus the (slimmed) per-request list, for the current billing
    cycle — the same numbers cursor.com/dashboard shows on its Usage page.

    Days and hours are local: the requests carry millisecond timestamps, and
    "which day was busy" is a question about the user's own calendar.
    """
    if not isinstance(s, dict) or not s:
        return {"available": False}
    agg = s.get("aggregated") if isinstance(s.get("aggregated"), dict) else {}
    events = [e for e in s.get("events") or [] if isinstance(e, dict)]

    requests_by_model = {}
    for e in events:
        requests_by_model[e.get("model") or ""] = requests_by_model.get(e.get("model") or "", 0) + 1

    models = {}
    favorite, favorite_out = "", 0
    for a in agg.get("aggregations") or []:
        if not isinstance(a, dict):
            continue
        name = a.get("modelIntent") or "unknown"
        inp, out = num(a.get("inputTokens")), num(a.get("outputTokens"))
        write, read = num(a.get("cacheWriteTokens")), num(a.get("cacheReadTokens"))
        models[name] = {
            "input": inp,
            "output": out,
            "cached": read,
            "cacheWrite": write,
            "total": inp + out + write + read,
            "cost": num(a.get("totalCents")) / 100,
            "requests": requests_by_model.get(name, 0),
        }
        if out > favorite_out:
            favorite, favorite_out = name, out

    total_tokens = sum(m["total"] for m in models.values())
    if total_tokens == 0 and not events:
        return {"available": False}

    daily, hours, spans = {}, {}, {}
    for e in events:
        ts = num(e.get("timestamp")) / 1000
        if ts <= 0:
            continue
        local = datetime.datetime.fromtimestamp(ts)
        day = local.strftime("%Y-%m-%d")
        tokens = num(e.get("input")) + num(e.get("output")) + num(e.get("cacheWrite")) + num(e.get("cacheRead"))
        tally = daily.setdefault(day, {"tokens": 0, "requests": 0})
        tally["tokens"] += tokens
        tally["requests"] += 1
        hours[str(local.hour)] = hours.get(str(local.hour), 0) + 1
        conversation = e.get("conversation")
        if isinstance(conversation, int) and conversation >= 0:
            first, last, count = spans.get(conversation, (ts, ts, 0))
            spans[conversation] = (min(first, ts), max(last, ts), count + 1)

    # Older requests may carry no token breakdown; a sparkline of zeros would
    # read as "idle", so fall back to counting requests.
    by_tokens = any(t["tokens"] > 0 for t in daily.values())
    unit = "tokens" if by_tokens else "requests"
    series = [{"date": d, "total": t["tokens"] if by_tokens else t["requests"]} for d, t in sorted(daily.items())]

    longest = max(spans.values(), key=lambda v: v[1] - v[0], default=None)
    blob = {
        "dailyActivity": [{"date": d} for d in daily],
        "totalSessions": len(spans),
        "totalMessages": len(events),
        "firstSessionDate": min(daily) if daily else "",
        "lastComputedDate": datetime.datetime.fromtimestamp(now).strftime("%Y-%m-%dT%H:%M:%S"),
        "longestSession": {"duration": (longest[1] - longest[0]) * 1000, "messageCount": longest[2]} if longest else {},
        "hourCounts": hours,
    }
    r = activity_base(blob, now, series, unit)
    event_count = int(num(s.get("eventCount")))
    r.update(
        {
            "totalTokens": total_tokens,
            "totalInputTokens": num(agg.get("totalInputTokens")),
            "totalOutputTokens": num(agg.get("totalOutputTokens")),
            "totalCachedTokens": num(agg.get("totalCacheReadTokens")),
            "totalCacheWriteTokens": num(agg.get("totalCacheWriteTokens")),
            "totalCostUSD": num(agg.get("totalCostCents")) / 100,
            "totalRequests": max(event_count, len(events)),
            # More requests than the paged fetch brought back: the per-day and
            # per-hour figures cover only the newest ones.
            "partial": event_count > len(events),
            "favoriteModel": favorite,
            "models": models,
            "dailyTokens": series if by_tokens else [],
            "periodStart": int(num(s.get("startMs")) // 1000),
            "currency": "USD",
        }
    )
    return r


def cline_stats(s, now):
    """Normalize the providers/cline.py session list — all local, all time.

    Cline records no per-message counts in the session header, so the
    messages tile stays at zero rather than opening every transcript.
    """
    sessions = [x for x in (s.get("sessions") if isinstance(s, dict) else None) or [] if isinstance(x, dict)]
    if not sessions:
        return {"available": False}

    models, workspaces, daily, hours = {}, {}, {}, {}
    favorite, favorite_out = "", 0
    totals = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "cost": 0}
    longest = None
    for x in sessions:
        tokens = num(x.get("input")) + num(x.get("output")) + num(x.get("cacheRead")) + num(x.get("cacheWrite"))
        for k in totals:
            totals[k] += num(x.get(k))
        name = x.get("model") or "unknown"
        m = models.setdefault(name, {"input": 0, "output": 0, "cached": 0, "cacheWrite": 0, "total": 0, "cost": 0, "sessions": 0})
        m["input"] += num(x.get("input"))
        m["output"] += num(x.get("output"))
        m["cached"] += num(x.get("cacheRead"))
        m["cacheWrite"] += num(x.get("cacheWrite"))
        m["total"] += tokens
        m["cost"] += num(x.get("cost"))
        m["sessions"] += 1
        if x.get("workspace"):
            workspaces[x["workspace"]] = workspaces.get(x["workspace"], 0) + 1
        local = datetime.datetime.fromtimestamp(num(x.get("startedAt")))
        day = local.strftime("%Y-%m-%d")
        daily[day] = daily.get(day, 0) + tokens
        hours[str(local.hour)] = hours.get(str(local.hour), 0) + 1
        duration = num(x.get("endedAt")) - num(x.get("startedAt"))
        if duration > 0 and (longest is None or duration > longest):
            longest = duration

    for name, m in models.items():
        # Output, not the total: input is context resent on every call.
        if m["output"] > favorite_out:
            favorite, favorite_out = name, m["output"]

    series = [{"date": d, "total": t} for d, t in sorted(daily.items())]
    blob = {
        "dailyActivity": [{"date": d} for d in daily],
        "totalSessions": len(sessions),
        "firstSessionDate": min(daily),
        "lastComputedDate": datetime.datetime.fromtimestamp(now).strftime("%Y-%m-%dT%H:%M:%S"),
        "longestSession": {"duration": longest * 1000} if longest else {},
        "hourCounts": hours,
    }
    r = activity_base(blob, now, series, "tokens")
    top = sorted(workspaces.items(), key=lambda kv: (-kv[1], kv[0]))[:5]
    r.update(
        {
            "totalTokens": totals["input"] + totals["output"] + totals["cacheRead"] + totals["cacheWrite"],
            "totalInputTokens": totals["input"],
            "totalOutputTokens": totals["output"],
            "totalCachedTokens": totals["cacheRead"],
            "totalCacheWriteTokens": totals["cacheWrite"],
            "totalCostUSD": totals["cost"],
            "favoriteModel": favorite,
            "models": models,
            "dailyTokens": series,
            "workspaceCount": len(workspaces),
            "topWorkspaces": [{"name": n, "sessions": c} for n, c in top],
            "currency": "USD",
        }
    )
    return r


def codex_stats(s, now):
    if not isinstance(s, dict) or num(s.get("totalSessions")) == 0:
        return {"available": False}

    usage = s.get("modelUsage") or {}
    models = {}
    favorite = ""
    favorite_total = -1
    for key, e in usage.items():
        e = e or {}
        model_total = num(e.get("totalTokens"))
        models[key] = {
            "input": num(e.get("inputTokens")),
            "output": num(e.get("outputTokens")),
            "cacheRead": num(e.get("cachedInput")),
            "reasoning": num(e.get("reasoningTokens")),
            "total": model_total,
            "sessions": num(e.get("sessions")),
            "contextWindow": num(e.get("contextWindow")),
        }
        if model_total > favorite_total:
            favorite, favorite_total = key, model_total

    daily_tokens = [{"date": a.get("date") or "", "total": num(a.get("total"))} for a in (s.get("dailyModelTokens") or [])]
    daily_tokens.sort(key=lambda a: a["date"])

    r = activity_base(s, now, daily_tokens, "tokens")
    r.update(
        {
            "totalTokens": num(s.get("totalTokens")),
            "favoriteModel": favorite,
            "models": models,
            "dailyTokens": daily_tokens,
            "model": s.get("model") or "",
            "effortLevel": s.get("effortLevel") or "",
        }
    )
    return r


def copilot_stats(s, now):
    """The Copilot CLI records activity but no tokens, models or cost, so this
    fills in the activity half of the same shape and leaves the token tiles
    empty (see providers/copilot_stats.py)."""
    if not isinstance(s, dict) or num(s.get("totalSessions")) == 0:
        return {"available": False}

    activity = [a for a in (s.get("dailyActivity") or []) if isinstance(a, dict)]
    daily_messages = [{"date": a.get("date") or "", "total": num(a.get("messageCount"))} for a in activity]
    daily_messages.sort(key=lambda a: a["date"])
    repos = [r for r in (s.get("topRepositories") or []) if isinstance(r, dict)]

    r = activity_base(s, now, daily_messages, "messages")
    r.update(
        {
            "totalTokens": 0,
            "totalFiles": num(s.get("totalFiles")),
            "totalRepositories": num(s.get("totalRepositories")),
            "topRepositories": [{"name": x.get("name") or "", "sessions": num(x.get("sessions"))} for x in repos],
            "favoriteModel": "",
            "models": {},
            "dailyTokens": [],
        }
    )
    return r


# OpenCode-billed usage (Zen and Go). Sessions run on a bring-your-own key
# (anthropic, openai, ...) belong to that provider, not the OpenCode account.
_OPENCODE_BILLED = ("opencode", "opencode-go")


def opencode_stats(s, now):
    """Build one stable stats shape from OpenCode's local SQLite ledger."""
    if not isinstance(s, dict):
        return {"available": False}
    sessions = [row for row in (s.get("sessions") or []) if isinstance(row, dict)]
    sessions = [row for row in sessions if row.get("id") or row.get("usage")]
    filtered_sessions = []
    for session in sessions:
        usage = [row for row in (session.get("usage") or []) if isinstance(row, dict) and row.get("provider") in _OPENCODE_BILLED]
        if usage:
            filtered_session = dict(session)
            filtered_session["usage"] = usage
            filtered_sessions.append(filtered_session)
    sessions = filtered_sessions
    if not sessions:
        return {"available": False}

    def usage_total(row):
        return sum(num(row.get(key)) for key in ("input", "output", "cacheRead", "cacheWrite", "reasoning"))

    def cost_state(rows):
        states = [row.get("costStatus") for row in rows if isinstance(row, dict) and usage_total(row) > 0]
        if not states:
            return "unavailable"
        if any(state in (None, "unavailable") for state in states):
            return "partial" if any(state in ("exact", "partial") for state in states) else "unavailable"
        return "partial" if any(state == "partial" for state in states) else "exact"

    models = {}
    upstream = {}
    daily = {}
    workspaces = {}
    all_buckets = []
    total_tokens = total_input = total_output = total_cache_read = total_cache_write = total_reasoning = 0
    total_cost = 0.0
    cost_rows = []
    favorite = ""
    favorite_total = -1

    def session_date(session):
        timestamp = num(session.get("lastActivity")) or num(session.get("createdAt"))
        try:
            return datetime.datetime.fromtimestamp(timestamp).strftime("%Y-%m-%d") if timestamp > 0 else ""
        except (OverflowError, OSError, ValueError):
            return ""

    for session in sessions:
        directory = session.get("directory") or ""
        if directory:
            workspaces[directory] = workspaces.get(directory, 0) + 1
        date = session_date(session)
        if date:
            daily.setdefault(date, 0)
        session_buckets = [row for row in (session.get("usage") or []) if isinstance(row, dict)]
        all_buckets.extend(session_buckets)
        for row in session_buckets:
            provider = row.get("provider") or "unknown"
            model = row.get("model") or "unknown"
            key = f"{provider}/{model}"
            in_ = num(row.get("input"))
            out_ = num(row.get("output"))
            cache_read = num(row.get("cacheRead"))
            cache_write = num(row.get("cacheWrite"))
            reasoning = num(row.get("reasoning"))
            tokens = in_ + out_ + cache_read + cache_write + reasoning
            cost = row.get("costUSD")
            cost = num(cost) if isinstance(cost, (int, float)) else None
            item = models.setdefault(
                key,
                {
                    "provider": provider,
                    "model": model,
                    "input": 0,
                    "output": 0,
                    "cacheRead": 0,
                    "cacheWrite": 0,
                    "reasoning": 0,
                    "total": 0,
                    "cost": 0,
                    "requests": 0,
                    "costStatus": "exact",
                },
            )
            item.update(
                {
                    "input": item["input"] + in_,
                    "output": item["output"] + out_,
                    "cacheRead": item["cacheRead"] + cache_read,
                    "cacheWrite": item["cacheWrite"] + cache_write,
                    "reasoning": item["reasoning"] + reasoning,
                    "total": item["total"] + tokens,
                    "requests": item["requests"] + 1,
                }
            )
            if cost is not None:
                item["cost"] += cost
                total_cost += cost
            if row.get("costStatus") == "unavailable":
                item["costStatus"] = "partial"
            if date:
                daily[date] += tokens
            total_input += in_
            total_output += out_
            total_cache_read += cache_read
            total_cache_write += cache_write
            total_reasoning += reasoning
            total_tokens += tokens
            upstream_item = upstream.setdefault(provider, {"provider": provider, "tokens": 0, "cost": 0, "requests": 0, "costStatus": "exact"})
            upstream_item["tokens"] += tokens
            upstream_item["requests"] += 1
            if cost is not None:
                upstream_item["cost"] += cost
            if row.get("costStatus") == "unavailable":
                upstream_item["costStatus"] = "partial"
            cost_rows.append(row)
            if tokens > favorite_total:
                favorite, favorite_total = key, tokens

    daily_tokens = [{"date": date, "total": total} for date, total in sorted(daily.items()) if date]
    dates = [row["date"] for row in daily_tokens]
    activity = {
        "dailyActivity": [{"date": date} for date in dates],
        "totalSessions": len(sessions),
        "totalMessages": sum(len(row.get("usage") or []) for row in sessions),
        "firstSessionDate": dates[0] if dates else "",
    }
    r = activity_base(activity, now, daily_tokens, "tokens")
    periods = []
    midnight = datetime.datetime.fromtimestamp(now).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    for key, label, since in (
        ("today", "Today", midnight),
        ("7d", "Last 7 days", now - 7 * 86400),
        ("30d", "Last 30 days", now - 30 * 86400),
        ("all", "All time", 0),
    ):
        selected = [row for row in sessions if num(row.get("lastActivity")) >= since]
        selected_rows = [bucket for row in selected for bucket in (row.get("usage") or []) if isinstance(bucket, dict)]
        periods.append(
            {
                "key": key,
                "label": label,
                "sessions": len(selected),
                "tokens": sum(usage_total(bucket) for bucket in selected_rows),
                "cost": sum(num(bucket.get("costUSD")) for bucket in selected_rows if isinstance(bucket.get("costUSD"), (int, float))),
                "costStatus": cost_state(selected_rows),
            }
        )

    r.update(
        {
            "totalTokens": total_tokens,
            "totalInputTokens": total_input,
            "totalOutputTokens": total_output,
            "totalCachedTokens": total_cache_read + total_cache_write,
            "totalReasoningTokens": total_reasoning,
            "totalCostUSD": total_cost,
            "costStatus": cost_state(cost_rows),
            "costProvenance": "catalog/local ledger",
            "favoriteModel": favorite,
            "models": models,
            "upstreamProviders": sorted(upstream.values(), key=lambda row: row["tokens"], reverse=True),
            "topWorkspaces": [
                {"name": name, "sessions": count} for name, count in sorted(workspaces.items(), key=lambda item: item[1], reverse=True)[:8]
            ],
            "dailyTokens": daily_tokens,
            "periods": periods,
            "currency": "USD",
        }
    )
    return r
