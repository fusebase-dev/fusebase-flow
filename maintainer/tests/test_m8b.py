#!/usr/bin/env python3
"""The 6.0.0-m8 pass, part two (test_m8.py stays under its 800 lines): the m7 reviews' findings (items 8 and 9).
`python maintainer/tests/test_m8b.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

import yaml

import test_m7
from synthetic import git

CORE = Path(__file__).resolve().parents[2]
WINDOWS = os.name == "nt"
sys.path[:0] = [str(CORE / "maintainer"), str(CORE / "hooks"), str(CORE / "hooks/local"), str(CORE / "hooks/local/lib")]


def inherited(base: type) -> dict:
    """The base class's tests set to None here: they run in the base's own module."""
    return dict.fromkeys(n for n in dir(base) if n.startswith("test"))



class RangeReviewA(test_m7.RangeCheck):
    """m7 review A #1..#4: what the pre-push and pre-merge-commit range check let through."""

    locals().update(inherited(test_m7.RangeCheck))

    def push(self, branch: str) -> subprocess.CompletedProcess:
        return self.git("push", "origin", branch, ok=False)

    def refused(self, out: subprocess.CompletedProcess, what: str) -> None:
        self.assertNotEqual(out.returncode, 0, f"{what} reached the remote")
        self.assertIn("secret pattern aws_access_key_id", out.stderr)

    def test_a_branch_older_than_the_upgrade_is_judged_at_push(self) -> None:
        # A#1: a branch cut from the history the install found never carries the check's mark, so it went unjudged
        self.git("checkout", "-q", "-b", "old", "main")
        self.commit("config/old.txt", f"aws_access_key_id = {self.KEY}\n", "T1: an old branch's settings", "--no-verify")
        self.git("checkout", "-q", "work")
        self.refused(self.push("old"), "a token on a branch older than the install")

    def test_a_line_starting_with_two_pluses_and_an_octopus_merges_own_line_are_scanned(self) -> None:
        # A#2: in the diff such a line reads `+++...`, which the check took for a file header
        self.git("checkout", "-q", "-b", "plus", "work")
        self.commit("docs/a.md", f"++aws_access_key_id = {self.KEY}\n", "T1: a doubled plus", "--no-verify")
        self.refused(self.push("plus"), "a token on a `++` line")
        for n in (1, 2):
            self.git("checkout", "-q", "-b", f"b{n}", "work")
            self.commit(f"docs/b{n}.md", f"{n}\n", f"T{n + 1}: note {n}", "--no-verify")
        self.git("checkout", "-q", "-b", "octo", "work")
        self.git("merge", "--no-ff", "--no-commit", "b1", "b2")
        (self.repo / "docs/b1.md").write_text(f"1\naws_access_key_id = {self.KEY}\n", encoding="utf-8")
        self.git("add", "--", "docs/b1.md")
        self.git("commit", "-q", "--no-verify", "-m", "T4: merge the notes")  # three parents: its own line is `+++`
        self.assertEqual(len(self.git("log", "-1", "--format=%P").stdout.split()), 3)
        self.refused(self.push("octo"), "a token an octopus merge added")



class StagedScanHeaders(unittest.TestCase):
    """m7 review A #2, the pre-commit's half: the staged secret scan dropped every `+++` line as a file header, so a
    staged line starting `++` was never scanned."""

    def test_a_staged_line_starting_with_two_pluses_is_scanned_and_the_headers_are_not(self) -> None:
        from shared.staged_secret_scan import added_lines
        diff = ("diff --git a/x.md b/x.md\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/x.md\n"
                "@@ -0,0 +1,2 @@\n+++token = 1\n+plain\ndiff --git a/y.md b/y.md\n--- a/y.md\n+++ b/y.md\n"
                "@@ -1 +1 @@\n-old\n+new\n")
        self.assertEqual(added_lines(diff).split("\n"), ["++token = 1", "plain", "new"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
