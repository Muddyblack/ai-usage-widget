"""Runs the antigravity-usage CLI if present, else scans the process table for
the Antigravity language server and probes its local API directly.

Ported from tools/sh/get-antigravity-usage. The bash version shelled out to
`ss`/`netstat` to find the language server's listening ports; on Linux this
reads /proc/[pid]/fd and /proc/net/tcp[6] directly instead, which is both more
portable (no external tool required) and avoids a process fork per probe.

Platforms without /proc (Windows, macOS) go through psutil instead. It is an
optional import: the Windows build bundles it, and without it the provider
says what is missing rather than claiming Antigravity is not running.
"""

import datetime
import json
import os
import shutil
import ssl
import subprocess
import urllib.error
import urllib.request

from .. import config as _config
from .. import paths
from ..http import as_json

_HAS_PROC = os.path.isdir("/proc/self")


def _ttl():
    # Keep this below the widget's 300-second default poll so a cache entry
    # cannot make a later poll permanently display an old quota snapshot.
    try:
        return max(0, int(os.environ.get("ANTIGRAVITY_TTL_SECONDS", "90")))
    except ValueError:
        return 90


def _cache_path():
    return os.path.join(_config.cache_dir(), "antigravity.json")


def _read_cache(ttl):
    try:
        with open(_cache_path(), encoding="utf-8", errors="replace") as stream:
            cached = json.load(stream)
    except (OSError, ValueError):
        return None
    if not isinstance(cached, dict) or not isinstance(cached.get("usage"), dict):
        return None
    usage = cached["usage"]
    if usage.get("method") != "cli":
        return None
    try:
        age = datetime.datetime.now(datetime.timezone.utc).timestamp() - float(cached.get("fetchedAt") or 0)
    except (TypeError, ValueError):
        return None
    if not 0 <= age < ttl:
        return None
    safe_usage = dict(usage)
    safe_usage["email"] = _account_email()
    return safe_usage


def _write_cache(usage):
    if "error" in usage:
        return
    safe_usage = dict(usage)
    # The live formatter also reports the account email. Keep the cache to the
    # CLI usage shape, but never persist identity data (or language-server data).
    safe_usage["email"] = None
    try:
        os.makedirs(_config.cache_dir(), exist_ok=True)
        with open(_cache_path(), "w", encoding="utf-8") as stream:
            json.dump(
                {"fetchedAt": datetime.datetime.now(datetime.timezone.utc).timestamp(), "usage": safe_usage},
                stream,
            )
    except (OSError, ValueError):
        pass


def _psutil():
    try:
        import psutil
    except ImportError:
        return None
    return psutil


def _proc_cmdlines():
    """(pid, argv) for every process whose command line is readable, read
    straight out of /proc."""
    try:
        pids = [e for e in os.listdir("/proc") if e.isdigit()]
    except OSError:
        return
    for pid in pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                raw = f.read()
        except OSError:
            continue
        parts = raw.split(b"\x00")
        if parts and parts[-1] == b"":
            parts = parts[:-1]
        yield pid, [a.decode("utf-8", "replace") for a in parts]


def _psutil_cmdlines():
    psutil = _psutil()
    if psutil is None:
        return
    # process_iter() with an attribute list reports a process it may not
    # inspect as None instead of raising AccessDenied.
    for proc in psutil.process_iter(["pid", "cmdline"]):
        args = proc.info.get("cmdline")
        if args:
            yield proc.info["pid"], list(args)


def _scan_processes():
    found = []
    for pid, args in _proc_cmdlines() if _HAS_PROC else _psutil_cmdlines():
        text = " ".join(args)
        argv0_name = os.path.basename(args[0]) if args else ""
        if not _HAS_PROC:
            # Case-insensitive file systems: the install folder is
            # "Antigravity", and the CLI is agy.exe.
            text = text.lower()
            argv0_name = os.path.splitext(argv0_name)[0].lower()
        # The standalone IDE (and, when active, the VS Code extension's
        # language server) mention "antigravity" in their cmdline and carry
        # a --csrf_token flag we can read straight out of /proc. The
        # Antigravity CLI's "agy --hub" process is also Antigravity, but
        # doesn't expose its CSRF token via cmdline or (thanks to Yama
        # ptrace_scope) environ, so it can never be queried here - it's
        # still matched so we can report it as "found but unreachable"
        # instead of falsely claiming Antigravity isn't running at all.
        if "antigravity" not in text and argv0_name != "agy":
            continue

        csrf_token, ext_port = "", ""
        i = 0
        while i < len(args):
            a = args[i]
            if a == "--csrf_token" and i + 1 < len(args):
                i += 1
                csrf_token = args[i]
            elif a.startswith("--csrf_token="):
                csrf_token = a.split("=", 1)[1]
            elif a in ("--extension_server_port", "--hub-port") and i + 1 < len(args):
                i += 1
                ext_port = args[i]
            elif a.startswith("--extension_server_port=") or a.startswith("--hub-port="):
                ext_port = a.split("=", 1)[1]
            i += 1

        found.append((pid, csrf_token, ext_port))
    return found


