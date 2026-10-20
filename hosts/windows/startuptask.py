"""Start at sign-in for the Microsoft Store (MSIX) build.

An MSIX app's HKCU\\...\\Run writes are virtualized and never start it at
sign-in; the package declares a windows.startupTask instead
(hosts/windows/msix/AppxManifest.xml.in), which this module switches through
WinRT's StartupTask. Outside a package is_packaged() is False and app.py keeps
using the Run key.
"""

import asyncio
import ctypes
import sys

TASK_ID = "TideSI"  # the manifest's StartupTask TaskId

_APPMODEL_ERROR_NO_PACKAGE = 15700
# StartupTaskState: Disabled 0, DisabledByUser 1, Enabled 2, DisabledByPolicy 3, EnabledByPolicy 4.
_ENABLED = (2, 4)


def is_packaged():
    """True when running from an installed MSIX package."""
    if sys.platform != "win32":
        return False
    length = ctypes.c_uint32(0)
    code = ctypes.windll.kernel32.GetCurrentPackageFullName(ctypes.byref(length), None)
    return code != _APPMODEL_ERROR_NO_PACKAGE


def _task():
    from winrt.windows.applicationmodel import StartupTask

    return asyncio.run(StartupTask.get_async(TASK_ID))


def enabled():
    return int(_task().state) in _ENABLED


def set_enabled(on):
    """Turn the task on or off. Windows keeps a task the user switched off in
    Settings → Apps → Startup off: the request is then ignored and enabled()
    keeps answering False."""
    task = _task()
    if not on:
        task.disable()
    elif int(task.state) not in _ENABLED:
        asyncio.run(task.request_enable_async())
