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

from synthetic import FLOW, GIT, git, no_auto_gc

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
        no_auto_gc(self.repo)

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

    def test_hooks_read_wired_only_when_pre_tool_use_is_registered_and_exists(self) -> None:
        """6.0.0-m7 item 4 (T322): the settings are parsed; a PreToolUse command must name the handler, which exists."""
        self.quiet_project({}, 1)
        write(self.repo, ".claude/settings.json", '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": '
              '[{"type": "command", "command": "python hooks/handlers/pre_tool_use.py"}]}]}}')
        self.assertIn("hooks: claude unenforced, codex unenforced", self.once().stdout)
        write(self.repo, "hooks/handlers/pre_tool_use.py", "")
        write(self.repo, ".codex/hooks.json", '{"note": "see hooks/handlers/pre_tool_use.py", "hooks": {}}')
        self.assertIn("hooks: claude wired, codex unenforced", self.once().stdout)

    def test_register_reader_prints_and_records_the_line_and_plain_install_registers_nothing(self) -> None:
        sys.path.insert(0, str(CORE / "maintainer"))
        import flow
        calls: list[list[str]] = []
        with mock.patch.object(flow, "register_reader", side_effect=lambda argv, target: calls.append(argv) or (0, "")):
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

    def test_a_blocked_at_row_with_an_owner_answer_passes_the_gate_and_is_never_pass(self) -> None:
        """Item 5 of brief m5: BLOCKED-AT-<reason> citing an A<n> that backlog.md has is accepted, listed as blocked."""
        sha = dict(ln.split(" ", 1)[::-1] for ln in git(self.repo, "log", "--format=%H %s").stdout.splitlines())
        write(self.repo, "state/returns/P1-S1.json", json.dumps({
            "slice": "P1-S1", "role": "builder", "started": "2026-10-18T10:00:00Z", "finished": "2026-10-18T11:00:00Z",
            "tasks": [{"id": "T1", "sha": sha["T1: the expiry"]}, {"id": "T2", "sha": sha["T2: the test"]}],
            "tool_calls": 40, "blocked_at": None, "notes": ""}))
        self.rows["B2"] = "| B2 | BLOCKED-AT-owner-account | - | - | - | - | the account is the owner's: A1 |"
        for answers, rc in (("", 1), ("\n## Answers\n\n### A2 Other\n- answered: 2026-10-19\n> No.\n", 1),
                            ("\n## Answers\n\n### A1 Whose account?\n- answered: 2026-10-19\n> The owner's.\n", 0)):
            write(self.repo, "docs/flow/backlog.md", BACKLOG.format(risk="none") + answers)
            self.validate()  # writes the evidence file
            out = run(str(LOCAL / "gate.py"), "P1", "--root", str(self.repo), cwd=self.tmp)
            self.assertEqual(out.returncode, rc, out.stdout)
            self.assertNotIn("  B2 PASS", out.stdout)
        self.assertIn("  B1 PASS", out.stdout)
        for text in (out.stdout, (self.repo / "state/gate/P1.txt").read_text(encoding="utf-8")):
            self.assertIn("  B2 BLOCKED-AT-owner-account: accepted by owner answer A1, not PASS", text)
            self.assertIn("EVIDENCE: BLOCKED (0 of 2 criteria fail; 1 blocked, accepted by an owner answer: B2 (A1))", text)
            self.assertIn("GATE: PASS: dispatch the two skeptics, then the verdict (python hooks/local/slice.py P1 "
                          "--brief skeptic, for each skeptic; then python hooks/local/slice.py P1 --brief verdict); blocked, "
                          "accepted by an owner answer, not PASS: B2 BLOCKED-AT-owner-account (A1)", text)

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
        self.rows["B1"] = self.rows["B1"][:-4] + " reproduced 1/1 (run-0): a stale build served it |"
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


