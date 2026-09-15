"""get-ai-usage — the shared provider backend for every frontend of this widget.

This tool owns credential discovery, provider API requests, response parsing,
quota/percentage maths, reset timestamps and error/stale state. The KDE Plasma
widget and the Hyprland/Quickshell shell both consume its output and do
presentation only; see docs/provider-contract.md for the schema.

  get-ai-usage --provider claude          one provider (KDE's active tab)
  get-ai-usage --provider claude,openai   several providers (active + pinned)
  get-ai-usage --all                      every enabled provider (Hyprland)
  get-ai-usage --normalize < envelope     replay a raw envelope offline (tests)
"""

import json
import sys

from . import config, envelope
from .contract import finalize
from .normalize import normalize

USAGE = """usage: get-ai-usage [--all | --provider <id>[,<id>...] | --normalize | --sessions]

  --all                 fetch every provider enabled in the shared settings file
  --provider <ids>      fetch the named providers regardless of the toggles
  --normalize           read one raw envelope on stdin, print the provider object
  --sessions            list recent local agent sessions (no paths or transcripts)
  --open-session <key>  resume one listed session (by its openKey) in a terminal
  --list                print the known provider ids, one per line
  -h, --help            show this help

providers: """ + " ".join(config.ALL_PROVIDERS)


def _emit(obj):
    sys.stdout.write(json.dumps(finalize(obj), separators=(",", ":"), ensure_ascii=False) + "\n")


def snapshot():
    """The envelope `--all` prints, for an in-process caller (the Windows tray
    app, which has no shell to run this module through).

    Like main(), this exports the settings file's keys into os.environ first. A
    long-lived caller has to put its environment back afterwards, or a key the
    user later clears would linger there."""
    cfg = config.load_settings()
    config.apply_widget_env(cfg)
    return finalize(envelope.build(envelope.enabled(cfg)))


def main(argv):
    mode = ""
    requested = ""
    open_key = ""

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--all":
            mode = "all"
        elif arg == "--provider":
            mode = "provider"
            i += 1
            requested = argv[i] if i < len(argv) else ""
        elif arg.startswith("--provider="):
            mode = "provider"
            requested = arg[len("--provider=") :]
        elif arg == "--normalize":
            mode = "normalize"
        elif arg == "--sessions":
            mode = "sessions"
        elif arg == "--open-session":
            mode = "open-session"
            i += 1
            open_key = argv[i] if i < len(argv) else ""
        elif arg.startswith("--open-session="):
            mode = "open-session"
            open_key = arg[len("--open-session=") :]
        elif arg == "--list":
            for p in config.ALL_PROVIDERS:
                print(p)
            return 0
        elif arg in ("-h", "--help"):
            print(USAGE)
            return 0
        else:
            sys.stderr.write(f"get-ai-usage: unknown argument: {arg}\n")
            sys.stderr.write(USAGE + "\n")
            return 2
        i += 1

    if mode == "sessions":
        from .sessions import collect_sessions

        _emit(collect_sessions())
        return 0

    if mode == "open-session":
        from .sessions import open_session

        ok, message = open_session(open_key)
        print(json.dumps({"ok": ok, "message": message}))
        return 0 if ok else 1

    cfg = config.load_settings()
    config.apply_widget_env(cfg)

    if mode == "normalize":
        try:
            raw = json.load(sys.stdin)
        except ValueError as e:
            sys.stderr.write(f"get-ai-usage: invalid envelope on stdin: {e}\n")
            return 2
        _emit(normalize(raw))
        return 0

    if not mode:
        mode = "all"

    if mode == "provider":
        if not requested:
            sys.stderr.write("get-ai-usage: --provider needs at least one id\n")
            return 2
        selected = []
        for id_ in requested.split(","):
            if id_ not in config.ALL_PROVIDERS:
                sys.stderr.write(f"get-ai-usage: unknown provider: {id_}\n")
                return 2
            selected.append(id_)
    else:
        selected = envelope.enabled(cfg)

    _emit(envelope.build(selected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
