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


class Reader(Workspace):
    """Done check 1: files and git only; no audit line exists in any of these repositories."""

    def quiet_project(self, beats: dict[str, str], age_min: float) -> None:
        """Every signal two hours old except the heartbeat files, written `age_min` minutes ago."""
        old = int(time.time()) - 7200
        env = {**os.environ, "GIT_COMMITTER_DATE": f"@{old} +0000", "GIT_AUTHOR_DATE": f"@{old} +0000"}
        subprocess.run([*GIT, "commit", "-q", "--allow-empty", "-m", "init"], cwd=self.repo, env=env, check=True)
        if (self.repo / ".git/index").exists():
            os.utime(self.repo / ".git/index", (old, old))
        folder = self.repo / "state/audit/liveness"
        folder.mkdir(parents=True)
        for name, text in beats.items():
            (folder / name).write_text(text, encoding="utf-8")
            stamp = time.time() - age_min * 60
            os.utime(folder / name, (stamp, stamp))

    def once(self) -> subprocess.CompletedProcess:
        out = run(str(LOCAL / "reader.py"), "--once", "--root", str(self.repo), cwd=self.tmp)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertFalse((self.repo / "state/audit.log.jsonl").exists(), "the fixture has no audit line")
        line = (self.repo / "state/status.line").read_text(encoding="utf-8")
        self.assertRegex(line.rstrip("\n"), STATUS)
        self.assertTrue(line.endswith("\n") and line.count("\n") == 1, "one line")
        return out

    def test_a_gap_past_the_silence_threshold_alerts(self) -> None:
        self.quiet_project({"npm-test-4242-1.hb": "bounded-run npm test deadline=3600s\nrunning 10/3600\n"}, 31)
        out = self.once()
        self.assertIn("ALERT silence-", out.stdout)
        self.assertIn(" alerts=1 ", (self.repo / "state/status.line").read_text(encoding="utf-8"))
        self.assertNotIn("npm test", out.stdout + (self.repo / "state/reader/last.json").read_text(encoding="utf-8"),
                         "a label is hashed, never printed")

    def test_a_gap_under_the_threshold_stays_quiet(self) -> None:
        self.quiet_project({"npm-test-4242-1.hb": "bounded-run npm test deadline=3600s\nrunning 10/3600\n"}, 29)
        out = self.once()
        self.assertNotIn("ALERT", out.stdout)
        self.assertIn("flow: running ", out.stdout)
        self.assertIn(" alerts=0 ", out.stdout)

    def test_finished_heartbeats_with_old_activity_read_as_idle(self) -> None:
        self.quiet_project({"build-7-1.hb": "bounded-run build deadline=600s\ndone rc=0 12s\n"}, 120)
        out = self.once()
        self.assertIn("flow: idle ", out.stdout)
        self.assertNotIn("ALERT", out.stdout)

    def test_the_same_command_hash_three_times_in_flight_is_logged_uncalibrated(self) -> None:
        beat = "bounded-run vitest run deadline=900s\nrunning 20/900\n"
        self.quiet_project({f"vitest-{pid}-1.hb": beat for pid in (101, 202, 303)}, 1)
        out = self.once()
        record = json.loads((self.repo / "state/reader/last.json").read_text(encoding="utf-8"))
        self.assertEqual([g["kind"] for g in record["logged"]], ["repeat"])
        self.assertIn("UNCALIBRATED", out.stdout)
        self.assertRegex(out.stdout, r"LOG repeat-[0-9a-f]{12}: the same command hash 3 times")
        self.assertEqual(record["counters"]["in_flight"], 3)
        two = {f"vitest-{pid}-1.hb": beat for pid in (101, 202)}
        shutil.rmtree(self.repo / "state")
        self.quiet_project(two, 1)
        self.assertNotIn("LOG repeat", self.once().stdout, "two in flight stay under the seed")

    def test_two_runs_with_nothing_changed_keep_the_counters(self) -> None:
        self.quiet_project({"npm-test-4242-1.hb": "bounded-run npm test deadline=3600s\nrunning 10/3600\n"}, 45)
        self.once()
        first = json.loads((self.repo / "state/reader/last.json").read_text(encoding="utf-8"))
        self.once()
        second = json.loads((self.repo / "state/reader/last.json").read_text(encoding="utf-8"))
        self.assertEqual(first["counters"], second["counters"])
        self.assertEqual(first["counters"]["alerts_raised"], 1)

    def test_register_reader_prints_and_records_the_line_and_plain_install_registers_nothing(self) -> None:
        sys.path.insert(0, str(CORE / "maintainer"))
        import flow
        calls: list[list[str]] = []
        with mock.patch.object(flow, "register_reader", side_effect=lambda argv: calls.append(argv) or (0, "")):
            plain = io.StringIO()
            with contextlib.redirect_stdout(plain):
                self.assertEqual(flow.install(self.repo, {"claude", "codex"}), 0)
            self.assertEqual(calls, [])
            self.assertNotIn("reader", json.loads((self.repo / "audit/flow-install.json").read_text("utf-8")))
            registered = io.StringIO()
            with contextlib.redirect_stdout(registered):
                self.assertEqual(flow.install(self.repo, {"claude", "codex"}, register=True), 0)
        self.assertEqual(len(calls), 1)
        record = json.loads((self.repo / "audit/flow-install.json").read_text("utf-8"))["reader"]
        self.assertIn(record["line"], registered.getvalue())
        self.assertIn("hooks/local/reader.py", record["line"].replace("\\", "/"))
        self.assertIn("--once", record["line"])


