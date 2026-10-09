"""The popup's real blur on Windows 11: the system's Acrylic backdrop.

A Qt window cannot see what is behind it, so the shared QML glass
(ui/PopupBackground.qml) can only paint a blur-like gradient. Windows 11
draws a real one, the Acrylic "transient window" backdrop its own flyouts
use, for any window that asks through DWM. This asks for it on the popup,
with Windows' rounded corners and the backdrop's light or dark matched to
the popup's Theme; the QML is told (Main.qml's nativeBlur) to thin its own
glass out so the blur reads through. The macOS counterpart is
hosts/macos/vibrancy.py.

Windows 10 has no system backdrop for other apps' windows: apply() says no
there, and the QML glass stays as it is.
"""

import ctypes
import sys
from ctypes import wintypes

# DwmSetWindowAttribute attributes (dwmapi.h).
DWMWA_USE_IMMERSIVE_DARK_MODE = 20
DWMWA_WINDOW_CORNER_PREFERENCE = 33
DWMWA_SYSTEMBACKDROP_TYPE = 38
DWMWCP_ROUND = 2
DWMSBT_TRANSIENTWINDOW = 3
# The system backdrop arrived in Windows 11 22H2.
FIRST_BUILD = 22621


class _Margins(ctypes.Structure):
    _fields_ = [("left", ctypes.c_int), ("right", ctypes.c_int), ("top", ctypes.c_int), ("bottom", ctypes.c_int)]


def _dwm():
    api = ctypes.windll.dwmapi
    api.DwmSetWindowAttribute.argtypes = [wintypes.HWND, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD]
    api.DwmSetWindowAttribute.restype = ctypes.c_long
    api.DwmExtendFrameIntoClientArea.argtypes = [wintypes.HWND, ctypes.POINTER(_Margins)]
    api.DwmExtendFrameIntoClientArea.restype = ctypes.c_long
    return api


def available():
    return sys.platform == "win32" and sys.getwindowsversion().build >= FIRST_BUILD


def _set(hwnd, attribute, value):
    data = ctypes.c_int(value)
    return _dwm().DwmSetWindowAttribute(wintypes.HWND(hwnd), attribute, ctypes.byref(data), ctypes.sizeof(data)) == 0


def apply(window, light):
    """Acrylic behind `window` (a QWindow that has been shown once), in light
    or dark. True when Windows took it."""
    if not available():
        return False
    hwnd = int(window.winId())
    # The backdrop fills the frame; a frameless window has none until the
    # frame is extended over all of it.
    margins = _Margins(-1, -1, -1, -1)
    if _dwm().DwmExtendFrameIntoClientArea(wintypes.HWND(hwnd), ctypes.byref(margins)) != 0:
        return False
    _set(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND)
    set_light(window, light)
    return _set(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, DWMSBT_TRANSIENTWINDOW)


def set_light(window, light):
    """The backdrop's own light or dark, matched to the popup's Theme."""
    _set(int(window.winId()), DWMWA_USE_IMMERSIVE_DARK_MODE, 0 if light else 1)
