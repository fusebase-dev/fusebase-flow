#!/usr/bin/env python3
"""The 6.0.0-m4 micro-pass fixtures: the commit-msg interpreter (O-19) and the CLI's checkpoint subjects (O-20).

`python maintainer/tests/test_commits.py`; test_migrate.py's load_tests runs it too, so core-verify carries it.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

import test_scripts as m3
from test_core import MSG_BACKLOG
from test_scripts import CORE, Workspace, write

PHASES = ("# Phases\n- reference: none\n\n## P1 First\n- base: pending\n\n### P1-S1 The slice\n"
          "| Task | Item | Does | Globs | Estimate |\n|---|---|---|---|---|\n| T1 | B1 | the sign-in | `src/**` | 30m 2f |\n")
# The CLI's own subjects: update-git-checkpoint.ts, `toLocaleString(undefined, {dateStyle: "medium", timeStyle:
# "medium"})`; en-US carries U+202F before PM under Node's ICU.
CLI_SUBJECTS = ("chore(update): pre app update (Oct 18, 2026, 7:51:03\u202fPM)",
                "chore(update): post app update (18.10.2026, 19:51:03)")


class Interpreter(Workspace):
    """O-19: commit-msg finds Python as the pre-commit does (python3, then python, then py -3), and a missing PyYAML is
    one Flow line, never a traceback."""

    def setUp(self) -> None:
        super().setUp()
        for rel in ("hooks/local/lib/commit_msg.py", "hooks/local/lib/flow_docs.py"):
            write(self.repo, rel, (CORE / rel).read_text(encoding="utf-8"))
        m3.git(self.repo, "add", "--", "hooks")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        real = shutil.which("git")
        if os.name == "nt":  # git.exe's own folder (Git\cmd) holds no Python; a native git is found only by its .exe
            self.path = os.pathsep.join([str(self.bin), str(Path(real).parent)])
        else:  # /usr/bin holds python3 too: a folder with git alone
            os.symlink(real, self.bin / "git")
            self.path = str(self.bin)

    def shim(self, name: str, *flags: str) -> None:
        """`name` runs this Python; `py` drops the -3 it is called with."""
        drop = '[ "$1" = "-3" ] && shift\n' if name == "py" else ""
        exe = Path(sys.executable).as_posix()
        (self.bin / name).write_text(f'#!/bin/sh\n{drop}exec "{exe}" {" ".join(flags)} "$@"\n', encoding="utf-8",
                                     newline="\n")
        (self.bin / name).chmod(0o755)

    def hook(self, subject: str) -> subprocess.CompletedProcess:
        (self.tmp / "msg.txt").write_text(subject + "\n", encoding="utf-8")
        return subprocess.run([shutil.which("bash"), str(CORE / "hooks/git/commit-msg"), str(self.tmp / "msg.txt")],
                              cwd=self.repo, env={**os.environ, "PATH": self.path}, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=600)

    def no_python3(self) -> None:
        found = subprocess.run([shutil.which("bash"), "-c", "command -v python3"], env={**os.environ, "PATH": self.path},
                               capture_output=True, text=True, timeout=600)
        self.assertEqual(found.stdout.strip(), "", "python3 must not be on the test's PATH")

    def test_python_alone_or_py_alone_checks_the_subject(self) -> None:
        for name in ("python", "py"):
            for old in self.bin.glob("py*"):
                old.unlink()
            self.shim(name)
            self.no_python3()
            good = self.hook("T1: the sign-in")
            self.assertEqual(good.returncode, 0, f"{name}: {good.stderr}")
            bad = self.hook("docs: a note")
            self.assertEqual(bad.returncode, 1, name)
            self.assertIn("must cite a T-number", bad.stderr, name)

    def test_a_missing_pyyaml_is_one_block_line_that_names_the_fix(self) -> None:
        self.shim("python3", "-S")  # no site-packages: PyYAML cannot be imported
        if subprocess.run([sys.executable, "-S", "-c", "import yaml"], capture_output=True).returncode == 0:
            self.skipTest("PyYAML importable without site-packages")
        out = self.hook("T1: the sign-in")
        self.assertEqual(out.returncode, 1)
        self.assertNotIn("Traceback", out.stderr)
        lines = out.stderr.strip().splitlines()
        self.assertEqual(len(lines), 1, out.stderr)
        self.assertIn("[fusebase-flow:commit-msg] BLOCK", lines[0])
        self.assertIn("-m pip install -r hooks/requirements.txt", lines[0])


class Checkpoint(Workspace):
    """O-20: the FuseBase CLI's two update checkpoint subjects pass on the committed policy alone; nothing wider does."""

    def setUp(self) -> None:
        super().setUp()
        self.policy = (CORE / "policies/evidence-classes.yml").read_text(encoding="utf-8")
        m3.commit(self.repo, {"policies/evidence-classes.yml": self.policy, "docs/flow/backlog.md": MSG_BACKLOG,
                              "docs/flow/phases.md": PHASES, "src/a.ts": "export const a = 1;\n"}, "init")

    def verdict(self, subject: str) -> subprocess.CompletedProcess:
        write(self.repo, "src/a.ts", "export const a = 2;\n")  # the CLI's `git add -A`: a project file
        m3.git(self.repo, "add", "--", "src/a.ts")
        (self.tmp / "msg.txt").write_text(subject + "\n", encoding="utf-8")
        return m3.run(str(CORE / "hooks/local/lib/commit_msg.py"), str(self.tmp / "msg.txt"), cwd=self.repo)

    def test_the_two_cli_subjects_pass_and_a_near_miss_or_a_local_widening_does_not(self) -> None:
        for subject in CLI_SUBJECTS:
            out = self.verdict(subject)
            self.assertEqual(out.returncode, 0, f"{subject}: {out.stderr}")
        wide = "exempt_subjects: ['^chore\\(update\\): .*$']\n"
        write(self.repo, "policies/evidence-classes.local.yml", wide)
        write(self.repo, "policies/evidence-classes.yml", self.policy.replace("exempt_subjects:", wide + "unused:"))
        m3.git(self.repo, "add", "--", "policies/evidence-classes.yml")  # staged and in the working tree, not at HEAD
        for subject in ("chore(update): something else", "chore(update): pre app update",
                        "chore(update): pre app update (Oct 18, 2026) and more", "chore: pre app update (Oct 18, 2026)"):
            out = self.verdict(subject)
            self.assertEqual(out.returncode, 1, f"{subject} passed")
            self.assertIn("must cite a T-number", out.stderr, subject)


if __name__ == "__main__":
    unittest.main(verbosity=2)