def _pid_listening_ports(pid):
    return _proc_listening_ports(pid) if _HAS_PROC else _psutil_listening_ports(pid)


def _psutil_listening_ports(pid):
    psutil = _psutil()
    if psutil is None:
        return []
    try:
        proc = psutil.Process(int(pid))
        # net_connections() is the psutil 6 name; connections() the older one.
        lister = getattr(proc, "net_connections", None) or proc.connections
        conns = lister(kind="tcp")
    except (psutil.Error, ValueError):
        return []
    return sorted({c.laddr.port for c in conns if c.status == psutil.CONN_LISTEN and c.laddr})


def _proc_listening_ports(pid):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for entry in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, entry))
            except OSError:
                continue
            if target.startswith("socket:["):
                inodes.add(target[8:-1])
    except OSError:
        return []

    ports = set()
    for proc_net in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(proc_net, encoding="utf-8") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A" or fields[9] not in inodes:
                continue
            try:
                port = int(fields[1].split(":")[1], 16)
            except (IndexError, ValueError):
                continue
            ports.add(port)
    return sorted(ports)


def _probe(url, token, body, timeout, ctx):
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Connect-Protocol-Version": "1", "X-Codeium-Csrf-Token": token},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        try:
            body_text = e.read().decode("utf-8", "replace")
        except Exception:
            body_text = ""
        return e.code, body_text
    except Exception:
        return None, None


def _probe_port(port, token):
    body = json.dumps({"wrapper_data": {}}).encode()
    for scheme in ("https", "http"):
        url = f"{scheme}://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/GetUnleashData"
        ctx = ssl._create_unverified_context() if scheme == "https" else None
        status, _ = _probe(url, token, body, 1, ctx)
        if status in (200, 401):
            return scheme
    return None


def _fetch_user_status(scheme, port, token):
    body = json.dumps({"metadata": {"ideName": "antigravity", "extensionName": "antigravity", "locale": "en"}}).encode()
    url = f"{scheme}://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/GetUserStatus"
    ctx = ssl._create_unverified_context() if scheme == "https" else None
    status, text = _probe(url, token, body, 2, ctx)
    if not text or "error" in text:
        return None
    return as_json(text)


def _format_user_status(data):
    us = data.get("userStatus") or {}
    ps = us.get("planStatus") or {}
    plan_info = ps.get("planInfo") or {}
    configs = (us.get("cascadeModelConfigData") or {}).get("clientModelConfigs") or []

    prompt_credits = None
    avail = ps.get("availablePromptCredits")
    monthly = plan_info.get("monthlyPromptCredits")
    if avail is not None and monthly is not None and monthly > 0:
        prompt_credits = {
            "available": avail,
            "monthly": monthly,
            "usedPercentage": (monthly - avail) / monthly,
            "remainingPercentage": avail / monthly,
        }

    models = []
    for c in configs:
        model_or_alias = c.get("modelOrAlias") or {}
        model_id = model_or_alias.get("model") or "unknown"
        label = c.get("label") or model_or_alias.get("model")
        quota = c.get("quotaInfo") or {}
        remaining = quota.get("remainingFraction")
        models.append(
            {
                "label": label,
                "modelId": model_id,
                "remainingPercentage": remaining,
                "isExhausted": remaining == 0,
                "resetTime": quota.get("resetTime"),
                "isAutocompleteOnly": ("gemini-2.5" in (model_or_alias.get("model") or "")) or ("Gemini 2.5" in (c.get("label") or "")),
            }
        )

    user_tier = us.get("userTier") or {}
    plan_type = user_tier.get("name") if user_tier.get("name") else None

    return {
        # Local time with a literal "Z", matching what the jq version emitted
        # via strflocaltime. Nothing in normalize/ reads this field; it exists
        # to mirror the antigravity-usage CLI's output shape.
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "method": "local",
        "email": us.get("email"),
        "planType": plan_type,
        "promptCredits": prompt_credits,
        "models": models,
    }


