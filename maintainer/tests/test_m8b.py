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


if __name__ == "__main__":
    unittest.main(verbosity=2)
