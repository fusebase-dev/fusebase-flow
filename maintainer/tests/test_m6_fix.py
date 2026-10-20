#!/usr/bin/env python3
"""The 6.0.0-m6 fix pass's owner additions (ii) to (iv) and re-review A's two commit.py fixes: `python
maintainer/tests/test_m6_fix.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import json
import sys
import unittest

import test_m6 as m6
import test_scripts as m3
from synthetic import git

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


class LiveRunRule(m3.Validator):
    """Item (iv): a live run must start after its environment's deploy finished (state/deploys/<env>.jsonl), except a
    pre-deploy baseline run, named so in its run-log title, which may start before the deploy it serves."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))

    def test_a_run_before_the_deploy_fails_unless_it_is_the_pre_deploy_baseline(self) -> None:
        m3.write(self.repo, "state/deploys/dev.jsonl", json.dumps({"env": "dev", "finished": "2026-10-18T09:45:00Z"}))
        records = "| 2026-10-18T09:30:00.000Z | S1 | PASS |\n"  # started 15 minutes before the deploy finished
        for title, holds in (("# Live run p1 aaa111 (dev)", False), ("# Live run baseline-p1 aaa111 (dev)", True),
                             ("# Live run p1-baseline aaa111 (dev)", True)):
            m3.write(self.repo, "runs/run-1/README.md", m3.RUN_LOG.format(records=records).replace(
                "# Live run p1 aaa111 (dev)", title))
            out = self.validate()
            line = next(ln for ln in out.stdout.splitlines() if ln.startswith("  B1 "))
            self.assertEqual(line.startswith("  B1 PASS (class live"), holds, f"{title}: {out.stdout}")
            if not holds:
                self.assertIn("before the dev deploy finished 2026-10-18T09:45:00Z", line)
        ship = (m3.CORE / "flow-skills/ship/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("`# Live run baseline-<run> <id> (<env>)`", ship)


class CommitPyOutput(m6.Project):
    """Re-review A on commit.py: what git and its hooks print reaches the caller (T317), and each name is marked
    :(literal) instead of git's --literal-pathspecs, which reached the hooks (T318)."""

    wire = False

    def commit_py(self, subject: str, *names: str):
        return m6.sh(self.repo, sys.executable, "hooks/local/commit.py", "-m", subject, *names)

    def test_a_refused_commit_says_why_and_a_landed_one_prints_its_summary(self) -> None:
        """T317: commit.py hands git its own stdout and stderr. With CREATE_NO_WINDOW and no handles, git printed to a
        hidden console of its own on Windows: a refused commit showed exit 1 and no reason."""
        rel = "policies/protected-paths.yml"
        (self.repo / rel).write_bytes((self.repo / rel).read_bytes() + b"# one more line\n")
        done = self.commit_py("T1: a protected file, no approval", rel)
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("[fusebase-flow:pre-commit] BLOCK", done.stdout + done.stderr)
        git(self.repo, "restore", "--staged", "--worktree", "--", rel)
        (self.repo / "x.ts").write_bytes(b"export const x = 1;\n")
        done = self.commit_py("T1: one file", "x.ts")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 file changed", done.stdout)

    def test_the_secret_scan_excludes_hold_through_commit_py(self) -> None:
        """T318: GIT_LITERAL_PATHSPECS=1, set by git's --literal-pathspecs, reached the hooks and turned the secret
        scan's :(exclude) entries into file names: a token shape in policies/secret-patterns.yml, which a plain git
        commit lands, was refused through commit.py."""
        rel, token = "policies/secret-patterns.yml", "ghp_" + "M6fakeTokenM6fakeTokenM6fakeToken00001"
        body = (self.repo / rel).read_bytes().rstrip(b"\n") + f"\n# an example: {token}\n".encode("utf-8")
        (self.repo / rel).write_bytes(body)
        git(self.repo, "add", "--", rel)
        mint = self.bash("hooks/local/write-bootstrap-approval.sh", FF_BOOTSTRAP_TTL_MIN="30")
        self.assertEqual(mint.returncode, 0, mint.stderr)
        done = self.commit_py("T1: an example token shape in the secret patterns", rel)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(git(self.repo, "show", "--name-only", "--format=", "HEAD").stdout.split(), [rel])


class NoWindowOutput(unittest.TestCase):
    def test_every_no_window_call_keeps_its_output(self) -> None:
        """T317: a CREATE_NO_WINDOW call that neither captures nor hands on stdout and stderr prints to a hidden console
        of its own on Windows (commit.py's git commit did: every hook's refusal was lost)."""
        lost = [f"{path.relative_to(m6.CORE).as_posix()}:{c.lineno}" for path in m6.NO_WINDOW_FILES
                for c in m6.subprocess_calls(path.read_text("utf-8"))
                if "capture_output" not in (kw := {k.arg for k in c.keywords})
                and not {"stdout", "stderr"} <= kw | ({"stdout"} if c.func.attr == "check_output" else set())]
        self.assertEqual(lost, [], "no-window calls whose output nobody sees")


if __name__ == "__main__":
    unittest.main(verbosity=2)
