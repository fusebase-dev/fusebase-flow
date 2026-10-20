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
import time
import unittest
from pathlib import Path
from unittest import mock

import test_scripts as m3
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


class FlakyScope(m3.Validator):
    """m6 list item 1 (M6-22): the flaky check reads the earlier runs of this run's own phase. Onboarding's P6 index
    carries phase 5's runs in their own folder; phase 5's S6 FAIL there flagged phase 6's S6."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_a_fail_in_a_run_another_phase_carried_into_this_index_is_not_flaky_and_one_in_this_phase_is(self) -> None:
        fail = m3.RUN_LOG.format(records="| 2026-10-18T09:30:00.000Z | S1 | FAIL: 200 |\n")
        m3.write(self.repo, "runs/carry-over/p0-run/README.md", fail)
        index = "p0-run\t2026-10-18T09:30:00Z\truns/carry-over/p0-run\t1\nrun-1\t2026-10-18T10:00:00Z\truns/run-1\t0\n"
        m3.write(self.repo, "state/runs/P1/index.tsv", index)
        out = self.validate()
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("  B1 PASS", out.stdout)
        m3.write(self.repo, "runs/run-0/README.md", fail)
        m3.write(self.repo, "state/runs/P1/index.tsv", index + "run-0\t2026-10-18T09:40:00Z\truns/run-0\t1\n")
        self.assert_fails("B1", "FLAKY: run run-0 recorded a FAIL")


class GatePass(m3.Validator):
    """m6 list item 2 (M6-23): the gate's PASS line names the readers workflows/lifecycle.md gives the target: one review
    reader for a slice; two skeptics, then the verdict reader, for a phase, never per slice."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))

    def setUp(self) -> None:
        super().setUp()
        sha = dict(ln.split(" ", 1)[::-1] for ln in git(self.repo, "log", "--format=%H %s").stdout.splitlines())
        m3.write(self.repo, "state/returns/P1-S1.json", json.dumps({
            "slice": "P1-S1", "role": "builder", "started": "2026-10-18T10:00:00Z", "finished": "2026-10-18T11:00:00Z",
            "tasks": [{"id": "T1", "sha": sha["T1: the expiry"]}, {"id": "T2", "sha": sha["T2: the test"]}],
            "tool_calls": 40, "blocked_at": None, "notes": ""}))
        self.validate()  # writes the evidence file

    def gate(self, target: str) -> str:
        out = m3.run(str(m3.LOCAL / "gate.py"), target, "--root", str(self.repo), cwd=self.tmp)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        return out.stdout.strip().splitlines()[-1]

    def test_a_slice_dispatches_its_review_and_a_phase_its_skeptics_then_its_verdict(self) -> None:
        self.assertEqual(self.gate("P1-S1"),
                         "GATE: PASS: dispatch the review (python hooks/local/slice.py P1-S1 --brief review)")
        self.assertEqual(self.gate("P1"), "GATE: PASS: dispatch the two skeptics, then the verdict "
                                          "(python hooks/local/slice.py P1 --brief skeptic, then verdict)")
        lifecycle = (CORE / "workflows/lifecycle.md").read_text(encoding="utf-8")
        self.assertIn("Review: one reader with `python hooks/local/slice.py <slice> --brief review`", lifecycle)
        self.assertIn("Phase gate: one verdict reader and two skeptic readers, never per slice", lifecycle)


