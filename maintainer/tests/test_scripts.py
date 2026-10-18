#!/usr/bin/env python3
"""Milestone 3 fixtures: the policy, the six scripts in hooks/local/ and the upgrade within 6.0.

`python maintainer/tests/test_scripts.py`; test_migrate.py's load_tests runs it too, so core-verify carries it.
Every fixture works on files and git only: no audit line, no provider hook wired.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import yaml

from synthetic import FLOW, GIT, git

CORE = FLOW.parents[1]
LOCAL = CORE / "hooks/local"
STATUS = re.compile(r"^flow: (running|idle) last=\S+Z hooks: claude (wired|unenforced), codex (wired|unenforced) "
                    r"alerts=\d+ reader=\S+Z$")


def run(*args: str, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, *args], cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=900)


class Workspace(unittest.TestCase):
    """A fresh git repository per test, removed afterwards."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m3-"))
        self.repo = self.tmp / "project"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)


class Policy(Workspace):
    def test_evidence_classes_parses_with_the_decided_values(self) -> None:
        doc = yaml.safe_load((CORE / "policies/evidence-classes.yml").read_text(encoding="utf-8"))
        self.assertEqual(doc["classes"], {"auth": [], "data": [], "ui": [], "deploy_config": []})
        self.assertEqual(doc["trivial"], {"docs_only": [], "test": [], "copy": []})
        self.assertEqual(doc["vendored_paths"], ["_core", "_web"])
        self.assertEqual(doc["finding_marker"], "^FINDING ")
        self.assertEqual(doc["run_log_header"], "| Time (UTC) | Row | Record |")
        status = re.compile(doc["row_status"])
        for good in ("PASS", "FAIL: the link signed someone in", "BLOCKED-AT-approval-g8-account"):
            self.assertTrue(status.match(good), good)
        for bad in ("PARTIAL", "FAIL", "pass", "BLOCKED-AT-"):
            self.assertFalse(status.match(bad), bad)
        self.assertTrue(re.match(doc["test_pass_marker"], "ok 12 - magic link expires"))
        self.assertEqual(doc["capture_min_bytes"], {"image": 10240, "other": 32})
        approval = yaml.safe_load((CORE / "policies/approval-policy.yml").read_text(encoding="utf-8"))
        self.assertEqual(approval["gate_rounds"], 2)

    def test_install_writes_the_ignore_block_once_and_a_second_run_leaves_it(self) -> None:
        (self.repo / ".gitignore").write_bytes(b"node_modules/\r\n.env\r\n")
        first = run(str(FLOW), "install", "--target", str(self.repo), cwd=self.tmp)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertIn(".gitignore (block updated)", first.stdout)
        text = (self.repo / ".gitignore").read_bytes()
        self.assertTrue(text.startswith(b"node_modules/\r\n.env\r\n"), "the project's lines stay first, byte for byte")
        self.assertEqual(text.count(b"# FLOW:BEGIN ignore"), 1)
        self.assertNotIn(b"\n", text.replace(b"\r\n", b""), "the file keeps its CRLF line endings")
        probes = "state/approvals/probe.yml\nstate/audit/probe.log\nhooks/shared/__pycache__/x.pyc\nstate/approvals/.gitkeep\n"
        ignored = subprocess.run(["git", "check-ignore", "--stdin"], cwd=self.repo, input=probes.encode(),
                                 capture_output=True).stdout.decode().split()
        self.assertEqual(ignored, ["state/approvals/probe.yml", "state/audit/probe.log", "hooks/shared/__pycache__/x.pyc"])
        second = run(str(FLOW), "install", "--target", str(self.repo), cwd=self.tmp)
        self.assertIn(".gitignore (block current)", second.stdout)
        self.assertEqual((self.repo / ".gitignore").read_bytes(), text)

    def test_install_refuses_an_ignore_block_without_its_end_marker(self) -> None:
        (self.repo / ".gitignore").write_text("dist/\n# FLOW:BEGIN ignore (old)\nstate/audit/*\n", encoding="utf-8")
        before = (self.repo / ".gitignore").read_bytes()
        out = run(str(FLOW), "install", "--target", str(self.repo), cwd=self.tmp)
        self.assertEqual(out.returncode, 2, out.stdout)
        self.assertIn(".gitignore line 2", out.stdout)
        self.assertEqual((self.repo / ".gitignore").read_bytes(), before)
        self.assertFalse((self.repo / "audit/flow-install.json").exists(), "nothing written")


if __name__ == "__main__":
    unittest.main(verbosity=2)
