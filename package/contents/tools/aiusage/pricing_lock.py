import os
import time

_LOCK_TIMEOUT_SECONDS = 30


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
    try:
        os.kill(owner, 0)
    except ProcessLookupError:
        try:
            current = os.stat(lock_path)
            if current.st_ino != metadata.st_ino or current.st_mtime != metadata.st_mtime:
                return
            os.unlink(lock_path)
        except OSError:
            pass
    except PermissionError:
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
