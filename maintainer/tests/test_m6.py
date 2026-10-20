#!/usr/bin/env python3
"""The 6.0.0-m6 pass: `python maintainer/tests/test_m6.py`; test_migrate.py's load_tests runs it too, so core-verify
carries it."""
from __future__ import annotations

import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from synthetic import FLOW, GIT, git, no_auto_gc

CORE = FLOW.parents[1]
sys.path.insert(0, str(CORE / "maintainer"))
import flow  # noqa: E402

BASH = shutil.which("bash") or "bash"
POLICY = "policies/validator-free-paths.yml"
DECLARED = "schema_version: 1\nvalidator_free_paths:\n  - 'docs/**/*.md'\n"


def sh(cwd: Path, *argv: str, stdin: str | None = None, **env: str) -> subprocess.CompletedProcess:
    return subprocess.run(list(argv), cwd=cwd, input=stdin, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env={**os.environ, **env}, timeout=900)


class Project(unittest.TestCase):
    """A git project with Flow installed and committed, Claude Code's tool hooks wired and committed: the m6 fixture."""

    wire = True

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m6-"))
        self.repo = self.tmp / "project"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        no_auto_gc(self.repo)
        for key, value in (("user.name", "flow-test"), ("user.email", "flow-test@example.invalid")):
            git(self.repo, "config", key, value)
        (self.repo / "README.md").write_text("demo\n", encoding="utf-8")
        git(self.repo, "add", "README.md")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "init")  # before Flow's hooks exist
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(flow.install(self.repo, {"claude"}), 0)
        self.commit_protected(self.untracked_and_changed(), "flow: install Fusebase Flow")
        if self.wire:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(flow.install(self.repo, {"claude"}, wire_hooks=True), 0)
            git(self.repo, "add", "--", ".claude/settings.json")
            done = git(self.repo, "commit", "-q", "-m", "T1: wire Flow hooks for Claude Code")
            self.assertEqual(done.returncode, 0, done.stderr)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def untracked_and_changed(self) -> list[str]:
        out = git(self.repo, "status", "--porcelain", "--untracked-files=all").stdout.splitlines()
        return [line[3:] for line in out]

    def commit_protected(self, paths: list[str], subject: str) -> None:
        git(self.repo, "add", "--", *paths)
        mint = self.bash("hooks/local/write-bootstrap-approval.sh", FF_BOOTSTRAP_TTL_MIN="30")
        self.assertEqual(mint.returncode, 0, mint.stderr)
        done = git(self.repo, "commit", "-q", "-m", subject)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.bash("hooks/local/write-bootstrap-approval.sh", "--consume")

    def bash(self, *argv: str, **env: str) -> subprocess.CompletedProcess:
        return sh(self.repo, BASH, *argv, **env)

    def tool(self, name: str, rel: str, **tool_input: str) -> dict:
        """The decision of the wired PreToolUse command for one tool call, with the payload Claude Code sends."""
        settings = json.loads((self.repo / ".claude/settings.json").read_text(encoding="utf-8"))
        command = next(h["command"] for group in settings["hooks"]["PreToolUse"] for h in group["hooks"]
                       if "pre_tool_use.py" in h["command"])
        payload = {"session_id": "m6", "transcript_path": str(self.tmp / "t.jsonl"), "cwd": str(self.repo),
                   "hook_event_name": "PreToolUse", "tool_name": name,
                   "tool_input": {"file_path": str(self.repo / rel), **tool_input}}
        out = sh(self.repo, BASH, "-c", command, stdin=json.dumps(payload), CLAUDE_PROJECT_DIR=str(self.repo))
        return json.loads(out.stdout or "{}") | {"rc": out.returncode}

    def audit(self, event: str) -> list[dict]:
        log = self.repo / "state/audit.log.jsonl"
        lines = log.read_text(encoding="utf-8").splitlines() if log.is_file() else []
        return [r for r in map(json.loads, lines) if r.get("event") == event]


