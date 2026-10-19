#!/usr/bin/env python3
"""The 6.0.0 pass fixtures: reader registration, stable flag ids, the kernel hooks, provider wiring and `flow health`.

`python maintainer/tests/test_core.py`; test_migrate.py's load_tests runs it too, so core-verify carries it.
A scheduler is never the real one: fake `crontab` and `schtasks` sit first on PATH.
"""
from __future__ import annotations

import calendar
import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

import test_scripts as m3
from test_scripts import BLOCK, CHECKS_BACKLOG, CHECKS_TIER, CORE, Workspace, commit, write

sys.path.insert(0, str(CORE / "maintainer"))
import flow  # noqa: E402

FAKE = '''import os, sys
log = os.environ["FAKE_SCHED_DIR"]
with open(os.path.join(log, "calls.txt"), "a", encoding="utf-8") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
if sys.argv[1] == "schtasks":
    sys.exit(int(os.environ.get("FAKE_SCHTASKS_RC", "0")))
if sys.argv[2:] == ["-l"]:
    sys.stdout.write(os.environ.get("FAKE_CRONTAB", ""))
    sys.stderr.write(os.environ.get("FAKE_CRONTAB_ERR", ""))
    sys.exit(int(os.environ.get("FAKE_CRONTAB_RC", "0")))
with open(os.path.join(log, "written.txt"), "wb") as f:
    f.write(sys.stdin.buffer.read())
'''


class Register(Workspace):
    """O-16: the user's crontab is written only after a clean read, and a refused registration leaves install at 0."""

    def setUp(self) -> None:
        super().setUp()
        self.bin = self.tmp / "fake-bin"
        self.bin.mkdir()
        (self.bin / "fake_sched.py").write_text(FAKE, encoding="utf-8")
        for name in ("crontab", "schtasks"):
            sh = self.bin / name
            sh.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{self.bin / "fake_sched.py"}" {name} "$@"\n',
                          encoding="utf-8", newline="\n")
            sh.chmod(0o755)
            (self.bin / f"{name}.cmd").write_text(f'@"{sys.executable}" "{self.bin / "fake_sched.py"}" {name} %*\r\n',
                                                  encoding="utf-8", newline="")
        env = {"PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}", "FAKE_SCHED_DIR": str(self.tmp)}
        patcher = mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        real = flow.subprocess.run

        def guarded(argv, *args, **kwargs):
            # TRIPWIRE: a bare name reaches the real scheduler (Windows searches System32 before PATH).
            if Path(argv[0]).stem.lower() in ("crontab", "schtasks") and Path(argv[0]).parent != self.bin:
                raise AssertionError(f"the real scheduler would run: {argv[0]}")
            return real(argv, *args, **kwargs)
        guard = mock.patch.object(flow.subprocess, "run", guarded)
        guard.start()
        self.addCleanup(guard.stop)

    def calls(self) -> list[str]:
        path = self.tmp / "calls.txt"
        return path.read_text(encoding="utf-8").splitlines() if path.is_file() else []

    def written(self) -> str | None:
        path = self.tmp / "written.txt"
        return path.read_text(encoding="utf-8") if path.is_file() else None

    def cron(self, target: Path, python: str = "/usr/bin/python3") -> list[str]:
        return ["crontab", f"*/5 * * * * cd '{target}' && '{python}' hooks/local/reader.py --once >/dev/null 2>&1"]

    def test_a_failed_crontab_read_writes_nothing_and_prints_the_line_by_hand(self) -> None:
        os.environ.update(FAKE_CRONTAB="", FAKE_CRONTAB_ERR="crontab: cannot open spool: Permission denied\n",
                          FAKE_CRONTAB_RC="1")
        rc, out = flow.register_reader(self.cron(self.repo), self.repo)
        self.assertNotEqual(rc, 0)
        self.assertIsNone(self.written(), "the crontab is never written after a failed read")
        self.assertEqual(self.calls(), ["crontab -l"])
        self.assertIn("Permission denied", out)

    def test_no_crontab_yet_writes_the_one_line(self) -> None:
        os.environ.update(FAKE_CRONTAB_ERR="no crontab for flow-test\n", FAKE_CRONTAB_RC="1")
        argv = self.cron(self.repo)
        self.assertEqual(flow.register_reader(argv, self.repo)[0], 0)
        self.assertEqual(self.written(), argv[1] + "\n")

    def test_an_existing_crontab_keeps_its_lines_and_gains_one(self) -> None:
        os.environ.update(FAKE_CRONTAB="MAILTO=me\n0 3 * * * /usr/bin/backup\n")
        argv = self.cron(self.repo)
        self.assertEqual(flow.register_reader(argv, self.repo)[0], 0)
        self.assertEqual(self.written(), "MAILTO=me\n0 3 * * * /usr/bin/backup\n" + argv[1] + "\n")

    def test_an_entry_for_the_same_target_under_another_interpreter_is_not_added_twice(self) -> None:
        old = self.cron(self.repo, "/opt/old/python3.10")[1]
        os.environ.update(FAKE_CRONTAB=f"0 3 * * * /usr/bin/backup\n{old}\n")
        rc, out = flow.register_reader(self.cron(self.repo), self.repo)
        self.assertEqual(rc, 0)
        self.assertIsNone(self.written())
        self.assertIn("already", out)
        other = self.repo.with_name(self.repo.name + "2")
        self.assertEqual(flow.register_reader(self.cron(other), other)[0], 0)
        self.assertIn(self.cron(other)[1], self.written() or "", "another target is its own entry")

    def test_a_tr_value_past_261_characters_is_refused_before_schtasks_runs(self) -> None:
        run = f'"C:\\Python312\\pythonw.exe" "C:\\{"p" * 240}\\hooks\\local\\reader.py" --once'
        argv = ["schtasks", "/Create", "/F", "/SC", "MINUTE", "/MO", "5", "/TN", "FuseBase Flow reader x", "/TR", run]
        rc, out = flow.register_reader(argv, self.repo)
        self.assertNotEqual(rc, 0)
        self.assertEqual(self.calls(), [], "schtasks never ran")
        self.assertIn("261", out)
        self.assertIn("Register-ScheduledTask", flow.by_hand(argv)[1])
        short = argv[:-1] + ['"C:\\Python312\\pythonw.exe" "C:\\p\\hooks\\local\\reader.py" --once']
        self.assertEqual(flow.register_reader(short, self.repo)[0], 0)
        self.assertEqual(len(self.calls()), 1)

    def test_a_failed_registration_leaves_a_good_install_at_exit_0_on_its_own_line(self) -> None:
        os.environ.update(FAKE_CRONTAB_ERR="crontab: your account is not allowed\n", FAKE_CRONTAB_RC="1",
                          FAKE_SCHTASKS_RC="1")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(flow.install(self.repo, {"claude", "codex"}, register=True), 0, "the files are in")
        line = [x for x in out.getvalue().splitlines() if x.startswith("[flow] heartbeat reader:")]
        self.assertEqual(len(line), 1, out.getvalue())
        self.assertIn("NOT registered", line[0])
        self.assertIn(flow.by_hand(flow.reader_line(self.repo)[1])[1], out.getvalue(), "the line to add by hand")
        self.assertNotIn("reader", json.loads((self.repo / "audit/flow-install.json").read_text("utf-8")))
        self.assertIsNone(self.written())


