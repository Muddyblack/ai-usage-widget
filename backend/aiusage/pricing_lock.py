import os
import time

_LOCK_TIMEOUT_SECONDS = 30


def _is_process_alive(pid):
    """Check if a process with the given PID is currently running."""
    if os.name == "nt":
        # On Windows, signal 0 is CTRL_C_EVENT (0), which calls GenerateConsoleCtrlEvent
        # and sends a Ctrl+C event into the console, causing spurious KeyboardInterrupt!
        try:
            import psutil

            return psutil.pid_exists(pid)
        except ImportError:
            pass
        try:
            import ctypes

            # PROCESS_QUERY_LIMITED_INFORMATION (0x1000) | SYNCHRONIZE (0x00100000)
            handle = ctypes.windll.kernel32.OpenProcess(0x1000 | 0x00100000, False, pid)
            if not handle:
                # If error is ERROR_ACCESS_DENIED (5), the process exists but is not accessible.
                return ctypes.windll.kernel32.GetLastError() == 5
            try:
                # 0x00000102 is WAIT_TIMEOUT, meaning the process has not terminated.
                return ctypes.windll.kernel32.WaitForSingleObject(handle, 0) == 0x00000102
            finally:
                ctypes.windll.kernel32.CloseHandle(handle)
        except Exception:
            return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _remove_stale_lock(lock_path):
    """Remove only an aged lock whose recorded owner process is gone."""
    try:
        metadata = os.stat(lock_path)
        with open(lock_path, encoding="ascii") as stream:
            owner = int(stream.read())
    except (OSError, ValueError):
        return
    if time.time() - metadata.st_mtime < _LOCK_TIMEOUT_SECONDS:
        return
    if _is_process_alive(owner):
        return
    try:
        current = os.stat(lock_path)
        if current.st_ino != metadata.st_ino or current.st_mtime != metadata.st_mtime:
            return
        os.unlink(lock_path)
    except OSError:
        pass


def acquire(path):
    lock_path = path + ".lock"
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    except OSError:
        return None
    deadline = time.monotonic() + _LOCK_TIMEOUT_SECONDS
    while True:
        try:
            handle = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            try:
                os.write(handle, str(os.getpid()).encode("ascii"))
            except OSError:
                os.close(handle)
                os.unlink(lock_path)
                return None
            return handle
        except FileExistsError:
            if time.monotonic() >= deadline:
                _remove_stale_lock(lock_path)
                return None
            time.sleep(0.01)
        except OSError:
            return None


def release(path, handle):
    if handle is None:
        return
    os.close(handle)
    try:
        os.unlink(path + ".lock")
    except OSError:
        pass
