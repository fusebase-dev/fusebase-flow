#!/usr/bin/env python3
"""The 6.0.0-m7 pass: `python maintainer/tests/test_m7.py`; test_migrate.py's load_tests runs it too, so core-verify
carries it."""
from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import test_m6

CORE = Path(__file__).resolve().parents[2]
WINDOWS = os.name == "nt"


def short_name(path: Path) -> str:
    """The 8.3 alias of an existing path (Windows), or the path as given when the volume makes none."""
    import ctypes
    buf = ctypes.create_unicode_buffer(1024)
    n = ctypes.windll.kernel32.GetShortPathNameW(str(path), buf, len(buf))
    return buf.value if 0 < n < len(buf) else str(path)


class ToolTimePaths(test_m6.Project):
    """m7 item 1: the wired PreToolUse handler judges the path git names, whatever spelling the tool sends: an 8.3
    short name, another case, `..`, `./`, a symlink, a path relative to the session's folder, NotebookEdit's
    notebook_path. Before, `Path(target).relative_to(root)` raised on any of them and the edit was allowed."""

    def decide(self, name: str, tool_input: dict, cwd: str | None = None) -> str:
        settings = json.loads((self.repo / ".claude/settings.json").read_text(encoding="utf-8"))
        command = next(h["command"] for group in settings["hooks"]["PreToolUse"] for h in group["hooks"]
                       if "pre_tool_use.py" in h["command"])
        payload = {"session_id": "m7", "cwd": cwd or str(self.repo), "hook_event_name": "PreToolUse",
                   "tool_name": name, "tool_input": tool_input}
        out = test_m6.sh(self.repo, test_m6.BASH, "-c", command, stdin=json.dumps(payload),
                         CLAUDE_PROJECT_DIR=str(self.repo))
        decision = json.loads(out.stdout or "{}").get("flow_decision")
        self.assertEqual(out.returncode, 2 if decision == "deny" else 0, out.stderr)
        return decision

    def test_dot_dot_dot_slash_relative_and_notebook_forms_of_a_protected_file_are_denied(self) -> None:
        (self.repo / "src").mkdir()
        for form in ("src/../policies/command-policy.yml", "./policies/command-policy.yml",
                     str(self.repo / "src" / ".." / "FLOW_RULES.md"), str(self.repo / "." / "hooks/shared/path_policy.py")):
            self.assertEqual(self.decide("Write", {"file_path": form, "content": "x\n"}), "deny", form)
        self.assertEqual(self.decide("Edit", {"file_path": "../FLOW_RULES.md", "old_string": "a", "new_string": "b"},
                                     cwd=str(self.repo / "src")), "deny", "a path relative to the session's folder")
        self.assertEqual(self.decide("NotebookEdit", {"notebook_path": str(self.repo / "hooks/shared/probe.ipynb"),
                                                      "new_source": "x = 1"}), "deny", "NotebookEdit's notebook_path")
        self.assertEqual(self.decide("Write", {"file_path": "src/app.ts", "content": "x\n"}), "allow")
        self.assertEqual(self.decide("Write", {"file_path": "policies/x.yml", "content": "x\n"},
                                     cwd=str(self.repo / "src")), "allow", "src/policies/x.yml is no Flow file")

    @unittest.skipUnless(WINDOWS, "8.3 short names and case-blind paths are Windows'")
    def test_an_8_3_short_name_and_another_case_of_a_protected_file_are_denied(self) -> None:
        target = self.repo / "policies" / "command-policy.yml"
        short = short_name(target)
        forms = [str(target).upper(), str(target).lower()]
        if short != str(target):
            forms.insert(0, short)
        else:
            print("\n[m7] this volume makes no 8.3 names here; the short-name form is GoAheadShortTemp's")
        for form in forms:
            self.assertEqual(self.decide("Edit", {"file_path": form, "old_string": "a", "new_string": "b"}), "deny", form)
        self.assertEqual(self.decide("Write", {"file_path": str(self.repo / "notes.md").upper(), "content": "x\n"}),
                         "allow")

    def test_a_symlinked_path_to_a_protected_file_is_denied(self) -> None:
        link = self.repo / "linked"
        try:
            os.symlink(self.repo / "policies", link, target_is_directory=True)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(f"no symlink here ({exc})")
        self.assertEqual(self.decide("Write", {"file_path": str(link / "command-policy.yml"), "content": "x\n"}), "deny")
        self.assertEqual(self.decide("Write", {"file_path": "linked/command-policy.yml", "content": "x\n"}), "deny")


@unittest.skipUnless(WINDOWS, "an 8.3 temp folder is Windows' (the runner's C:\\Users\\RUNNER~1)")
class GoAheadShortTemp(test_m6.GoAhead):
    """The three test_m6.GoAhead tests with TMP and TEMP at an 8.3 alias, as on GitHub's Windows runner (core-verify
    run 39487718435): the payload names the project by its short name, git by its long one."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.long = Path(tempfile.mkdtemp(prefix="flow-m7-a-folder-with-a-long-name-"))
        cls.short = short_name(cls.long)
        if cls.short == str(cls.long):
            shutil.rmtree(cls.long, ignore_errors=True)
            raise unittest.SkipTest("this volume makes no 8.3 names")

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.long, ignore_errors=True)

    def setUp(self) -> None:
        self.saved = tempfile.tempdir
        tempfile.tempdir = self.short
        try:
            super().setUp()
        finally:
            tempfile.tempdir = self.saved
        self.assertNotEqual(str(self.repo), str(self.repo.resolve()), "the project is not spelled by its 8.3 name")


if __name__ == "__main__":
    unittest.main(verbosity=2)