def _account_email():
    path = os.path.expanduser("~/.gemini/google_accounts.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    return data.get("active") if isinstance(data, dict) else None


def _run_agy_usage(agy_path):
    try:
        proc = subprocess.run(
            [agy_path, "--output-format", "json", "--print=/usage"],
            capture_output=True,
            text=True,
            # Named, or Windows decodes the CLI's UTF-8 as its ANSI code page.
            encoding="utf-8",
            errors="replace",
            timeout=20,
            **paths.no_window(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    parsed = as_json(proc.stdout)
    if not isinstance(parsed, dict) or parsed.get("status") != "SUCCESS":
        return None
    command = parsed.get("command") or {}
    return command.get("data") if command.get("name") == "usage" else None


def _format_agy_usage(data):
    models = []
    for group in data.get("groups") or []:
        group_name = group.get("name") or "Unknown"
        # Only the weekly bucket drives the group's pct: it's the binding
        # constraint over time. The 5-hour bucket is a burst limiter that
        # sits near 100% outside of active bursts, and normalize_antigravity
        # averages every model in a family together, so mixing it in here
        # would wash out the weekly figure instead of adding information.
        bucket = next((b for b in group.get("buckets") or [] if b.get("window") == "weekly"), None)
        if bucket is None:
            continue
        remaining = bucket.get("remaining_fraction")
        remaining = remaining if isinstance(remaining, (int, float)) and not isinstance(remaining, bool) else None
        models.append(
            {
                "label": group_name,
                "modelId": bucket.get("id") or f"{group_name}-weekly",
                "remainingPercentage": remaining,
                "isExhausted": remaining == 0,
                "resetTime": bucket.get("reset_time"),
                "isAutocompleteOnly": False,
            }
        )
    return {
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "method": "cli",
        "email": _account_email(),
        "planType": None,
        "promptCredits": None,
        "models": models,
    }


def get_antigravity_usage():
    cli = shutil.which("aiu") or shutil.which("antigravity-usage")
    if cli:
        try:
            proc = subprocess.run(
                [cli, "--json"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15, **paths.no_window()
            )
        except (OSError, subprocess.TimeoutExpired):
            proc = None
        if proc is not None and proc.returncode == 0:
            parsed = as_json(proc.stdout)
            return parsed if isinstance(parsed, dict) else {}

    # A reachable local language server (the standalone IDE, or the VS Code
    # extension's own server) answers with real per-model quota - richer
    # than agy's /usage, which only reports two family-level weekly
    # buckets. Prefer it whenever one is actually reachable.
    found_any_process = False
    for pid, csrf_token, ext_port in _scan_processes():
        found_any_process = True
        if not csrf_token:
            # No token available to us (e.g. the CLI's "agy --hub" process,
            # which doesn't put it on the cmdline) - any request would just
            # 401. Still counts as "found" for the error message below.
            continue
        ports = _pid_listening_ports(pid)
        if not ports and ext_port:
            try:
                ports = [int(ext_port)]
            except ValueError:
                ports = []
        for port in ports:
            scheme = _probe_port(port, csrf_token)
            if scheme is None:
                continue
            data = _fetch_user_status(scheme, port, csrf_token)
            if data is not None:
                return _format_user_status(data)

    # No reachable local server - fall back to agy's own /usage command.
    # It needs neither a running IDE nor the language server's CSRF token,
    # just the CLI itself, but only reports coarse per-family quota.
    ttl = _ttl()
    if found_any_process and ttl > 0:
        cached = _read_cache(ttl)
        if cached is not None:
            return cached

    agy = shutil.which("agy")
    if agy:
        agy_data = _run_agy_usage(agy)
        if agy_data is not None:
            usage = _format_agy_usage(agy_data)
            if ttl > 0:
                _write_cache(usage)
            return usage

    if found_any_process:
        return {"error": "Antigravity language server found but could not connect to API"}
    if not _HAS_PROC and _psutil() is None:
        return {"error": "Finding Antigravity on this platform needs the psutil package (pip install psutil)"}
    return {"error": "Antigravity is not running. Please open your IDE."}