class ReviewRounds(m3.Gate):
    """m6 list item 3: the ledger has a record kind for a review round, and the gate counts review rounds beside the
    verdict rounds, each against gate_rounds (the verify skill: review rounds share the limit, own counter)."""

    locals().update(dict.fromkeys(n for n in dir(m3.Gate) if n.startswith("test")))
    REVIEW = "2026-10-18T09:00Z review P1-S1 result=FAIL agent=r0 -- the banner shows twice\n"

    def test_review_records_are_counted_on_their_own_counter_and_exhaust_the_rounds(self) -> None:
        template = (CORE / "templates/ledger.md").read_text(encoding="utf-8")
        self.assertIn("review  <slice>          result=PASS|FAIL agent=<reader agent id>", template)
        m3.write(self.repo, "docs/flow/ledger.md", "## Records\n" + self.REVIEW + m3.VERDICTS.splitlines()[0] + "\n")
        out = self.gate()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("1 of 2 verdict rounds and 1 of 2 review rounds used", out.stdout)
        m3.write(self.repo, "docs/flow/ledger.md", "## Records\n" + self.REVIEW + self.REVIEW.replace("r0", "r1"))
        out = self.gate()
        self.assertEqual(out.returncode, 3, out.stdout + out.stderr)
        self.assertIn("BLOCKED-AT-gate-budget: 2 reviews recorded for P1-S1, gate_rounds 2", out.stdout)
        self.assertIn("review 1 FAIL: the banner shows twice", out.stdout)

    def test_a_next_or_handoff_bullet_that_says_review_is_no_round(self) -> None:
        """m6-fix F1 (review B #2): only a line that starts with its record time counts."""
        template = (CORE / "templates/ledger.md").read_text(encoding="utf-8")
        ledger = template.replace("## Next\n-\n", "## Next\n- review P1-S1 again once T2 lands\n").replace(
            "## Handoff\n-\n", "## Handoff\n- review P1-S1 found the banner twice; T2 fixes it\n")
        m3.write(self.repo, "docs/flow/ledger.md", ledger.replace("## Records\n", "## Records\n" + self.REVIEW))
        out = self.gate()
        self.assertNotEqual(out.returncode, 3, out.stdout)
        self.assertIn("0 of 2 verdict rounds and 1 of 2 review rounds used", out.stdout)


