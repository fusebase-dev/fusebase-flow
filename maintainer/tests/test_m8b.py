#!/usr/bin/env python3
"""The 6.0.0-m8 pass, part two (test_m8.py stays under its 800 lines): the m7 reviews' findings (items 8 and 9).
`python maintainer/tests/test_m8b.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

import yaml

import test_m7
from synthetic import git

CORE = Path(__file__).resolve().parents[2]
WINDOWS = os.name == "nt"
sys.path[:0] = [str(CORE / "maintainer"), str(CORE / "hooks"), str(CORE / "hooks/local"), str(CORE / "hooks/local/lib")]


def inherited(base: type) -> dict:
    """The base class's tests set to None here: they run in the base's own module."""
    return dict.fromkeys(n for n in dir(base) if n.startswith("test"))



class RangeReviewA(test_m7.RangeCheck):
    """m7 review A #1..#4: what the pre-push and pre-merge-commit range check let through."""

    locals().update(inherited(test_m7.RangeCheck))

    def push(self, branch: str) -> subprocess.CompletedProcess:
        return self.git("push", "origin", branch, ok=False)

    def refused(self, out: subprocess.CompletedProcess, what: str) -> None:
        self.assertNotEqual(out.returncode, 0, f"{what} reached the remote")
        self.assertIn("secret pattern aws_access_key_id", out.stderr)

    def test_a_branch_older_than_the_upgrade_is_judged_at_push(self) -> None:
        # A#1: a branch cut from the history the install found never carries the check's mark, so it went unjudged
        self.git("checkout", "-q", "-b", "old", "main")
        self.commit("config/old.txt", f"aws_access_key_id = {self.KEY}\n", "T1: an old branch's settings", "--no-verify")
        self.git("checkout", "-q", "work")
        self.refused(self.push("old"), "a token on a branch older than the install")

    def test_a_line_starting_with_two_pluses_and_an_octopus_merges_own_line_are_scanned(self) -> None:
        # A#2: in the diff such a line reads `+++...`, which the check took for a file header
        self.git("checkout", "-q", "-b", "plus", "work")
        self.commit("docs/a.md", f"++aws_access_key_id = {self.KEY}\n", "T1: a doubled plus", "--no-verify")
        self.refused(self.push("plus"), "a token on a `++` line")
        for n in (1, 2):
            self.git("checkout", "-q", "-b", f"b{n}", "work")
            self.commit(f"docs/b{n}.md", f"{n}\n", f"T{n + 1}: note {n}", "--no-verify")
        self.git("checkout", "-q", "-b", "octo", "work")
        self.git("merge", "--no-ff", "--no-commit", "b1", "b2")
        (self.repo / "docs/b1.md").write_text(f"1\naws_access_key_id = {self.KEY}\n", encoding="utf-8")
        self.git("add", "--", "docs/b1.md")
        self.git("commit", "-q", "--no-verify", "-m", "T4: merge the notes")  # three parents: its own line is `+++`
        self.assertEqual(len(self.git("log", "-1", "--format=%P").stdout.split()), 3)
        self.refused(self.push("octo"), "a token an octopus merge added")

    def test_a_tracking_ref_under_another_remotes_name_hides_nothing(self) -> None:
        # A#3: any refs/remotes/* ref counted as the remote's, so one set by hand hid a commit from the check
        sha = self.side_secret()
        self.git("update-ref", "refs/remotes/other/side", sha)
        self.refused(self.push("side"), "a token another remote's ref held")
        merged = self.git("merge", "--no-ff", "--no-edit", "side", ok=False)
        self.assertNotEqual(merged.returncode, 0, "the merge of a token another remote's ref held landed")
        self.assertIn("a secret pattern in what the merge brings in", merged.stderr)

    def test_putting_a_commit_on_record_needs_the_go_ahead_and_leaves_an_audit_line(self) -> None:
        # A#4: --record-commit approved any commit, silently; the record is the operator's word
        rules = self.repo / "FLOW_RULES.md"
        sha = self.commit("FLOW_RULES.md", rules.read_text(encoding="utf-8") + "\nx\n", "T1: a rule edit", "--no-verify")
        record = [sys.executable, "hooks/local/lib/range_check.py", "--record-commit", sha]
        asked = subprocess.run(record, cwd=self.repo, capture_output=True, text=True, timeout=600)
        self.assertEqual(asked.returncode, 2, asked.stdout + asked.stderr)
        self.assertIn("--go-ahead", asked.stderr)
        self.assertNotEqual(self.push("work").returncode, 0, "the unrecorded edit reached the remote")
        done = subprocess.run([*record, "--go-ahead"], cwd=self.repo, capture_output=True, text=True, timeout=600)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("[fusebase-flow] on record: FLOW_RULES.md", done.stdout)
        lines = [json.loads(ln) for ln in (self.repo / "state/audit.log.jsonl").read_text(encoding="utf-8").splitlines()]
        audit = [e for e in lines if e.get("event") == "approval_record"]
        self.assertEqual([(e["commit"], e["paths"]) for e in audit], [(sha, ["FLOW_RULES.md"])])
        self.assertEqual(self.push("work").returncode, 0)


