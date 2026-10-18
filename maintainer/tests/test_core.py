#!/usr/bin/env python3
"""The 6.0.0 pass fixtures: reader registration, stable flag ids, the kernel hooks, provider wiring and `flow health`.

`python maintainer/tests/test_core.py`; test_migrate.py's load_tests runs it too, so core-verify carries it.
A scheduler is never the real one: fake `crontab` and `schtasks` sit first on PATH.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

from test_scripts import CORE, Workspace

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
