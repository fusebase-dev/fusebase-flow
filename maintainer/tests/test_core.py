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


if __name__ == "__main__":
    unittest.main(verbosity=2)