TIER = "schema_version: 1\ntrivial:\n  docs_only: ['docs/notes/**']\n  test: []\n  copy: []\n"


def commit(repo: Path, files: dict[str, str], message: str) -> str:
    for rel, text in files.items():
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (repo / rel).write_text(text, encoding="utf-8", newline="\n")
        git(repo, "add", "--", rel)
    out = subprocess.run([*GIT, "commit", "-q", "--allow-empty", "-F", "-"], cwd=repo, input=message.encode("utf-8"),
                         capture_output=True)
    assert out.returncode == 0, out.stderr
    return git(repo, "rev-parse", "HEAD").stdout.strip()


def phases_doc(base: str, rows: list[tuple[str, str]], slice_id: str = "P1-S1") -> str:
    table = "".join(f"| {tid} | B1 | does {tid} | `{globs}` | 30m 2f |\n" for tid, globs in rows)
    return (f"# Phases\n- reference: none\n\n## P1 First phase\n- base: {base}\n\n### {slice_id} The slice\n"
            f"| Task | Item | Does | Globs | Estimate |\n|---|---|---|---|---|\n{table}")


def write(repo: Path, rel: str, text: str) -> None:
    (repo / rel).parent.mkdir(parents=True, exist_ok=True)
    (repo / rel).write_text(text, encoding="utf-8", newline="\n")


class Done(Workspace):
    """Done check 2."""

    def setUp(self) -> None:
        super().setUp()
        self.base = commit(self.repo, {"policies/evidence-classes.yml": TIER, "README.md": "x\n"}, "init")
        write(self.repo, "docs/flow/phases.md", phases_doc(self.base, [("T1", "src/a/**"), ("T2", "src/b/**"),
                                                                     ("T3", "src/c/**")]))

    def done(self) -> subprocess.CompletedProcess:
        return run(str(LOCAL / "done.py"), "P1-S1", "--root", str(self.repo), cwd=self.tmp)

    def returns(self, tasks: dict[str, str]) -> None:
        write(self.repo, "state/returns/P1-S1.json", json.dumps({
            "slice": "P1-S1", "role": "builder", "started": "2026-10-18T10:00:00Z", "finished": "2026-10-18T11:00:00Z",
            "tasks": [{"id": k, "sha": v} for k, v in tasks.items()], "tool_calls": 40, "blocked_at": None,
            "notes": ""}))

    def test_body_mentions_trivial_tier_commits_and_commits_outside_the_globs_leave_tasks_open(self) -> None:
        commit(self.repo, {"src/a/one.ts": "1\n"}, "feat(a): the first part\n\nT1 lives here")
        commit(self.repo, {"src/a/two.ts": "2\n"}, "plan: T1 the plan")
        t2 = commit(self.repo, {"docs/notes/b.md": "b\n"}, "T2: a note")
        t3 = commit(self.repo, {"src/z/c.ts": "c\n"}, "T3: in the wrong folder")
        self.returns({"T2": t2, "T3": t3})
        out = self.done()
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn("T1 OPEN: no commit carries it alone in its subject", out.stdout)
        self.assertIn("T2 OPEN: only trivial-tier commits carry it", out.stdout)
        self.assertIn("T3 OPEN: its commits touch none of its globs", out.stdout)
        record = json.loads((self.repo / "state/done/P1-S1.json").read_text(encoding="utf-8"))
        self.assertEqual((record["committed"], record["open"]), ({}, ["T1", "T2", "T3"]))

    def test_every_id_committed_inside_its_globs_is_done(self) -> None:
        shas = {t: commit(self.repo, {f"src/{d}/x.ts": t}, f"feat({d}): {t} the {d} part")
                for t, d in (("T1", "a"), ("T2", "b"), ("T3", "c"))}
        self.returns(shas)
        out = self.done()
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("DONE: PASS", out.stdout)
        record = json.loads((self.repo / "state/done/P1-S1.json").read_text(encoding="utf-8"))
        self.assertEqual(record["committed"], shas)

    def test_a_missing_returns_file_is_a_failure(self) -> None:
        for t, d in (("T1", "a"), ("T2", "b"), ("T3", "c")):
            commit(self.repo, {f"src/{d}/x.ts": t}, f"{t}: the {d} part")
        out = self.done()
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn("returns: state/returns/P1-S1.json is missing", out.stdout)

    def test_a_returns_file_naming_a_sha_not_on_the_branch_is_a_failure(self) -> None:
        git(self.repo, "checkout", "-q", "-b", "side")
        stray = commit(self.repo, {"src/a/side.ts": "s\n"}, "T1: on another branch")
        git(self.repo, "checkout", "-q", "main")
        shas = {t: commit(self.repo, {f"src/{d}/x.ts": t}, f"{t}: the {d} part") for t, d in (("T1", "a"), ("T2", "b"),
                                                                                                  ("T3", "c"))}
        self.returns({**shas, "T1": stray})
        out = self.done()
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn(f"T1: {stray[:12]} is not a commit on this branch", out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