CHECKS_BACKLOG = "# Backlog\n\n## B1 Sign-in\n- source: owner:2026-10-16\n- criterion: It works.\n- risk: none\n" \
                 "- status: open\n- inputs:\n  - dep:zod\n"
CHECKS_TIER = "schema_version: 1\ntrivial:\n  docs_only: ['docs/notes/**']\n  test: ['test/**']\n  copy: []\n" \
              "vendored_paths: [_core, _web]\n"
BLOCK = "".join(f"export function step{n}(value: number): number {{ return value * {n} + {n * 7}; }}\n" for n in range(25))


class Checks(Workspace):
    """Done check 4: each flag fires once and stays quiet once, on files and git only."""

    def setUp(self) -> None:
        super().setUp()
        self.base = commit(self.repo, {"policies/evidence-classes.yml": CHECKS_TIER, "docs/flow/backlog.md": CHECKS_BACKLOG,
                                       "package.json": '{"name": "app", "dependencies": {}}\n',
                                       "src/a/one.ts": BLOCK}, "init")
        self.globs = "src/a/**`, `package.json`, `tsconfig.json`, `test/**"
        self.estimate = "30m 2f"
        self.plan()

    def plan(self) -> None:
        write(self.repo, "docs/flow/phases.md", phases_doc(self.base, [("T1", self.globs)])
              .replace("| 30m 2f |", f"| {self.estimate} |"))

    def at(self, when: str, files: dict[str, str], subject: str = "T1: work") -> None:
        env = {**os.environ, "GIT_COMMITTER_DATE": when, "GIT_AUTHOR_DATE": when}
        for rel, text in files.items():
            write(self.repo, rel, text)
            git(self.repo, "add", "--", rel)
        subprocess.run([*GIT, "commit", "-q", "-m", subject], cwd=self.repo, env=env, check=True)

    def returns(self, calls: object = 40, started: str = "2026-10-18T10:00:00Z") -> None:
        write(self.repo, "state/returns/P1-S1.json", json.dumps({
            "slice": "P1-S1", "role": "builder", "started": started, "finished": "2026-10-18T12:00:00Z",
            "tasks": [], "tool_calls": calls, "blocked_at": None, "notes": ""}))

    def checks(self, *extra: str) -> str:
        out = run(str(LOCAL / "checks.py"), *(extra or ("P1-S1",)), "--root", str(self.repo), cwd=self.tmp)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        return out.stdout

    def kinds(self, text: str, word: str = "FLAG") -> list[str]:
        return re.findall(rf"^  {word} (\S+?)(?:-[0-9a-f]{{8}})? check", text, re.M)

    def test_scope_fires_on_a_new_file_outside_the_globs_and_stays_quiet_inside(self) -> None:
        self.returns()
        self.at("2026-10-18T10:10:00Z", {"src/a/two.ts": "export const a = 1;\n"})
        out = self.checks()
        self.assertNotIn("new", self.kinds(out))
        self.assertIn("breadth: T1 `src/a/**` matches 2 files at HEAD", out)
        self.at("2026-10-18T10:20:00Z", {"src/z/stray.ts": "export const z = 1;\n"})
        out = self.checks()
        self.assertEqual(self.kinds(out), ["new"])
        rows = (self.repo / "state/flags/P1-S1.tsv").read_text(encoding="utf-8").splitlines()
        self.assertEqual(rows[0], "id\tcheck\ttask\tevidence\truling")
        self.assertRegex(rows[1], r"^new-[0-9a-f]{8}\t1\tT1\tsrc/z/stray.ts is under no task glob of the slice\t$")

    def test_dependency_and_config_fire_and_stay_quiet_with_both_exemptions_logged(self) -> None:
        self.returns()
        self.at("2026-10-18T10:10:00Z", {"package.json": '{"name": "app", "dependencies": {"zod": "3.23.8"}}\n',
                                         "tsconfig.json": '{"compilerOptions": {"strict": true, // on\n},}\n',
                                         "test/env.test.ts": "const t = process.env.TEST_TOKEN;\n"})
        out = self.checks()
        self.assertEqual(self.kinds(out), [], out)
        self.assertEqual(sorted(self.kinds(out, "LOG")), ["cfg", "cfg", "env"], out)
        self.at("2026-10-18T10:20:00Z", {
            "package.json": '{"name": "app", "engines": {"node": "22"}, "dependencies": {"zod": "3.23.8", "left-pad": '
                            '"1.3.0"}}\n', "src/a/env.ts": "export const url = process.env.API_URL;\n"})
        out = self.checks()
        self.assertEqual(sorted(self.kinds(out)), ["cfg", "dep", "env"], out)
        self.assertIn("left-pad, named by no item of the slice", out)
        self.assertIn("API_URL, read in src/a/env.ts", out)

    def test_budget_minutes_and_files_fire_past_2x_and_stay_quiet_under(self) -> None:
        self.returns()
        self.at("2026-10-18T10:50:00Z", {"src/a/two.ts": "1\n", "src/a/three.ts": "1\n", "src/a/four.ts": "1\n",
                                         "test/a.test.ts": "1\n"})
        self.assertEqual(self.kinds(self.checks()), [])
        self.estimate = "20m 1f"
        self.plan()
        self.assertEqual(sorted(self.kinds(self.checks())), ["files", "minutes"])

    def test_a_no_commit_span_of_201_calls_flags_and_199_does_not(self) -> None:
        self.at("2026-10-18T10:10:00Z", {"src/a/two.ts": "1\n"})
        self.returns({"total": 400, "before_first_work": 20, "between_commits": [199, 12]})
        self.assertEqual(self.kinds(self.checks()), [])
        self.returns({"total": 400, "before_first_work": 20, "between_commits": [201, 12]})
        self.assertEqual(self.kinds(self.checks()), ["no-commit-calls"])

    def test_orientation_of_136_calls_flags_and_134_does_not(self) -> None:
        self.at("2026-10-18T10:10:00Z", {"src/a/two.ts": "1\n"})
        self.returns({"total": 300, "before_first_work": 134, "between_commits": [40]})
        self.assertEqual(self.kinds(self.checks()), [])
        self.returns({"total": 300, "before_first_work": 136, "between_commits": [40]})
        self.assertEqual(self.kinds(self.checks()), ["before-work-calls"])

    def test_redundancy_fires_on_a_copied_block_and_stays_quiet_on_new_code_and_vendored_copies(self) -> None:
        self.returns()
        self.globs += "`, `_core/**"
        self.plan()
        self.at("2026-10-18T10:10:00Z", {"_core/copy.ts": BLOCK, "src/a/new.ts": BLOCK.replace("value", "input")
                                         .replace("return", "const r =")})
        self.assertEqual(self.kinds(self.checks()), [])
        self.at("2026-10-18T10:20:00Z", {"src/a/copy.ts": BLOCK})
        out = self.checks()
        self.assertEqual(self.kinds(out), ["dup"])
        self.assertRegex(out, r"src/a/copy.ts:1 repeats (_core/copy|src/a/one).ts:1, 25 lines")

    def test_a_trivial_tier_slice_runs_no_scope_or_redundancy_flag(self) -> None:
        self.returns()
        self.at("2026-10-18T10:10:00Z", {"docs/notes/a.md": "a note\n", "docs/notes/b.md": BLOCK})
        out = self.checks()
        self.assertIn("trivial tier: yes (no flag 1 or 4, no rubric)", out)
        self.assertEqual(self.kinds(out), [])
        self.assertNotIn("breadth:", out)

    def test_precision_reproduces_a_hand_count(self) -> None:
        write(self.repo, "state/flags/P1-S1.tsv", "id\tcheck\ttask\tevidence\truling\n"
              "new-00000001\t1\tT1\ta\tupheld\nnew-00000002\t1\tT1\tb\tupheld\nnew-00000003\t1\tT2\tc\trejected\n"
              "outside-00000004\t1\tT2\td\t\ndup-00000005\t4\tT1\te\trejected\n")
        out = self.checks("--precision", "P1-S1")
        self.assertEqual(out.splitlines(), ["check 1: 2 upheld, 1 rejected, 1 open, precision 67%",
                                            "check 4: 0 upheld, 1 rejected, 0 open, precision 0%"])

    def test_a_rerun_keeps_the_planners_rulings(self) -> None:
        self.returns()
        self.at("2026-10-18T10:20:00Z", {"src/z/stray.ts": "export const z = 1;\n"})
        self.checks()
        path = self.repo / "state/flags/P1-S1.tsv"
        path.write_text(path.read_text(encoding="utf-8").replace("slice\t\n", "slice\tupheld\n"), encoding="utf-8")
        self.checks()
        self.assertTrue(path.read_text(encoding="utf-8").endswith("\tupheld\n"))