class FlagIds(Workspace):
    """O-17: a flag's id is its kind, task and path or variable, so a ruling outlives a re-run that moved its numbers."""

    plan, at, returns, checks, kinds = m3.Checks.plan, m3.Checks.at, m3.Checks.returns, m3.Checks.checks, m3.Checks.kinds

    def setUp(self) -> None:
        super().setUp()
        self.base = commit(self.repo, {"policies/evidence-classes.yml": CHECKS_TIER, "docs/flow/backlog.md": CHECKS_BACKLOG,
                                       "package.json": '{"name": "app", "dependencies": {}}\n',
                                       "src/a/one.ts": BLOCK}, "init")
        self.globs, self.estimate = "src/a/**`, `package.json`, `tsconfig.json`, `test/**", "30m 2f"
        self.plan()
        self.tsv = self.repo / "state/flags/P1-S1.tsv"

    def rows(self) -> list[list[str]]:
        return [r.split("\t") for r in self.tsv.read_text(encoding="utf-8").splitlines()]

    def test_a_ruling_survives_a_rerun_where_the_duplicates_line_and_count_changed(self) -> None:
        self.returns()
        self.at("2026-10-18T10:10:00Z", {"src/a/copy.ts": BLOCK})
        self.assertRegex(self.checks(), r"src/a/copy.ts:1 repeats src/a/one.ts:1, 25 lines")
        head, row = self.rows()
        self.tsv.write_text("\t".join(head + ["note"]) + "\n" + "\t".join(row[:4] + ["rejected", "a test copy"]) + "\n",
                            encoding="utf-8")
        moved = "export const pad = 1;\nexport const pad2 = 2;\n" + "".join(BLOCK.splitlines(True)[:23])
        self.at("2026-10-18T10:20:00Z", {"src/a/copy.ts": moved})
        out = self.checks()
        self.assertRegex(out, r"src/a/copy.ts:3 repeats src/a/one.ts:1, 23 lines \[rejected\]")
        now = self.rows()
        self.assertEqual(now, [head + ["note"], [row[0], "4", "T1", now[1][3], "rejected", "a test copy"]])
        self.at("2026-10-18T10:30:00Z", {"src/a/copy.ts": "export const fresh = true;\n"})
        out = self.checks()
        self.assertEqual(self.kinds(out), [], "the duplicate no longer fires")
        self.assertIn(f"  STALE {row[0]} check 4 T1:", out)
        stale = self.rows()[1]
        self.assertEqual((stale[0], stale[4], stale[5]), (row[0], "rejected", "a test copy"), "carried, not dropped")
        self.assertTrue(stale[3].startswith("[stale] "), stale[3])
        self.assertEqual(self.checks().count("[stale]"), 1, "marked once")

    def test_a_ruling_under_the_m3_id_carries_over_to_the_stable_id(self) -> None:
        self.returns()
        self.at("2026-10-18T10:10:00Z", {"src/z/stray.ts": "export const z = 1;\n"})
        evidence = "src/z/stray.ts is under no task glob of the slice"
        m3_id = "new-" + hashlib.sha256(f"T1|{evidence}".encode()).hexdigest()[:8]
        write(self.repo, "state/flags/P1-S1.tsv", f"id\tcheck\ttask\tevidence\truling\n{m3_id}\t1\tT1\t{evidence}\tupheld\n")
        self.assertIn(f"{evidence} [upheld]", self.checks())
        self.assertEqual(len(self.rows()), 2, "no stale copy of the m3 row")
        self.assertNotEqual(self.rows()[1][0], m3_id)

    def test_a_minutes_flag_keeps_its_id_when_the_minutes_change(self) -> None:
        self.returns()
        self.estimate = "10m 2f"
        self.plan()
        self.at("2026-10-18T10:50:00Z", {"src/a/two.ts": "1\n"})
        self.checks()
        first = self.rows()[1]
        self.returns(started="2026-10-18T10:05:00Z")
        self.checks()
        second = self.rows()[1]
        self.assertEqual((first[2], second[2]), ("T1", "T1"))
        self.assertNotEqual(first[3], second[3], "the minutes in the evidence changed")
        self.assertEqual(first[0], second[0])

    def test_finished_heartbeats_are_not_repeats_and_three_in_flight_are(self) -> None:
        self.returns()
        self.at("2026-10-18T10:10:00Z", {"src/a/two.ts": "1\n"})
        folder = self.repo / "state/audit/liveness"
        folder.mkdir(parents=True)
        stamp = calendar.timegm(time.strptime("2026-10-18 11:00", "%Y-%m-%d %H:%M"))
        for record, expect in (("done rc=0 20s", False), ("running 20/900", True)):
            for pid in (101, 202, 303):
                beat = folder / f"vitest-{pid}-1.hb"
                beat.write_text(f"bounded-run vitest run deadline=900s\n{record}\n", encoding="utf-8")
                os.utime(beat, (stamp, stamp))
            self.assertEqual("3 times in flight (UNCALIBRATED: logged)" in self.checks(), expect, record)


