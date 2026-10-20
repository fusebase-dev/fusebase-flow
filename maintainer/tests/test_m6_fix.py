#!/usr/bin/env python3
"""The 6.0.0-m6 fix pass's owner additions (ii) to (iv) and the reader re-registration: `python
maintainer/tests/test_m6_fix.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import json
import unittest

import test_scripts as m3

ANSWERS = "\n## Answers\n\n### A1 Is the stale build an accepted cause?\n- answered: 2026-10-20\n> Yes.\n"


class FlakyNote(m3.Validator):
    """Item (ii): a FLAKY row passes only when its note cites an owner answer that backlog.md has, or states
    `reproduced <k>/<n>` and cites each of the n runs; "repro" or "not reproduced" alone does not."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))

    def test_a_flaky_row_needs_an_answer_or_a_reproduction_count_citing_each_run(self) -> None:
        m3.write(self.repo, "docs/flow/backlog.md", m3.BACKLOG.format(risk="none") + ANSWERS)
        m3.write(self.repo, "runs/run-0/README.md",
                 m3.RUN_LOG.format(records="| 2026-10-18T09:30:00.000Z | S1 | FAIL: 200 |\n"))
        m3.write(self.repo, "state/runs/P1/index.tsv",
                 "run-0\t2026-10-18T09:30:00Z\truns/run-0\t1\nrun-1\t2026-10-18T10:00:00Z\truns/run-1\t0\n")
        row = self.rows["B1"][:-4]
        for note, holds in (("repro: a stale build served run-0", False), ("not reproduced", False),
                            ("not reproduced; the stale build, A9", False), ("not reproduced; accepted, A1", True),
                            ("reproduced 2/2: run-0 and run-1, a stale build; fixed in T1", True),
                            ("reproduced 2/2: run-0, a stale build", False), ("reproduced 0/2: run-0, run-1", False)):
            self.rows["B1"] = f"{row} {note} |"
            out = self.validate()
            line = next(ln for ln in out.stdout.splitlines() if ln.startswith("  B1 "))
            self.assertEqual(line.startswith("  B1 PASS"), holds, f"{note!r}: {line}")


class StagedAsWritten(m3.Validator):
    """Item (iii): the pre-commit's staged evidence check (`validate_evidence.py --staged`) never prints PASS for a row
    whose status is FAIL, or BLOCKED without an accepted owner answer; it shows the row's own status and, as before,
    counts it as no failure of the commit."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))

    def test_a_staged_fail_or_unaccepted_blocked_row_is_shown_as_written_never_pass(self) -> None:
        head = "| Criterion | Status | Capture | sha256 | Bytes | Log | Note |\n|---|---|---|---|---|---|---|\n"
        rows = ("| B1 | FAIL: the link signed someone in | - | - | - | - | - |\n"
                "| B2 | BLOCKED-AT-owner-account | - | - | - | - | no answer yet |\n")
        m3.write(self.repo, "docs/flow/evidence/P1.md", "# Evidence\n\n" + head + rows)
        m3.git(self.repo, "add", "--", "docs/flow/evidence/P1.md")
        out = m3.run(str(m3.LOCAL / "validate_evidence.py"), "--staged", "--root", str(self.repo), cwd=self.tmp)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertNotRegex(out.stdout, r"(?m)^  B[12] PASS", out.stdout)
        self.assertIn("  B1 FAIL: the link signed someone in (holds as written: no failure of this commit, not PASS)",
                      out.stdout)
        self.assertIn("  B2 BLOCKED-AT-owner-account (holds as written", out.stdout)
        self.assertIn("EVIDENCE: AS WRITTEN (0 of 2 rows fail; 2 as written, not PASS: B1, B2)", out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