SLICE_BACKLOG = """# Backlog

## B1 Magic-link sign-in expires after 15 minutes
- source: owner:2026-10-16
- criterion: A magic link older than 15 minutes shows "link expired" and signs nobody in.
- risk: auth
- status: open
- inputs:
  - packages/core/src/auth/magic-link.ts
  - dep:jose
- answers: A1, A2, A3

## Answers

### A1 How long is a magic link valid?
- answered: 2026-10-16
> 15 minutes, counted from the moment the email is sent.

### A2 What does an expired link show?
- answered: 2026-10-16
> The words "link expired" and a button that sends a new link.
> Nothing else on the page changes.

### A3 Does an expired link count as a failed sign-in?
- answered: 2026-10-17
> No. Only a wrong code counts.
"""


class Slicer(Workspace):
    """Done check 5."""

    def setUp(self) -> None:
        super().setUp()
        tools = (CORE / "policies/agent-tools.yml").read_text(encoding="utf-8")
        self.base = commit(self.repo, {"policies/agent-tools.yml": tools, "policies/evidence-classes.yml": TIER,
                                       "packages/core/src/auth/magic-link.ts": "export {};\n"}, "init")
        write(self.repo, "docs/flow/backlog.md", SLICE_BACKLOG)
        write(self.repo, "docs/flow/phases.md", phases_doc(self.base, [("T1", "packages/core/src/auth/**")]))

    def slice(self, *args: str) -> subprocess.CompletedProcess:
        return run(str(LOCAL / "slice.py"), *args, "--root", str(self.repo), cwd=self.tmp)

    def test_a_task_with_three_cited_answers_fits_and_carries_no_rule_or_skill_text(self) -> None:
        out = self.slice("T1")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertLess(len(out.stdout.encode("utf-8")), 8000)
        for text in ('15 minutes, counted from the moment the email is sent.', 'Nothing else on the page changes.',
                     'No. Only a wrong code counts.', 'criterion: A magic link older than 15 minutes',
                     'glob: `packages/core/src/auth/**` (1 files at HEAD)', 'estimate: 30m 2f', 'reference: none',
                     '  - dep:jose'):
            self.assertIn(text, out.stdout)
        kernel = [CORE / "FLOW_RULES.md", *sorted(CORE.glob("flow-skills/*/SKILL.md"))]
        lines = {ln.strip() for f in kernel for ln in f.read_text(encoding="utf-8").splitlines() if len(ln.strip()) >= 25}
        self.assertEqual([ln for ln in lines if ln in out.stdout], [])

    def test_with_no_reader_run_it_prints_last_seen_never(self) -> None:
        self.assertIn("last seen: never", self.slice("T1").stdout)
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 300))
        write(self.repo, "state/status.line", f"flow: idle last={stamp} hooks: claude unenforced, codex unenforced "
                                              f"alerts=0 reader={stamp}\n")
        self.assertRegex(self.slice("T1").stdout, r"reader=\S+; last seen: [45] min ago")

    def test_an_input_tool_absent_from_the_builder_profile_blocks(self) -> None:
        write(self.repo, "docs/flow/backlog.md", SLICE_BACKLOG.replace("  - dep:jose\n", "  - dep:jose\n  - figma:frame-12\n"))
        tools = (CORE / "policies/agent-tools.yml").read_text(encoding="utf-8").replace("input_kinds: {}",
                                                                                         "input_kinds: {figma: figma_mcp}")
        commit(self.repo, {"policies/agent-tools.yml": tools}, "chore: T9 the figma input kind")
        out = self.slice("T1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("BLOCKED-AT-input: T1 input figma:frame-12 needs figma_mcp, absent from the builder profile",
                      out.stdout)
        self.assertNotIn("15 minutes", out.stdout)

    def test_the_brief_carries_the_flag_rows_and_the_gate_block_inline(self) -> None:
        write(self.repo, "state/gate/P1-S1.txt", "## DONE\ndone P1-S1: 1/1 committed\nDONE: PASS\n")
        write(self.repo, "state/flags/P1-S1.tsv", "id\tcheck\ttask\tevidence\truling\n"
                                                 "new-1a2b3c4d\t1\tT1\tsrc/z.ts is under no task glob\t\n")
        out = self.slice("P1-S1", "--brief", "review")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("done P1-S1: 1/1 committed\nDONE: PASS", out.stdout)
        self.assertIn("new-1a2b3c4d\t1\tT1\tsrc/z.ts is under no task glob", out.stdout)
        self.assertTrue(out.stdout.startswith("REVIEW BRIEF\nSlice P1-S1 at "), out.stdout[:80])
        self.assertIn("(a) Does the diff add a feature the criterion does not ask for?", out.stdout)
        self.assertIn('"rubric": {"a": "yes|no", "a_evidence", "b": "yes|no", "b_evidence"}', out.stdout)
        self.assertIn("B1 answer A2: What does an expired link show?: The words", out.stdout)
        verdict = self.slice("P1", "--brief", "verdict")
        self.assertEqual(verdict.returncode, 0, verdict.stdout)
        self.assertTrue(verdict.stdout.startswith("VERDICT BRIEF\nPhase P1 at "), verdict.stdout[:80])

    def test_a_trivial_tier_slice_brief_asks_no_rubric(self) -> None:
        commit(self.repo, {"docs/notes/a.md": "a\n"}, "T1: a note")
        out = self.slice("P1-S1", "--brief")
        self.assertIn("rubric: not asked (a trivial-tier slice)", out.stdout)
        self.assertNotIn('"rubric"', out.stdout)
        self.assertNotIn("(a) Does the diff", out.stdout)