class CommitStages(Project):
    """m6 list item 4 (M6-25): the git hooks keep each stage's time where the planner reads it afterwards."""

    wire = False

    def test_each_stage_of_a_commit_is_kept_in_state_audit_with_its_time_and_parent(self) -> None:
        stages = self.repo / "state/audit/commit-stages.tsv"
        stages.unlink(missing_ok=True)
        parent = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        (self.repo / "src.txt").write_text("a change\n", encoding="utf-8")
        git(self.repo, "add", "--", "src.txt")
        done = git(self.repo, "commit", "-q", "-m", "T1: a change")
        self.assertEqual(done.returncode, 0, done.stderr)
        rows = [line.split("\t") for line in stages.read_text(encoding="utf-8").splitlines()]
        self.assertEqual([r[2:4] for r in rows], [["pre-commit", "secret-scan"], ["pre-commit", "protected-paths"],
                                                  ["pre-commit", "module-size"], ["pre-commit", "validators"],
                                                  ["commit-msg", "validators"]], rows)
        for when, head, _, _, seconds in rows:
            self.assertRegex(when, r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
            self.assertEqual(head, parent)
            self.assertRegex(seconds, r"^\d+\.\d\d$")
        self.assertIn("state/audit/commit-stages.tsv", git(self.repo, "check-ignore", "state/audit/commit-stages.tsv").stdout)


class PlannerCalls(m3.Validator):
    """m6 list item 4 (M6-25): every audit line of a completed call carries its agent_id, and checks.py counts the
    planner's own calls (no agent_id) in the slice's window."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))

    def test_post_tool_use_marks_each_call_and_checks_counts_the_planners_in_the_window(self) -> None:
        for rel in ("hooks/shared", "hooks/handlers", "policies"):
            shutil.copytree(CORE / rel, self.repo / rel, ignore=shutil.ignore_patterns("__pycache__"), dirs_exist_ok=True)
        for agent in ("builder-1", None):
            event = {"hook_event_name": "PostToolUse", "cwd": str(self.repo), "tool_name": "Read", "tool_use_id": "t1",
                     "tool_input": {"file_path": str(self.repo / "README.md")}, **({"agent_id": agent} if agent else {})}
            sh(self.repo, sys.executable, str(self.repo / "hooks/handlers/post_tool_use.py"), stdin=json.dumps(event))
        lines = [json.loads(x) for x in (self.repo / "state/audit.log.jsonl").read_text(encoding="utf-8").splitlines()]
        self.assertEqual([(x["tool_name"], x["agent_id"]) for x in lines], [("Read", "builder-1"), ("Read", None)])
        m3.write(self.repo, "state/returns/P1-S1.json", json.dumps({
            "slice": "P1-S1", "role": "builder", "started": "2026-10-18T10:00:00Z", "finished": "2026-10-18T11:00:00Z",
            "tasks": [], "tool_calls": 40, "blocked_at": None, "notes": ""}))
        call = '{{"ts":"{}","event":"post_tool_use","tool_name":"Read","agent_id":{}}}\n'
        m3.write(self.repo, "state/audit.log.jsonl", "".join(call.format(ts, agent) for ts, agent in (
            ("2026-10-18T09:59:59Z", "null"), ("2026-10-18T10:00:00Z", "null"), ("2026-10-18T10:30:00Z", '"b1"'),
            ("2026-10-18T10:45:00Z", "null"), ("2026-10-18T11:00:01Z", "null"))))
        out = m3.run(str(m3.LOCAL / "checks.py"), "P1-S1", "--root", str(self.repo), cwd=self.tmp)
        self.assertIn("LOG planner-calls check 3 -: 2 planner tool calls from the slice's start to its finish", out.stdout)
        (self.repo / "state/audit.log.jsonl").unlink()
        out = m3.run(str(m3.LOCAL / "checks.py"), "P1-S1", "--root", str(self.repo), cwd=self.tmp)
        self.assertNotIn("planner-calls", out.stdout, "no audit line, nothing to count from")


class OneCommitAtATime(Project):
    """m6 list item 5: the planner and the builders share one work tree and one git index; every commit goes through
    hooks/local/commit.py, which takes the repository's Flow commit lock and commits only its named files."""

    wire = False

    def start(self, subject: str, rel: str, **env: str) -> subprocess.Popen:
        (self.repo / rel).write_text(f"{subject}\n", encoding="utf-8")
        return subprocess.Popen([sys.executable, "hooks/local/commit.py", "-m", subject, rel], cwd=self.repo,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env={**os.environ, **env})

    def test_a_planner_commit_waits_for_a_builder_commit_and_neither_takes_the_others_files(self) -> None:
        (self.repo / "src.ts").write_text("export const a = 1;\n", encoding="utf-8")
        git(self.repo, "add", "--", "src.ts")  # a builder's staged change, not committed yet
        lock = self.repo / ".git/index.lock"
        lock.write_bytes(b"")  # a git process holds the index
        (self.repo / "docs/flow").mkdir(parents=True, exist_ok=True)
        (self.repo / "docs/flow/ledger.md").write_text("status: x\n", encoding="utf-8")
        plain = git(self.repo, "add", "--", "docs/flow/ledger.md")
        self.assertIn("index.lock", plain.stderr)  # the collision the field saw
        waiting = self.start("plan: a ledger record", "docs/flow/ledger.md")
        time.sleep(3)
        self.assertIsNone(waiting.poll(), "commit.py did not wait for the index lock")
        lock.unlink()
        out = waiting.communicate(timeout=900)[0].decode("utf-8", "replace")
        self.assertEqual(waiting.returncode, 0, out)
        self.assertIn("waiting: a git process (index.lock) holds the repository", out)
        self.assertEqual(git(self.repo, "show", "--name-only", "--format=", "HEAD").stdout.split(), ["docs/flow/ledger.md"])
        self.assertEqual(git(self.repo, "diff", "--cached", "--name-only").stdout.split(), ["src.ts"], "still staged")
        head = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        slow = self.start("T1: a builder's task", "src.ts", FUSEBASE_FLOW_LINT="sleep 8")  # lint runs in commit-msg
        time.sleep(2)
        fast = self.start("plan: another ledger record", "docs/flow/ledger.md")
        outs = [p.communicate(timeout=900)[0].decode("utf-8", "replace") for p in (slow, fast)]
        self.assertEqual([slow.returncode, fast.returncode], [0, 0], outs)
        self.assertIn("waiting: another Flow commit", outs[1])
        log = git(self.repo, "log", "--format=%s", f"{head}..HEAD").stdout.splitlines()
        self.assertEqual(log, ["plan: another ledger record", "T1: a builder's task"])
        self.assertFalse((self.repo / ".git/flow-commit.lock").exists())


class OwnGate(m3.Slicer):
    """m6 list item 6: an item whose criterion depends on the gate of its own phase is refused where the plan's items
    are checked before dispatch (slice.py, beside BLOCKED-AT-input). Onboarding's B4 (phase 6): "the phase 7 args
    start from release-1-spec at the phase 6 gate commit"."""

    locals().update(dict.fromkeys(n for n in dir(m3.Slicer) if n.startswith("test")))

    def test_a_criterion_naming_its_own_phases_gate_blocks_and_another_phases_gate_does_not(self) -> None:
        criterion = '- criterion: A magic link older than 15 minutes shows "link expired" and signs nobody in.'
        self.assertIn(criterion, m3.SLICE_BACKLOG)
        for text, blocked in (("the phase 1 gate commit", True), ("P1's gate", True), ("the gate of P1", True),
                              ("gate.py P1", True), ("state/gate/P1.txt", True), ("the P0 gate commit", False),
                              ("the phase 11 gate", False), ("a gateway", False)):
            m3.write(self.repo, "docs/flow/backlog.md", m3.SLICE_BACKLOG.replace(criterion, f"{criterion[:-1]}, at {text}."))
            out = self.slice("T1")
            self.assertEqual((out.returncode, "BLOCKED-AT-criterion: T1 serves B1" in out.stdout), (3, True) if blocked
                             else (0, False), f"{text}: {out.stdout}")


FAKE_SCHEDULER = r'''import os, sys
tool, args = sys.argv[1], sys.argv[2:]
with open(os.path.join(os.environ["FAKE_SCHED_DIR"], "calls.txt"), "a", encoding="utf-8") as fh:
    fh.write(" ".join([tool, *args]) + "\n")
if tool == "crontab":
    sys.stdout.write(os.environ.get("FAKE_CRONTAB", ""))
    sys.exit(0)
status = os.environ.get("FAKE_TASK_STATUS", "missing")
if status == "missing":
    sys.stderr.write("ERROR: The system cannot find the file specified.\n")
    sys.exit(1)
sys.stdout.write(f"\nFolder: \\\nHostName:                             HOST\nTaskName:                             \\{args[2]}\n"
                 f"Next Run Time:                        N/A\nStatus:                               {status}\n"
                 f"Scheduled Task State:                 {'Disabled' if status == 'Disabled' else 'Enabled'}\n")
'''


class ReaderState(Project):
    """m6 list item 7: health reports the reader from the scheduler's own state, read-only, never from the install
    record alone (WorkHub: "health reports 'reader scheduled' while the task is disabled"). Fakes only: a guard fails
    the test before any real schtasks or crontab could run."""

    wire = False

    def setUp(self) -> None:
        super().setUp()
        self.bin = self.tmp / "fake-bin"
        self.bin.mkdir()
        (self.bin / "fake_sched.py").write_text(FAKE_SCHEDULER, encoding="utf-8")
        for name in ("schtasks", "crontab"):
            (self.bin / f"{name}.bat").write_text(f'@"{sys.executable}" "{self.bin / "fake_sched.py"}" {name} %*\r\n',
                                                  encoding="utf-8", newline="")
            (self.bin / name).write_text(f'#!/bin/sh\nexec "{sys.executable}" "{self.bin / "fake_sched.py"}" {name} "$@"\n',
                                         encoding="utf-8", newline="\n")
            (self.bin / name).chmod(0o755)
        patcher = mock.patch.dict(os.environ, {"PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                                               "FAKE_SCHED_DIR": str(self.tmp)})
        patcher.start()
        self.addCleanup(patcher.stop)
        import health
        self.health, real = health, health.subprocess.run

        def guarded(argv, *args, **kwargs):
            if Path(argv[0]).stem.lower() in ("crontab", "schtasks") and Path(argv[0]).parent != self.bin:
                raise AssertionError(f"the real scheduler would be asked: {argv[0]}")
            return real(argv, *args, **kwargs)
        guard = mock.patch.object(health.subprocess, "run", guarded)
        guard.start()
        self.addCleanup(guard.stop)

    def reader_line(self, record: dict) -> str:
        manifest = json.loads((self.repo / flow.MANIFEST).read_text(encoding="utf-8"))
        (self.repo / flow.MANIFEST).write_text(json.dumps({**manifest, "reader": record}), encoding="utf-8")
        return next(line for line in self.health.report(self.repo)[1] if line.startswith("reader:"))

    def test_health_asks_the_scheduler_and_reports_a_disabled_or_deleted_task(self) -> None:
        name = "FuseBase Flow reader project-0123abcd"
        task = {"line": subprocess.list2cmdline(["schtasks", "/Create", "/F", "/SC", "MINUTE", "/MO", "5", "/TN", name,
                                                 "/TR", '"pythonw.exe" "reader.py" --once']), "registered": True}
        for status, said in (("Ready", "the task is Ready"), ("Disabled", "the task is Disabled"),
                             ("missing", f"schtasks has no task {name!r} (deleted)")):
            os.environ["FAKE_TASK_STATUS"] = status
            self.assertEqual(self.reader_line(task), f"reader: registered by install; the scheduler says: {said}")
        self.assertIn(f"schtasks /Query /TN {name} /FO LIST /V", (self.tmp / "calls.txt").read_text(encoding="utf-8"))
        cron = {"line": f"*/5 * * * * cd {flow.sh_quote(str(self.repo))} && 'python3' {flow.READER_RUN}", "registered": True}
        for listed, said in ((cron["line"] + "\n", "in the crontab"), ("# " + cron["line"] + "\n", "NOT in the crontab")):
            os.environ["FAKE_CRONTAB"] = listed
            self.assertIn(said, self.reader_line(cron))
        calls = (self.tmp / "calls.txt").read_text(encoding="utf-8").split()
        self.assertNotIn("/Create", calls, "health only asks")


class StateValidatorFree(Project):
    """m6 list item 8: Flow's records under state/ skip lint and typecheck with no declaration, except the extensions a
    lint covers (M6-24); a declared glob that matches lint-covered files at HEAD warns (M6-16). Through the installed
    hooks, with the project's lint red."""

    wire = False
    RED = {"FUSEBASE_FLOW_LINT": "echo lint-ran >&2; false"}

    def commit(self, rel: str, text: str = "x\n") -> subprocess.CompletedProcess:
        (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.repo / rel).write_text(text, encoding="utf-8")
        git(self.repo, "add", "--", rel)
        return sh(self.repo, *GIT, "commit", "-q", "-m", "T1: a record", **self.RED)

    def test_state_records_skip_lint_by_default_a_json_there_does_not_and_a_wide_glob_warns(self) -> None:
        for rel in ("state/gate/P1.txt", "state/runs/P1/index.tsv"):
            done = self.commit(rel)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("validator-free by default", done.stderr)
            self.assertNotIn("lint-ran", done.stderr)
        refused = self.commit("state/done/P1-S1.json", "{}\n")
        self.assertNotEqual(refused.returncode, 0, "a .json under state/ skipped the lint that covers it")
        self.assertIn("lint-ran", refused.stdout + refused.stderr, refused.stdout)
        git(self.repo, "rm", "-q", "--cached", "--", "state/done/P1-S1.json")
        (self.repo / "docs").mkdir(exist_ok=True)
        (self.repo / "docs/data.json").write_text("{}\n", encoding="utf-8")
        (self.repo / POLICY).write_text("schema_version: 1\nvalidator_free_paths:\n  - 'docs/**'\n", encoding="utf-8")
        self.commit_protected([POLICY, "docs/data.json"], "T1: declare the docs")
        done = self.commit("docs/notes.md")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("WARNING: policies/validator-free-paths.yml declares 'docs/**' validator-free, and it matches 1 "
                      "file(s) a lint covers (docs/data.json)", done.stderr)


class BaselineSplit(Project):
    """m6 list item 9 (M6-15): Flow's policies/module-size-baseline.txt holds the core's rows only; the project's rows
    live in policies/module-size-baseline.project.txt, which hooks/shared/module_size.py reads beside it. An upgraded
    project's `821 hooks/local/upgrade.sh` row (the 5.x core's) is dropped, a live project row moves."""

    wire = False

    def test_an_upgrade_moves_the_project_rows_out_and_drops_the_5x_row_then_health_stays_quiet(self) -> None:
        base, own = flow.BASELINE, flow.PROJECT_BASELINE
        core = (CORE / base).read_bytes().replace(b"\r\n", b"\n")
        (self.repo / "src").mkdir()
        (self.repo / "src/big.ts").write_text("export const a = 1;\n" * 900, encoding="utf-8")
        (self.repo / base).write_bytes(core + b"821 hooks/local/upgrade.sh\n900 src/big.ts\n")  # as an m5 upgrade left it
        self.commit_protected([base, "src/big.ts"], "T1: the project's monolith, frozen")
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(flow.install(self.repo, {"claude"}), 0)
        self.assertIn(f"{own} (the project's own: 1 rows from {base})", out.getvalue())
        self.assertEqual((self.repo / base).read_bytes(), core)
        self.assertEqual((self.repo / own).read_bytes(), flow.PROJECT_HEADER + b"900 src/big.ts\n")
        self.commit_protected(self.untracked_and_changed(), "flow: upgrade Fusebase Flow")  # flow_owned.py accepts it
        import health
        rc, lines = health.report(self.repo)
        self.assertIn("HEALTH: healthy", lines[-1], lines)
        (self.repo / own).write_bytes(flow.PROJECT_HEADER)  # the project drops its own row
        self.commit_protected([own], "T1: the monolith is split, its row goes")
        rc, lines = health.report(self.repo)
        self.assertEqual((rc, [x for x in lines if own in x]), (0, []), lines)
        again = sh(self.repo, sys.executable, str(FLOW), "install", "--target", str(self.repo), "--providers", "claude")
        self.assertEqual(again.returncode, 0, again.stdout)
        self.assertEqual(git(self.repo, "status", "--porcelain").stdout, "", "a re-run changed a file")
        (self.repo / "src/big.ts").write_text("export const a = 1;\n" * 950, encoding="utf-8")  # past the ceiling again
        adopt = self.bash("hooks/local/check-module-size.sh", "--write-baseline")
        self.assertIn(f"baseline-path: {own}", adopt.stdout, adopt.stderr)
        self.assertIn("FR-07 approval minted", adopt.stdout, adopt.stderr)
        self.assertEqual((self.repo / base).read_bytes(), core, "--write-baseline rewrote Flow's file")
        git(self.repo, "add", "--", "src/big.ts")
        done = git(self.repo, "commit", "-q", "-m", "T1: the monolith grows, adopted")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("950 src/big.ts", (self.repo / own).read_text(encoding="utf-8"))
        self.bash("hooks/local/write-bootstrap-approval.sh", "--consume")


class OrphanBackups(unittest.TestCase):
    """m6 list item 10 (M6-17, O-32 (c)): the migration removes the 5.x repair backups whose file is gone or goes with
    it, under .claude/, .agents/ and .codex/, `.pre-flow-repair` and `.pre-flow-repair.<n>` alike; one beside a file
    that stays is left. Backed up, listed in the dry run, and the migration commit lands. One migration, shared."""

    ORPHANS = {".claude/skills/old/SKILL.md.pre-flow-repair": "old\n",
               ".agents/skills/old/SKILL.md.pre-flow-repair.1": "old\n",
               ".codex/agents/old.toml.pre-flow-repair": "old = 1\n"}
    KEPT = {".claude/skills/mine/SKILL.md": "---\nname: mine\n---\n",
            ".claude/skills/mine/SKILL.md.pre-flow-repair": "---\nname: mine\n---\nbefore\n"}

    @classmethod
    def setUpClass(cls) -> None:
        from synthetic import migrate, scratch_clone
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        cls.clone = scratch_clone(cls.tmp, {**cls.ORPHANS, **cls.KEPT})
        cls.dry = migrate(cls.clone, "--providers", "claude,codex")
        cls.applied = migrate(cls.clone, "--providers", "claude,codex", "--apply", "--go-ahead")

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_the_migration_removes_the_orphans_and_keeps_a_backup_whose_file_stays(self) -> None:
        dry, run, clone = self.dry, self.applied, self.clone
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        self.assertIn("orphan 5.x backups: 3 (", dry.stdout)
        self.assertNotIn(".claude/skills/old/", dry.stdout.split("never touch")[1].split("keep (")[0])
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("committed: ", run.stdout)
        for rel in self.ORPHANS:
            self.assertFalse((clone / rel).exists(), rel)
            self.assertTrue(next(clone.glob(".flow-migrate-*")).joinpath(rel).is_file(), f"{rel} not backed up")
        for rel in self.KEPT:
            self.assertTrue((clone / rel).is_file(), rel)
        deleted = git(clone, "show", "--name-only", "--diff-filter=D", "--format=", "HEAD").stdout.split()
        self.assertLessEqual(set(self.ORPHANS), set(deleted))
        self.assertEqual(git(clone, "status", "--porcelain").stdout, "")

    def test_the_guidance_after_the_migration_makes_the_gate_the_planners_and_one_item_per_evidence_row(self) -> None:
        """m6 list item 11: Onboarding's carried plan modelled the gate as a builder task."""
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        ledger = (self.clone / "docs/flow/ledger.md").read_text(encoding="utf-8")
        for text in (self.applied.stdout, ledger):
            self.assertIn("one backlog item per evidence row", text)
            self.assertIn("the gate is the planner's own step (gate.py and the verify skill), never a task for a "
                          "builder", text)
        plan = (CORE / "flow-skills/plan/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("one item per evidence row it needs", plan)
        self.assertIn("the gate is your step (verify)", plan)


if __name__ == "__main__":
    unittest.main(verbosity=2)