class StagedScanHeaders(unittest.TestCase):
    """m7 review A #2, the pre-commit's half: the staged secret scan dropped every `+++` line as a file header, so a
    staged line starting `++` was never scanned."""

    def test_a_staged_line_starting_with_two_pluses_is_scanned_and_the_headers_are_not(self) -> None:
        from shared.staged_secret_scan import added_lines
        diff = ("diff --git a/x.md b/x.md\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/x.md\n"
                "@@ -0,0 +1,2 @@\n+++token = 1\n+plain\ndiff --git a/y.md b/y.md\n--- a/y.md\n+++ b/y.md\n"
                "@@ -1 +1 @@\n-old\n+new\n")
        self.assertEqual(added_lines(diff).split("\n"), ["++token = 1", "plain", "new"])



class GateReviewB(test_m7.LocalTightens):
    """m7 review A #5 and review B #1..#3: what the tool-time gate let through, or refused that it should not."""

    locals().update(inherited(test_m7.LocalTightens))

    def verdict(self, tool: str, tool_input: dict) -> dict:
        payload = {"session_id": "m8", "cwd": str(self.repo), "hook_event_name": "PreToolUse", "tool_name": tool,
                   "tool_input": tool_input}
        out = subprocess.run([sys.executable, "hooks/handlers/pre_tool_use.py"], cwd=self.repo, input=json.dumps(payload),
                             capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        return json.loads(out.stdout or "{}") or {"flow_decision": f"no decision: {out.stderr}"}

    def decide(self, tool: str, tool_input: dict) -> str:
        return self.verdict(tool, tool_input).get("flow_decision", "")

    def committed(self) -> None:
        git(self.repo, "add", "-A")
        git(self.repo, "-c", "user.name=flow-test", "-c", "user.email=flow-test@example.invalid", "commit", "-q",
            "--no-verify", "-m", "flow: install Fusebase Flow")

    @unittest.skipUnless(WINDOWS, "Windows path spellings")
    def test_a_write_by_a_windows_spelling_of_a_protected_path_is_denied(self) -> None:
        # A#5: \\?\, \\?\UNC\, a \\localhost\C$ share, a trailing dot or space and an NTFS stream name the same file
        rules = str((self.repo / "FLOW_RULES.md").resolve())
        drive, rest = rules[0], rules[2:]
        for spelled in (f"\\\\?\\{rules}", f"\\\\?\\UNC\\localhost\\{drive}$\\{rest}", f"\\\\localhost\\{drive}$\\{rest}",
                        f"\\\\.\\{rules}", f"\\\\127.0.0.1\\{drive.lower()}$\\{rest}", rules + ".", rules + " ",
                        rules + "::$DATA", rules.replace("FLOW_RULES.md", "flow_rules.md")):
            self.assertEqual(self.decide("Write", {"file_path": spelled, "content": "x\n"}), "deny", spelled)
        self.assertEqual(self.decide("Write", {"file_path": str(self.repo.resolve() / "src/a.ts"), "content": "x\n"}),
                         "allow")

    def test_a_working_tree_edit_of_a_shipped_policy_loosens_nothing_and_checking_policies_out_is_denied(self) -> None:
        # B#1: the handler read policies/*.yml from the working tree: written by a script, or checked out from an older
        # commit, they emptied the deny list and `git commit --no-verify` went through
        self.committed()
        shipped = self.repo / "policies/command-policy.yml"
        policy = yaml.safe_load(shipped.read_text(encoding="utf-8"))  # a loosened, well-formed policy
        policy["deny"] = [r for r in policy["deny"] if not any(w in str(r.get("pattern")) for w in
                                                               ("verify", "commit", "checkout", "restore"))]
        policy["require_approval"] = []
        shipped.write_text(yaml.safe_dump(policy, sort_keys=False), encoding="utf-8")
        for command in ("git commit --no-verify -m x", "npx prisma migrate deploy"):
            self.assertEqual(self.bash(command), "deny", command)
        for command in ("git checkout HEAD~1 -- policies/", "git checkout HEAD~1 -- policies/command-policy.yml",
                        "git restore --source HEAD~1 policies/command-policy.yml", "git restore policies",
                        "git checkout -- ./policies/secret-patterns.yml"):
            self.assertEqual(self.bash(command), "deny", command)
        for command in ("git checkout main", "git checkout -b policies-fix", "git restore src/policies/rules.ts",
                        "git checkout -- src/app.ts"):
            self.assertEqual(self.bash(command), "allow", command)


class EolPinRun(unittest.TestCase):
    """m7 review A #6: a project's own line spelled like a 5.x pin (`VERSION text eol=lf`, written by the project before
    Flow came) went with the 5.x pins. Only the run of lines a 5.x comment opens goes."""

    def test_a_project_line_spelled_like_a_pin_outside_the_5x_run_stays(self) -> None:
        import eol_pins
        own = "VERSION text eol=lf\nhooks/** text eol=lf\n"
        kept, gone = eol_pins.drop(own + "\n" + test_m7.PINS_5X + test_m7.PROJECT_LINES)
        self.assertEqual(kept, own + "\n" + test_m7.PROJECT_LINES, gone)
        self.assertEqual(len(gone), 21)


if __name__ == "__main__":
    unittest.main(verbosity=2)