GATE_BACKLOG = BACKLOG.format(risk="auth").replace("- test: test/auth.test.ts::magic link expires\n- risk: none",
                                                    "- criterion: Deleting a link keeps the account.\n- risk: data")
VERDICTS = ("2026-10-18T10:00Z verdict P1-S1 result=FAIL agent=r1 -- the banner text contradicts owner answer A2\n"
            "2026-10-18T11:00Z verdict P1-S1 result=FAIL agent=r2 -- privacy: the email address is written to the log\n")


class Gate(Workspace):
    """Done check 6."""

    def setUp(self) -> None:
        super().setUp()
        approval = (CORE / "policies/approval-policy.yml").read_text(encoding="utf-8")
        self.base = commit(self.repo, {"policies/approval-policy.yml": approval, "policies/evidence-classes.yml": TIER,
                                       "docs/flow/backlog.md": GATE_BACKLOG}, "init")
        write(self.repo, "docs/flow/phases.md", phases_doc(self.base, [("T1", "src/a/**"), ("T2", "src/b/**")])
              .replace("| T2 | B1 |", "| T2 | B2 |"))
        commit(self.repo, {"src/a/x.ts": "export const x = 1;\n"}, "T1: the first part")

    def gate(self) -> subprocess.CompletedProcess:
        return run(str(LOCAL / "gate.py"), "P1-S1", "--root", str(self.repo), cwd=self.tmp)

    def test_the_gate_writes_its_three_blocks(self) -> None:
        out = self.gate()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        text = (self.repo / "state/gate/P1-S1.txt").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"^## (\w+)$", text, re.M), ["DONE", "Checks", "Evidence"])
        self.assertIn("0 of 2 verdict rounds and 0 of 2 review rounds used", text)
        self.assertIn("T2 OPEN: no commit carries it alone in its subject", text)
        self.assertIn("GATE: FAIL: send P1-S1 back to build", text)

    def test_two_recorded_verdicts_exhaust_two_rounds_with_the_carry_over_in_order(self) -> None:
        write(self.repo, "docs/flow/ledger.md", "status: state/status.line\n\n## Records\n" + VERDICTS)
        write(self.repo, "state/returns/P1-S1-review.json", json.dumps({"findings": [
            {"file": "src/a/x.ts", "line": 1, "wrong_outcome": "the banner shows twice", "severity": "MEDIUM"}]}))
        out = self.gate()
        self.assertEqual(out.returncode, 3, out.stdout + out.stderr)
        self.assertIn("BLOCKED-AT-gate-budget: 2 verdicts recorded for P1-S1, gate_rounds 2", out.stdout)
        listed = re.findall(r"^(\d+)\. \[([a-z-]+)\] (.*)$", out.stdout, re.M)
        self.assertEqual([int(n) for n, _, _ in listed], list(range(1, len(listed) + 1)))
        self.assertEqual([c for _, c, _ in listed][:4], ["security", "privacy", "data-loss", "owner-answer"])
        self.assertTrue(listed[0][2].startswith("B1 (risk auth) FAIL"), listed[0])
        self.assertIn("the email address is written to the log", listed[1][2])
        self.assertTrue(listed[2][2].startswith("B2 (risk data) FAIL"), listed[2])
        self.assertIn("contradicts owner answer A2", listed[3][2])
        self.assertEqual({c for _, c, _ in listed[4:]}, {"other"})
        self.assertIn("T2 OPEN", out.stdout.split("Carry-over")[1])
        self.assertIn("P1-S1-review: file=src/a/x.ts; line=1; wrong_outcome=the banner shows twice", out.stdout)

    def test_a_local_override_lowers_the_rounds_and_never_raises_them(self) -> None:
        write(self.repo, "docs/flow/ledger.md", "## Records\n" + VERDICTS.splitlines()[0] + "\n")
        write(self.repo, "policies/approval-policy.local.yml", "gate_rounds: 1\n")
        self.assertEqual(self.gate().returncode, 3)
        write(self.repo, "policies/approval-policy.local.yml", "gate_rounds: 5\n")
        self.assertEqual(self.gate().returncode, 1)


