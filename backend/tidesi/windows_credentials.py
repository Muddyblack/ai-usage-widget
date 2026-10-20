"""Read one known generic credential; never enumerate or log secrets."""

import ctypes
from ctypes import wintypes

from . import paths


class _Credential(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD),
        ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR),
        ("Comment", wintypes.LPWSTR),
        ("LastWritten", wintypes.FILETIME),
        ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD),
        ("AttributeCount", wintypes.DWORD),
        ("Attributes", ctypes.c_void_p),
        ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


def password(target):
    if not paths.IS_WINDOWS:
        return ""
    try:
        api = ctypes.WinDLL("advapi32", use_last_error=True)
        pointer = ctypes.POINTER(_Credential)()
        api.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(_Credential))]
        api.CredReadW.restype = wintypes.BOOL
        api.CredFree.argtypes = [ctypes.c_void_p]
        api.CredFree.restype = None
        if not api.CredReadW(target, 1, 0, ctypes.byref(pointer)):
            return ""
        try:
            item = pointer.contents
            # go-keyring stores raw UTF-8 bytes, not a UTF-16 password.
            return ctypes.string_at(item.CredentialBlob, item.CredentialBlobSize).decode("utf-8")
        finally:
            api.CredFree(pointer)
    except (OSError, UnicodeError):
        return ""
