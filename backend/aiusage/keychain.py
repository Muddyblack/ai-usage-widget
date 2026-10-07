"""The macOS login Keychain, read the way the tools that write it read it.

Several CLIs this widget follows keep their login in the Keychain on macOS
instead of in a file — Claude Code, cursor-agent, `gh` — so a provider that
only knows the Linux file finds nothing on a Mac.

Always through ``/usr/bin/security``, never the Security framework. A keychain
item's ACL names the programs allowed to read it and its partition list names
the signing identities; these items are created by running ``security``, which
leaves the ACL trusting that tool and the partition list holding
``apple-tool:`` — a list no third-party signature can join, and one that
"Always Allow" does not edit. Read through the framework, a widget polling
every few minutes would raise the "wants to access your keychain" dialog on
every poll, for the life of the app. Asking the same Apple-signed tool that
wrote the item raises none, whatever this app is signed with.
"""

import subprocess

from . import paths


def password(service, account=None):
    """One generic-password item's secret, or "" when there is none to read.

    `account` None asks for the service's item whatever account it is under,
    which is what `security` does when it is given no -a. That is the right
    question for a tool that keys its item to something this package cannot
    reconstruct — and the wrong one for a tool whose item is keyed by user
    name, where a machine with two logins would answer with either.

    Every non-zero exit is the same answer — no credential — and the cases are
    not worth telling apart here: `security` reports the low byte of the
    OSStatus, so 44 is errSecItemNotFound (nobody logged in), 36 is
    errSecInteractionNotAllowed (an SSH session with no keychain to unlock) and
    128 is errSecUserCanceled (the user said no).

    Nothing is logged on any path, including failures. The one thing this
    function handles is a secret, and a copy in a log file is a copy the user
    cannot easily find or clear.
    """
    if not paths.IS_MACOS or not service or account == "":
        return ""
    argv = ["/usr/bin/security", "find-generic-password", "-s", service, "-w"]
    if account is not None:
        argv[2:2] = ["-a", account]
    try:
        result = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()