class Upgrade(Workspace):
    """Done check 7, its install part on a synthetic project: 6.0.0-m2's install, then a re-run of this tree's."""
    M2 = "1f91908e"  # 6.0.0-m2
    NEW = ("hooks/local/reader.py", "hooks/local/done.py", "hooks/local/validate_evidence.py", "hooks/local/checks.py",
           "hooks/local/slice.py", "hooks/local/gate.py", "hooks/local/lib/flow_docs.py", "policies/evidence-classes.yml")

    def test_a_rerun_on_an_m2_install_adds_the_new_files_and_touches_nothing_else(self) -> None:
        import tarfile
        from synthetic import snapshot
        archive = subprocess.run(["git", "archive", "--format=tar", self.M2], cwd=CORE, capture_output=True)
        if archive.returncode:
            self.skipTest(f"6.0.0-m2 ({self.M2}) is not in this clone's history")
        with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
            tar.extractall(self.tmp / "core-m2")
        write(self.repo, "src/app.ts", "export const app = 1;\n")
        write(self.repo, ".gitignore", "node_modules/\n")
        first = run(str(self.tmp / "core-m2/maintainer/flow.py"), "install", "--target", str(self.repo), cwd=self.tmp)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        _, before = snapshot(self.repo)
        upgrade = run(str(FLOW), "install", "--target", str(self.repo), cwd=self.tmp)
        self.assertEqual(upgrade.returncode, 0, upgrade.stdout + upgrade.stderr)
        _, after = snapshot(self.repo)
        manifest = json.loads((self.repo / "audit/flow-install.json").read_text(encoding="utf-8"))
        flow_owned = {e["path"] for e in manifest["files"]} | {".gitattributes", ".gitignore", "audit/flow-install.json"}
        changed = {p for p in set(before) | set(after) if before.get(p) != after.get(p) and not p.startswith(".git/")}
        self.assertEqual(sorted(changed - flow_owned), [], "a re-run touched a project file")
        self.assertTrue(set(self.NEW) <= changed and set(self.NEW) <= flow_owned)
        self.assertEqual(manifest["flow_version"], (CORE / "VERSION").read_text(encoding="utf-8").strip())
        self.assertIn("gate_rounds: 2", (self.repo / "policies/approval-policy.yml").read_text(encoding="utf-8"))
        self.assertTrue((self.repo / ".gitignore").read_text(encoding="utf-8").startswith("node_modules/\n\n# FLOW:BEGIN ignore"))
        self.assertEqual(before["src/app.ts"], after["src/app.ts"])
        again = run(str(FLOW), "install", "--target", str(self.repo), cwd=self.tmp)
        self.assertIn("added: 0", again.stdout)
        self.assertEqual(snapshot(self.repo)[1], after, "a second re-run changed a file")

    def test_install_never_sources_run_with_timeout_beyond_the_kept_part(self) -> None:
        """O-2: only bounded-run.sh sources it, and the core carries the trimmed file (the kernel lock holds its bytes)."""
        sources = [p.relative_to(CORE).as_posix() for p in [*CORE.glob("maintainer/*.py"), *CORE.glob("hooks/**/*.sh"),
                                                              *CORE.glob("hooks/local/*.py")]
                   if "run-with-timeout" in p.read_text(encoding="utf-8")]
        self.assertEqual(sources, ["hooks/local/lib/bounded-run.sh"])
        kept = (CORE / "hooks/local/lib/run-with-timeout.sh").read_text(encoding="utf-8").splitlines()
        self.assertLess(len(kept), 69 - 32 + 10, "the trimmed timeout core (5.x lines 32-69 and its header)")


