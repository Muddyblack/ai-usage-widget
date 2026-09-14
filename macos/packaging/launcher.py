"""PyInstaller's entry point: both backend CLIs in one frozen binary.

macOS ships no Python anyone can rely on — /usr/bin/python3 is a stub that
offers to install the Xcode command line tools — so `AI Usage.app` carries its
own. The backend is standard-library-only apart from psutil, which is what
makes that a 15 MB detail rather than a project.

    ai-usage-backend --all               the provider envelope (aiusage.__main__)
    ai-usage-backend history autoload     the shared usage history (aiusage.historyio)

Everything else is passed straight through, so the frozen binary answers
--provider, --normalize, --list and --help exactly as `get-ai-usage` does.
"""

import sys

from aiusage.__main__ import main as usage_main
from aiusage.historyio import main as history_main


def main(argv):
    if argv and argv[0] == "history":
        return history_main(argv[1:])
    return usage_main(argv)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
