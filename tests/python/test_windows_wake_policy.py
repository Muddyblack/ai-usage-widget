"""Windows idle SIGINT wake policy — static invariants without PySide6 (task 30).

The plan gates any change to the 250 ms wake timer on a measured idle
CPU/battery benefit on Windows. That measurement is not possible here (this is
a Linux host and PySide6 is not installed), so the outcome is a documented
no-change decision. These tests lock the *invariants* a future change must not
break: Ctrl+C still quits the app, the wake timer is a no-op tick, and the
headless path returns before the GUI loop is entered.
"""

import ast
import unittest
from pathlib import Path

from _support import REPO  # noqa: F401  (ensures TOOLS is on sys.path)

WINDOWS_APP = Path(REPO) / "windows" / "app.py"


def _main_ast():
    tree = ast.parse(WINDOWS_APP.read_text(encoding="utf-8"), filename=str(WINDOWS_APP))
    main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
    return main, tree


def _calls_in(node):
    """Every ``Call`` node under ``node``, in source order."""
    return [child for child in ast.walk(node) if isinstance(child, ast.Call)]


def _called_name(call):
    func = call.func
    if isinstance(func, ast.Attribute):
        return f"{_dotted(func.value)}.{func.attr}"
    if isinstance(func, ast.Name):
        return func.id
    return ""


def _dotted(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return f"{_dotted(node.value)}.{node.attr}"
    return ""


class WakeTimerInvariantsTest(unittest.TestCase):
    def setUp(self):
        self.main, _ = _main_ast()
        self.calls = _calls_in(self.main)

    def test_ctrl_c_still_quits_the_app(self):
        """A SIGINT handler must still call app.quit()."""
        handlers = []
        for node in ast.walk(self.main):
            if isinstance(node, ast.Call) and _called_name(node) == "signal.signal":
                if node.args and isinstance(node.args[0], ast.Attribute) and node.args[0].attr == "SIGINT":
                    handlers.append(node)
        self.assertEqual(len(handlers), 1, "exactly one SIGINT handler expected")
        body = handlers[0].args[1]
        quit_calls = [c for c in ast.walk(body) if isinstance(c, ast.Call) and "quit" in _called_name(c)]
        self.assertTrue(quit_calls, "the SIGINT handler must quit the app")

    def test_the_wake_tick_is_a_no_op(self):
        """The timer exists only to let Python run the handler between bytecodes."""
        starts = [c for c in self.calls if _called_name(c) == "wake.start"]
        self.assertEqual(len(starts), 1, "exactly one wake timer start expected")
        connects = [c for c in self.calls if _called_name(c) == "wake.timeout.connect"]
        self.assertEqual(len(connects), 1, "the wake timer must have one tick target")
        target = connects[0].args[0]
        # The connected lambda/function must not touch state: its whole job is
        # to return, which gives the interpreter a chance to run the handler.
        if isinstance(target, ast.Lambda):
            self.assertIsInstance(target.body, ast.Constant)
            self.assertIsNone(target.body.value)

    def test_headless_returns_before_the_gui_loop(self):
        """The selftest/screenshot path must not install the wake timer."""
        source = ast.unparse(self.main)
        headless_return = source.index("return _run_headless")
        wake_start = source.index("wake.start")
        self.assertLess(headless_return, wake_start)

    def test_shutdown_still_flushes_and_exits(self):
        names = {_called_name(c) for c in self.calls}
        self.assertIn("_flush_stdio", names)
        self.assertIn("os._exit", names)


if __name__ == "__main__":
    unittest.main()