class GoAhead(Project):
    """Brief m6 item (9): one go-ahead, minted before the change, covers the agent's Edit/Write of the named
    Flow-internals paths under the wired handler and the commit of exactly those paths; the commit spends it."""

    def mint(self, *paths: str, ttl: str = "30") -> subprocess.CompletedProcess:
        # MSYS=noglob: Git Bash started from a Windows process expands a glob in its arguments before bash runs
        return self.bash("hooks/local/write-bootstrap-approval.sh", "--paths", *paths, FF_BOOTSTRAP_TTL_MIN=ttl,
                         MSYS="noglob")

    def test_one_go_ahead_lets_the_agent_edit_and_commit_the_named_policy_file_and_the_commit_spends_it(self) -> None:
        self.assertEqual(self.tool("Edit", POLICY, old_string="a", new_string="b")["flow_decision"], "deny")
        self.assertEqual(self.tool("Write", POLICY, content=DECLARED)["rc"], 2)
        mint = self.mint(POLICY)
        self.assertEqual(mint.returncode, 0, mint.stderr)
        self.assertIn("the go-ahead for 1 named path(s): policies/validator-free-paths.yml", mint.stdout)
        self.assertEqual(self.tool("Write", POLICY, content=DECLARED)["flow_decision"], "allow")
        (self.repo / POLICY).write_text(DECLARED, encoding="utf-8")
        self.assertEqual(self.tool("Edit", POLICY, old_string="docs", new_string="doc")["flow_decision"], "allow")
        for other in ("policies/protected-paths.yml", "hooks/shared/path_policy.py", "FLOW_RULES.md"):
            self.assertEqual(self.tool("Edit", other, old_string="a", new_string="b")["flow_decision"], "deny", other)
        git(self.repo, "add", "--", POLICY)
        (self.repo / "notes.md").write_text("a note\n", encoding="utf-8")
        git(self.repo, "add", "--", "notes.md")  # a path the go-ahead does not name: the commit is refused
        refused = git(self.repo, "commit", "-q", "-m", "T1: declare docs-only paths")
        self.assertNotEqual(refused.returncode, 0, "a commit touching a path the go-ahead does not name landed")
        self.assertIn("protected paths edited without exception artifact", refused.stderr)
        git(self.repo, "rm", "-q", "--cached", "--", "notes.md")
        head = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        done = git(self.repo, "commit", "-q", "-m", "T1: declare docs-only paths")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD~1").stdout.strip(), head)
        self.assertEqual(git(self.repo, "show", "--name-only", "--format=", "HEAD").stdout.split(), [POLICY])
        uses = self.audit("approval_go_ahead")
        self.assertTrue(uses and all(u["path"] == POLICY and u["artifact"].startswith("protected_path_edit-flow-bootstrap")
                                     for u in uses), uses)
        self.assertEqual(len(self.audit("approval_go_ahead_minted")), 1)
        # spent: HEAD moved, so the same go-ahead allows neither another edit nor another commit
        self.assertEqual(self.tool("Edit", POLICY, old_string="doc", new_string="docs")["flow_decision"], "deny")
        (self.repo / POLICY).write_text(DECLARED + "  - 'state/**/*.txt'\n", encoding="utf-8")
        git(self.repo, "add", "--", POLICY)
        again = git(self.repo, "commit", "-q", "-m", "T1: widen the declaration")
        self.assertNotEqual(again.returncode, 0, "a spent go-ahead let a second commit through")
        used = self.bash("hooks/local/write-bootstrap-approval.sh", "--consume")
        self.assertIn("consumed 1 'flow-bootstrap' approval artifact(s)", used.stdout)
        # the digest-bound flow, mint after staging, works as before
        self.commit_protected([POLICY], "T1: widen the declaration")
        self.assertEqual(list((self.repo / "state/approvals").glob("*.json")), [])

    def test_an_expired_or_long_lived_go_ahead_is_refused_and_the_mint_names_only_its_own_paths(self) -> None:
        self.assertEqual(self.mint(POLICY, ttl="31").returncode, 2)
        for wrong in ("policies/*.yml", "/policies/x.yml", "../policies/x.yml", "src/app.ts", ".github/workflows/x.yml"):
            out = self.mint(wrong)
            self.assertEqual(out.returncode, 2, wrong)
            self.assertIn("refused", out.stderr, wrong)
        self.assertEqual(self.mint(POLICY).returncode, 0)
        artifact = next((self.repo / "state/approvals").glob("protected_path_edit-flow-bootstrap-*.json"))
        data = json.loads(artifact.read_text(encoding="utf-8"))
        self.assertEqual((data["paths"], len(data["head_at_mint"])), ([POLICY], 40))
        self.assertNotIn("tree_digest", data)
        for expires in ("2020-01-01T00:00:00Z", "2999-01-01T00:00:00Z"):  # expired; a life past the 30-minute cap
            artifact.write_text(json.dumps(data | {"expires_at": expires}), encoding="utf-8")
            self.assertEqual(self.tool("Write", POLICY, content=DECLARED)["flow_decision"], "deny", expires)
        artifact.write_text(json.dumps(data), encoding="utf-8")
        self.assertEqual(self.tool("Write", POLICY, content=DECLARED)["flow_decision"], "allow")


if __name__ == "__main__":
    unittest.main(verbosity=2)