class SmallItems(Workspace):
    """O-18: the ignore block follows the records decision, the scripts import each other under PYTHONSAFEPATH=1, and
    the public texts name the public 5.x commit and the 30-minute mint."""

    def test_the_ignore_block_hides_runtime_state_and_never_a_record(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(flow.install(self.repo, {"claude", "codex"}), 0, out.getvalue())
        runtime = ["state/returns/P1-S1.json", "state/returns/P1-S1-review.json", "state/audit.log.jsonl",
                   "state/reader/last.json", "state/status.line", "state/approvals/x.json", "hooks/shared/__pycache__/x.pyc"]
        records = ["state/flags/P1-S1.tsv", "state/gate/P1-S1.txt", "state/done/P1-S1.json", "state/deploys/dev.jsonl",
                   "state/runs/P1/index.tsv", "state/approvals/.gitkeep"]
        probe = subprocess.run(["git", "check-ignore", "--stdin"], cwd=self.repo, capture_output=True,
                               input="\n".join(runtime + records).encode() + b"\n")
        self.assertEqual(sorted(probe.stdout.decode().split()), sorted(runtime))

    @unittest.skipIf(sys.version_info < (3, 11), "PYTHONSAFEPATH arrived in Python 3.11")
    def test_the_scripts_import_each_other_under_pythonsafepath(self) -> None:
        env = {**os.environ, "PYTHONSAFEPATH": "1"}
        for argv in ([str(CORE / "hooks/local/gate.py"), "--help"], [str(CORE / "hooks/local/checks.py"), "--help"],
                     [str(CORE / "maintainer/flow.py"), "migrate", "--target", str(self.tmp / "absent")]):
            out = subprocess.run([sys.executable, *argv], cwd=self.tmp, env=env, capture_output=True, text=True,
                                 timeout=600)
            self.assertNotIn("Traceback", out.stderr, argv)
            self.assertNotIn("ModuleNotFoundError", out.stderr + out.stdout, argv)

    def test_public_texts_name_the_public_5x_commit_and_the_30_minute_mint(self) -> None:
        local = "bac8" + "bbb1"
        named = subprocess.run(["git", "grep", "-n", local, "--", "."], cwd=CORE, capture_output=True, text=True)
        self.assertEqual(named.stdout, "", "the local-only 5.x commit is named nowhere")
        self.assertIn("731acb69", (CORE / "maintainer/kernel.lock").read_text(encoding="utf-8"))
        for note in sorted((CORE / "maintainer/release-notes").glob("6.0.0-m[3-9]*.md")):
            text = note.read_text(encoding="utf-8")
            self.assertIn("FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh", text, note.name)
            self.assertIn("which has no `gate_rounds`; the gate then allows 2 rounds", text, note.name)


class CommandHash(Workspace):
    """O-10: bounded-run writes the command's sha256 into its heartbeat, and the reader counts that, not the label."""

    def bounded(self, label: str, *argv: str) -> Path:
        folder = self.tmp / "hb"
        env = {**os.environ, "BOUNDED_RUN_HB_DIR": folder.as_posix(), "BOUNDED_RUN_HEARTBEAT_SECS": "0",
               "BR_LIB": (CORE / "hooks/local/lib/bounded-run.sh").as_posix()}
        bash = shutil.which("bash")  # TRIPWIRE: a bare name on Windows finds System32's WSL bash first
        out = subprocess.run([bash, "-c", '. "$BR_LIB"; bounded_run 60 "$0" -- "$@"', label, *argv], env=env,
                             capture_output=True, text=True, timeout=600)
        self.assertEqual(out.returncode, 0, out.stderr)
        return sorted(folder.glob("*.hb"), key=lambda p: p.stat().st_mtime_ns)[-1]

    def test_the_heartbeat_carries_the_sha256_of_the_commands_arguments(self) -> None:
        lines = self.bounded("probe", "echo", "a b", "c").read_text(encoding="utf-8").splitlines()
        want = hashlib.sha256(b"echo\0a b\0c\0").hexdigest()
        self.assertEqual(lines[0], "bounded-run probe deadline=60s", "the header stays the first line")
        self.assertEqual(lines[1], f"cmd sha256={want}")
        self.assertRegex(lines[-1], r"^done rc=0 \d+s$", "the terminal record stays the last line")
        other = self.bounded("probe", "echo", "a", "b", "c").read_text(encoding="utf-8").splitlines()[1]
        self.assertNotEqual(other, lines[1], "the arguments' boundaries count")

    def test_the_reader_prefers_the_command_hash_over_the_label(self) -> None:
        sys.path.insert(0, str(CORE / "hooks/local"))
        import reader
        folder = self.repo / "state/audit/liveness"
        folder.mkdir(parents=True)
        one, two = hashlib.sha256(b"vitest\0run\0").hexdigest(), hashlib.sha256(b"vitest\0run\0--watch\0").hexdigest()
        beats = {"tests-1-1.hb": ("tests", one), "tests-2-1.hb": ("tests", two), "unit-3-1.hb": ("unit", one),
                 "suite-4-1.hb": ("suite", one), "old-5-1.hb": ("old", None)}
        for name, (label, digest) in beats.items():
            cmd = f"cmd sha256={digest}\n" if digest else ""
            (folder / name).write_text(f"bounded-run {label} deadline=900s\n{cmd}running 10/900\n", encoding="utf-8")
        got = {p: h for p, _, h, _ in reader.heartbeats(self.repo)}
        self.assertEqual([got["1"], got["2"], got["3"], got["4"]], [one, two, one, one])
        self.assertEqual(got["5"], hashlib.sha256(b"bounded-run old").hexdigest(), "an older heartbeat keeps the label")


class EvidenceHook(Workspace):
    """O-11: the installed pre-commit runs the evidence validator on a commit that stages evidence or run files only."""

    def hooked(self, subject: str, files: dict[str, str | bytes], mint: bool = False) -> subprocess.CompletedProcess:
        for rel, data in files.items():
            (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / rel).write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))
            m3.git(self.repo, "add", "--", rel)
        bash = shutil.which("bash")
        if mint:
            subprocess.run([bash, "hooks/local/write-bootstrap-approval.sh"], cwd=self.repo, check=True,
                           env={**os.environ, "FF_BOOTSTRAP_TTL_MIN": "30"}, capture_output=True)
        out = subprocess.run([*m3.GIT, "commit", "-q", "-m", subject], cwd=self.repo, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=900)
        if mint:
            subprocess.run([bash, "hooks/local/write-bootstrap-approval.sh", "--consume"], cwd=self.repo, check=True,
                           capture_output=True)
        return out

    def row(self, item: str, rel: str, data: bytes, sha: str | None = None) -> str:
        (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.repo / rel).write_bytes(data)
        return f"| {item} | PASS | {rel} | {sha or hashlib.sha256(data).hexdigest()} | {len(data)} | runs/run-1/README.md | - |"

    def test_the_installed_pre_commit_checks_staged_rows_and_stays_quiet_otherwise(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(flow.install(self.repo, {"claude"}), 0)
        names = m3.git(self.repo, "ls-files", "--others", "--exclude-standard").stdout.splitlines()
        first = self.hooked("T1: install Fusebase Flow", {n: (self.repo / n).read_bytes() for n in names}, mint=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(list((self.repo / "state/approvals").glob("*.json")), [], "consumed")
        base = m3.git(self.repo, "rev-parse", "HEAD").stdout.strip()
        plain = self.hooked("T2: the plan and the code", {
            "docs/flow/backlog.md": m3.BACKLOG.format(risk="none"),
            "docs/flow/phases.md": m3.phases_doc(base, [("T1", "src/a/**"), ("T2", "test/**")])
            .replace("| T2 | B1 |", "| T2 | B2 |"),
            "src/a/expiry.ts": "export const ttl = 15;\n", "test/auth.test.ts": "test('magic link expires', () => {});\n"})
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertNotIn("stage=evidence", plain.stderr, "quiet on a commit with no evidence or run path")
        self.assertNotIn("EVIDENCE:", plain.stdout + plain.stderr)
        runs = {"state/deploys/dev.jsonl": json.dumps({"env": "dev", "finished": "2026-10-18T09:00:00Z"}) + "\n",
                "state/runs/P1/index.tsv": "run-1\t2026-10-18T10:00:00Z\truns/run-1\t0\n",
                "runs/run-1/README.md": m3.RUN_LOG.format(records="| 2026-10-18T10:00:00.000Z | S1 | PASS |\n")}
        head = "# Evidence\n\n| Criterion | Status | Capture | sha256 | Bytes | Log | Note |\n|---|---|---|---|---|---|---|\n"
        capture = b'{"signed_in": false, "status": 410}\n'
        wrong = self.row("B1", "runs/run-1/S1/link.json", capture, "0" * 64)
        blocked = self.hooked("T3: the B1 row", {**runs, "docs/flow/evidence/P1.md": f"{head}{wrong}\n"})
        self.assertNotEqual(blocked.returncode, 0, "a PASS row whose digest is wrong is not committed")
        self.assertIn("B1 FAIL: the row's sha256 or Bytes differ from the file", blocked.stdout + blocked.stderr)
        self.assertIn("BLOCK — an evidence row this commit stages does not hold", blocked.stderr)
        partial = self.hooked("T3: the B1 row", {"docs/flow/evidence/P1.md": f"{head}{self.row('B1', 'runs/run-1/S1/link.json', capture)}\n"})
        self.assertEqual(partial.returncode, 0, partial.stdout + partial.stderr)
        self.assertIn("stage=evidence", partial.stderr)
        self.assertIn("EVIDENCE: PASS (0 of 1 rows fail)", partial.stderr, "B2 has no row yet: no failure here")
        failed = self.hooked("T4: the B2 row records a FAIL", {"docs/flow/evidence/P1.md": (
            self.repo / "docs/flow/evidence/P1.md").read_text("utf-8") + "| B2 | FAIL: the test is red | - | - | - | - | - |\n"})
        self.assertEqual(failed.returncode, 0, failed.stdout + failed.stderr)
        self.assertIn("EVIDENCE: PASS (0 of 2 rows fail)", failed.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
