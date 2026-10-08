"""Optional pill overlay beside the primary taskbar's notification area.

Explorer does not reserve space for this window. It can overlap task buttons,
so docking is opt-in; dragging the pill detaches it. A missing notification
area, vertical taskbar, or auto-hide taskbar keeps the normal floating pill.
All returned coordinates are physical pixels. No Explorer reparenting or
process injection is used.
"""

import ctypes
from ctypes import wintypes

HWND_TOPMOST = -1
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_NOACTIVATE = 0x0010
ABM_GETSTATE = 4
ABS_AUTOHIDE = 1


class _AppBarData(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("hWnd", wintypes.HWND),
        ("uCallbackMessage", wintypes.UINT),
        ("uEdge", wintypes.UINT),
        ("rc", wintypes.RECT),
        ("lParam", wintypes.LPARAM),
    ]


_user32 = ctypes.windll.user32
_user32.FindWindowW.restype = wintypes.HWND
_user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
_user32.FindWindowExW.restype = wintypes.HWND
_user32.FindWindowExW.argtypes = [wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR]
_user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
_user32.GetWindowRect.restype = wintypes.BOOL
_user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.UINT]
_user32.SetWindowPos.restype = wintypes.BOOL
_shell32 = ctypes.windll.shell32
_shell32.SHAppBarMessage.argtypes = [wintypes.DWORD, ctypes.POINTER(_AppBarData)]
_shell32.SHAppBarMessage.restype = ctypes.c_size_t


def _rect(hwnd):
    rect = wintypes.RECT()
    if not hwnd or not _user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        return None
    return rect.left, rect.top, rect.right, rect.bottom


def place():
    """Return (taskbar rectangle, notification-area left edge), or None."""
    taskbar = _user32.FindWindowW("Shell_TrayWnd", None)
    bar = _rect(taskbar)
    if bar is None:
        return None
    data = _AppBarData()
    data.cbSize = ctypes.sizeof(data)
    data.hWnd = taskbar
    if _shell32.SHAppBarMessage(ABM_GETSTATE, ctypes.byref(data)) & ABS_AUTOHIDE:
        return None
    left, top, right, bottom = bar
    if right - left <= bottom - top:
        return None
    tray = _rect(_user32.FindWindowExW(taskbar, None, "TrayNotifyWnd", None))
    if tray is None or not left < tray[0] < right:
        return None
    return bar, tray[0]


def keep_on_top(window):
    """Raise above the taskbar without taking keyboard focus."""
    return bool(
        _user32.SetWindowPos(wintypes.HWND(int(window.winId())), wintypes.HWND(HWND_TOPMOST), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
    )
