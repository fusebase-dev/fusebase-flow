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


BACKLOG = """# Backlog

## B1 Magic links expire
- source: owner:2026-10-16
- criterion: A magic link older than 15 minutes signs nobody in.
- risk: {risk}
- status: open

## B2 The expiry has a unit test
- source: owner:2026-10-16
- test: test/auth.test.ts::magic link expires
- risk: none
- status: open

## B3 The banner says so
- source: owner:2026-10-16
- criterion: The sign-in page says "link expired".
- risk: none
- status: open
"""
RUN_LOG = "# Live run p1 aaa111 (dev)\n\n| Time (UTC) | Row | Record |\n|---|---|---|\n{records}"


def blank_png(width: int = 1280, height: int = 720) -> bytes:
    import struct
    import zlib

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\xff" * 3 * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


class Validator(Workspace):
    """Done check 3: a phase whose rows all hold, then one fault at a time."""

    def setUp(self) -> None:
        super().setUp()
        policy = (CORE / "policies/evidence-classes.yml").read_text(encoding="utf-8")
        self.base = commit(self.repo, {"policies/evidence-classes.yml": policy,
                                       "docs/flow/backlog.md": BACKLOG.format(risk="none"),
                                       "test/auth.test.ts": "test('magic link expires', () => {});\n"}, "init")
        write(self.repo, "docs/flow/phases.md", phases_doc(self.base, [("T1", "src/a/**"), ("T2", "test/**")])
              .replace("| T2 | B1 |", "| T2 | B2 |"))
        commit(self.repo, {"src/a/expiry.ts": "export const ttl = 15;\n"}, "T1: the expiry")
        commit(self.repo, {"test/auth.test.ts": "test('magic link expires', () => {});\n// ttl\n"}, "T2: the test")
        write(self.repo, "state/deploys/dev.jsonl", json.dumps({"env": "dev", "finished": "2026-10-18T09:00:00Z"}) + "\n")
        write(self.repo, "state/runs/P1/index.tsv", "run-1\t2026-10-18T10:00:00Z\truns/run-1\t0\n")
        write(self.repo, "runs/run-1/README.md", RUN_LOG.format(records="| 2026-10-18T10:00:00.000Z | S1 | PASS |\n"))
        write(self.repo, "runs/unit.tap", "TAP version 13\nok 1 - magic link expires\n# pass 1\n")
        self.rows = {"B1": self.capture_row("B1", "runs/run-1/S1/link.json", b'{"signed_in": false, "status": 410}\n'),
                     "B2": "| B2 | PASS | test/auth.test.ts::magic link expires | - | - | runs/unit.tap | - |"}

    def capture_row(self, item: str, rel: str, data: bytes, log: str = "runs/run-1/README.md", note: str = "-") -> str:
        (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.repo / rel).write_bytes(data)
        import hashlib
        return f"| {item} | PASS | {rel} | {hashlib.sha256(data).hexdigest()} | {len(data)} | {log} | {note} |"

    def validate(self, target: str = "P1") -> subprocess.CompletedProcess:
        head = "| Criterion | Status | Capture | sha256 | Bytes | Log | Note |\n|---|---|---|---|---|---|---|\n"
        write(self.repo, "docs/flow/evidence/P1.md", "# Evidence\n\n" + head + "".join(f"{r}\n" for r in self.rows.values()))
        return run(str(LOCAL / "validate_evidence.py"), target, "--root", str(self.repo), cwd=self.tmp)

    def assert_fails(self, item: str, text: str) -> None:
        out = self.validate()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        line = next((ln for ln in out.stdout.splitlines() if ln.startswith(f"  {item} FAIL")), "")
        self.assertIn(text, line, out.stdout)

    def test_a_phase_whose_rows_hold_passes_and_accepts_a_test_id_row_with_its_pass_marker(self) -> None:
        out = self.validate()
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("  B2 PASS (class unit, minimum unit)", out.stdout)
        self.assertRegex(out.stdout, r"capture runs/run-1/S1/link.json sha256=[0-9a-f]{64} bytes=\d+")
        self.assertIn("EVIDENCE: PASS", out.stdout)

    def test_rejects_a_blank_capture_under_the_floor(self) -> None:
        self.rows["B1"] = self.capture_row("B1", "runs/run-1/S1/page.png", blank_png())
        self.assert_fails("B1", "under the floor of 10240")

    def test_rejects_a_capture_dated_before_the_deploy_finished(self) -> None:
        write(self.repo, "state/deploys/dev.jsonl", json.dumps({"env": "dev", "finished": "2026-10-18T09:00:00Z"})
              + "\n" + json.dumps({"env": "dev", "finished": "2026-10-18T11:00:00Z"}) + "\n")
        self.assert_fails("B1", "before the dev deploy finished 2026-10-18T11:00:00Z")

    def test_rejects_two_rows_sharing_a_digest(self) -> None:
        write(self.repo, "docs/flow/phases.md", (self.repo / "docs/flow/phases.md").read_text(encoding="utf-8")
              + "| T3 | B3 | the banner | `src/b/**` | 10m 1f |\n")
        self.rows["B3"] = self.capture_row("B3", "runs/run-1/S1/copy.json", b'{"signed_in": false, "status": 410}\n')
        self.assert_fails("B1", "shares capture")
        self.assert_fails("B3", "shares capture")

    def test_rejects_a_pass_row_whose_run_log_records_a_finding(self) -> None:
        write(self.repo, "runs/run-1/README.md", RUN_LOG.format(
            records="| 2026-10-18T10:00:00.000Z | S1 | PASS |\n| 2026-10-18T10:01:00.000Z | S2 | FINDING F7: banner |\n"))
        self.assert_fails("B1", "FINDING")

    def test_rejects_a_test_id_row_whose_test_is_absent_at_head(self) -> None:
        self.rows["B2"] = self.rows["B2"].replace("magic link expires |", "magic link is revoked |")
        write(self.repo, "runs/unit.tap", "TAP version 13\nok 1 - magic link is revoked\n")
        self.assert_fails("B2", "the test is absent at HEAD")

    def test_rejects_a_test_id_row_whose_test_gained_skip_in_the_slice_diff(self) -> None:
        commit(self.repo, {"test/auth.test.ts": "test.skip('magic link expires', () => {});\n"}, "T2: skip it")
        self.assert_fails("B2", "skip or todo token was added")

    def test_rejects_a_run_log_without_the_header(self) -> None:
        write(self.repo, "runs/run-1/README.md", "# Live run p1 aaa111 (dev)\n\nS1 PASS\n")
        self.assert_fails("B1", "unrecognised run log")

    def test_reports_flaky_as_fail_for_a_pass_after_a_fail_without_a_reproduction_note(self) -> None:
        write(self.repo, "runs/run-0/README.md", RUN_LOG.format(records="| 2026-10-18T09:30:00.000Z | S1 | FAIL: 200 |\n"))
        write(self.repo, "state/runs/P1/index.tsv",
              "run-0\t2026-10-18T09:30:00Z\truns/run-0\t1\nrun-1\t2026-10-18T10:00:00Z\truns/run-1\t0\n")
        self.assert_fails("B1", "FLAKY: run run-0 recorded a FAIL")
        self.rows["B1"] = self.rows["B1"][:-4] + " repro: a stale build served run-0 |"
        self.assertEqual(self.validate().returncode, 0)

    def test_the_minimum_class_follows_the_touched_paths(self) -> None:
        policy = (CORE / "policies/evidence-classes.yml").read_text(encoding="utf-8").replace("  ui: []", "  ui: ['test/**']")
        commit(self.repo, {"policies/evidence-classes.yml": policy}, "chore: T9 declare the ui globs")
        self.assert_fails("B2", "unit evidence, under the minimum smoke")
        self.assertNotIn("no globs declared", self.validate().stdout)

    def test_a_risk_line_changed_inside_its_slice_window_is_a_flag(self) -> None:
        write(self.repo, "docs/flow/backlog.md", BACKLOG.format(risk="auth"))
        out = self.validate()
        self.assertIn("FLAG item-edit B1: risk changed since the phase's base", out.stdout)
        self.assertIn("  B1 PASS (class live, minimum live)", out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
