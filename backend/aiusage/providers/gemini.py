"""Read Gemini CLI token usage from its local chat files.

The Gemini CLI saves each session as ``~/.gemini/tmp/<project>/chats/session-*.json``
(a ``messages`` list) or ``.jsonl`` (a header line, then one message per line).
Replies of type ``gemini`` carry a ``tokens`` object: ``input`` (which already
includes ``cached``), ``output``, ``thoughts``, ``tool`` and ``total``.

Nothing is sent anywhere and no key is read. Only counters, model ids and the
project folder name leave this module — never prompts, replies or paths.

Cost is deliberately left out: a Gemini CLI login is usually a free tier or a
subscription, so pricing the tokens at API rates would overstate what was billed.
The token counts are exact.
"""

import datetime
import json
import os
import re

_MAX_FILE_BYTES = 64 * 1024 * 1024
_HASHED = re.compile(r"[0-9a-f]{64}")


def chat_roots():
    """Every ``tmp`` directory that may hold chats, best first."""
    base = os.environ.get("GEMINI_CLI_HOME") or os.path.expanduser("~")
    return [os.path.normpath(os.path.join(base, ".gemini", "tmp"))]


def _count(value):
    # Booleans and negatives are not recorded token counts.
    return int(value) if type(value) in (int, float) and 0 <= value < 2**53 else 0


def _timestamp(value):
    if isinstance(value, str) and value:
        try:
            return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return 0
    return 0


def _bucket(message, at):
    tokens = message.get("tokens")
    if not isinstance(tokens, dict):
        return None
    cached = _count(tokens.get("cached"))
    # `input` includes the cached part; the tool-use prompt is input as well, and
    # reasoning is billed as output.
    fresh = max(_count(tokens.get("input")) - cached, 0) + _count(tokens.get("tool"))
    output = _count(tokens.get("output")) + _count(tokens.get("thoughts"))
    if not (fresh or output or cached):
        return None
    model = message.get("model")
    return {
        "provider": "google",
        "model": model if isinstance(model, str) and model else "unknown",
        "input": fresh,
        "output": output,
        "cacheRead": cached,
        "cacheWrite": 0,
        "timestamp": at,
        "costStatus": "unavailable",
    }


def _entries(path):
    """(header, messages) of one chat file; ({}, []) when it cannot be read."""
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            if path.endswith(".jsonl"):
                rows = []
                for line in stream:
                    try:
                        row = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(row, dict):
                        rows.append(row)
                header = rows[0] if rows and "sessionId" in rows[0] else {}
                return header, rows
            data = json.load(stream)
    except (OSError, ValueError):
        return {}, []
    if not isinstance(data, dict):
        return {}, []
    messages = data.get("messages")
    return data, [m for m in messages if isinstance(m, dict)] if isinstance(messages, list) else []


def _read_file(path):
    header, messages = _entries(path)
    usage, seen, last = [], set(), 0
    for message in messages:
        at = _timestamp(message.get("timestamp"))
        last = max(last, at)
        if message.get("type") != "gemini":
            continue
        message_id = message.get("id")
        if isinstance(message_id, str):
            # A resumed session rewrites earlier messages.
            if message_id in seen:
                continue
            seen.add(message_id)
        bucket = _bucket(message, at)
        if bucket:
            usage.append(bucket)
    session_id = header.get("sessionId") if isinstance(header.get("sessionId"), str) else ""
    return session_id, usage, last or _timestamp(header.get("lastUpdated"))


def read_sessions():
    sessions, known = [], set()
    for root in chat_roots():
        try:
            projects = sorted(os.scandir(root), key=lambda entry: entry.name)
        except OSError:
            continue
        for project in projects:
            chats = os.path.join(project.path, "chats")
            try:
                files = sorted(os.scandir(chats), key=lambda entry: entry.name)
            except OSError:
                continue
            # The project folder is a name, or a hash of the path when Gemini had none.
            folder = "" if _HASHED.fullmatch(project.name) else project.name
            for entry in files:
                if not entry.name.startswith("session-") or not entry.name.endswith((".json", ".jsonl")):
                    continue
                try:
                    stat = entry.stat()
                except OSError:
                    continue
                if not entry.is_file() or stat.st_size > _MAX_FILE_BYTES:
                    continue
                session_id, usage, last = _read_file(entry.path)
                key = session_id or entry.path
                if not usage or key in known:
                    continue
                known.add(key)
                stamps = [row["timestamp"] for row in usage if row["timestamp"]]
                sessions.append(
                    {
                        "id": session_id or entry.name.rsplit(".", 1)[0],
                        "title": "",
                        "directory": folder,
                        "createdAt": min(stamps) if stamps else last,
                        "lastActivity": last or stat.st_mtime,
                        "agent": "gemini",
                        "usage": usage,
                    }
                )
    return sorted(sessions, key=lambda row: row["lastActivity"], reverse=True)


def usage_snapshot():
    return {"sessions": read_sessions()}