class PolicyKeys(unittest.TestCase):
    """The acceptance: no policy key that no script reads."""

    def test_every_evidence_classes_key_is_read_by_a_script(self) -> None:
        doc = yaml.safe_load((CORE / "policies/evidence-classes.yml").read_text(encoding="utf-8"))
        code = "".join(p.read_text(encoding="utf-8") for p in [*LOCAL.glob("*.py"), *(LOCAL / "lib").glob("*.py")])
        unread = [k for k in [*doc, *doc["capture_min_bytes"]] if f'"{k}"' not in code]
        self.assertEqual(unread, [])
        sys.path.insert(0, str(LOCAL / "lib"))
        sys.path.insert(0, str(LOCAL))
        import flow_docs
        import validate_evidence
        self.assertEqual(set(doc["classes"]), set(validate_evidence.NEEDS))
        lists = {k: [k] for k in doc["trivial"]}
        self.assertEqual(flow_docs.tier({"trivial": lists}), list(doc["trivial"]))
        for name, key in (("approval-policy", "gate_rounds"), ("agent-tools", "input_kinds")):
            self.assertIn(key, yaml.safe_load((CORE / f"policies/{name}.yml").read_text(encoding="utf-8")))
            self.assertIn(f'"{key}"', code)


if __name__ == "__main__":
    unittest.main(verbosity=2)
