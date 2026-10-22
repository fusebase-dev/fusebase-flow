#!/usr/bin/env python3
"""The 6.0.0-m8 fix pass (review B held the tag: the command gate let through commands 6.0.0-m7 denied).
`python maintainer/tests/test_m8c.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

CORE = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(CORE / "hooks")]
from shared import shell_view  # noqa: E402
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

BS = chr(92)  # a backslash, so no escape in this file is read twice


def decision(command: str) -> str:
    reset_cache()
    return evaluate(command, root=CORE).decision


class Gate(unittest.TestCase):
    def assert_denied(self, *commands: str) -> None:
        self.assertEqual([c for c in commands if decision(c) != "deny"], [], "allowed, though the line runs it")

    def assert_allowed(self, *commands: str) -> None:
        self.assertEqual([c for c in commands if decision(c) != "allow"], [], "denied, though the words are data")


class FailsClosed(Gate):
    """Review B H1: an error in the parser let the command run. view() caught three exception types, chr() raised on
    `$'\\U00110000'`, and the hook's exit 1 is non-blocking (run-handler.sh). Any error now means the raw text is
    judged, and the hook prints a decision on every path."""

    def test_any_parser_error_judges_the_raw_text(self) -> None:
        with mock.patch.object(shell_view, "parse", side_effect=KeyError("an error the parser never planned for")):
            self.assert_denied("rm -rf /tmp/h1-monkeypatched")
            self.assert_allowed("ls /tmp/h1-monkeypatched")

    def test_a_code_point_past_unicode_judges_the_line(self) -> None:
        self.assert_denied(f"echo $'{BS}U00110000'; rm -rf /tmp/x", f"X=$'{BS}UFFFFFFFF' fusebase deploy",
                           f"echo $'{BS}U7FFFFFFF' && git commit --no-verify -m x")
        self.assert_allowed(f"echo $'{BS}U00110000'")

    def test_the_hook_prints_a_deny_when_it_fails(self) -> None:
        spec = importlib.util.spec_from_file_location("pre_tool_use_h1", CORE / "hooks/handlers/pre_tool_use.py")
        handler = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(handler)
        with tempfile.TemporaryDirectory() as folder:  # no git root: nothing is written
            event = json.dumps({"tool_name": "Bash", "cwd": folder, "tool_input": {"command": "ls"}})
            out = io.StringIO()
            with mock.patch.object(handler, "evaluate_command", side_effect=RuntimeError("an error on the way")), \
                    mock.patch("sys.stdin", io.StringIO(event)), contextlib.redirect_stdout(out), \
                    contextlib.redirect_stderr(io.StringIO()):
                rc = handler.main()
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(out.getvalue())["flow_decision"], "deny")


if __name__ == "__main__":
    unittest.main(verbosity=2)
