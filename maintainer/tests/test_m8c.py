#!/usr/bin/env python3
"""The 6.0.0-m8 fix pass (reviews A and B held the tag). The command parser's classes left with the parser (the
owner's cut of 2026-10-22); what stays holds for the raw matcher too.
`python maintainer/tests/test_m8c.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import test_m7
import test_m8

CORE = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(CORE / "hooks")]
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

BS = chr(92)  # a backslash, so no escape in this file is read twice
NL = chr(10)


def decision(command: str) -> str:
    reset_cache()
    return evaluate(command, root=CORE).decision


class Gate(unittest.TestCase):
    def assert_denied(self, *commands: str) -> None:
        self.assertEqual([c for c in commands if decision(c) != "deny"], [], "allowed, though the line runs it")

    def assert_allowed(self, *commands: str) -> None:
        self.assertEqual([c for c in commands if decision(c) != "allow"], [], "denied, though the words are data")


class FailsClosed(Gate):
    """Review B H1: an error on the way to the decision let the command run (the hook's exit 1 is non-blocking in
    run-handler.sh). The hook prints a decision on every path, and an error denies."""

    def test_a_code_point_past_unicode_judges_the_line(self) -> None:
        self.assert_denied(f"echo $'{BS}U00110000'; rm -rf /tmp/x", f"X=$'{BS}UFFFFFFFF' fusebase deploy",
                           f"echo $'{BS}U7FFFFFFF' && git commit --no-verify -m x")
        self.assert_allowed(f"echo $'{BS}U00110000'")

    def test_the_hook_prints_a_deny_when_it_fails(self) -> None:
        spec = importlib.util.spec_from_file_location("pre_tool_use_h1", CORE / "hooks/handlers/pre_tool_use.py")
        handler = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(handler)
        with tempfile.TemporaryDirectory() as folder:  # no git root: nothing is written
            event = json.dumps({"tool_name": "Bash", "cwd": folder, "tool_input": {"command": "ls"}})
            out = io.StringIO()
            with mock.patch.object(handler, "evaluate_command", side_effect=RuntimeError("an error on the way")), \
                    mock.patch("sys.stdin", io.StringIO(event)), contextlib.redirect_stdout(out), \
                    contextlib.redirect_stderr(io.StringIO()):
                rc = handler.main()
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(out.getvalue())["flow_decision"], "deny")


class OutsideTheProject(unittest.TestCase):
    """T371 made the hook print a decision on every path, and a call from outside any git work tree (`cd <your-project>`
    from the folder above it, as the upgrade's steps run) then met the policy's fail-closed deny: no git root, no
    policies. Such a call is judged by the rules of the project the handler belongs to."""

    def decide_outside(self, command: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as folder:
            event = {"tool_name": "Bash", "cwd": folder, "hook_event_name": "PreToolUse",
                     "tool_input": {"command": command}}
            out = subprocess.run([sys.executable, str(CORE / "hooks/handlers/pre_tool_use.py")], input=json.dumps(event),
                                 capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=folder,
                                 timeout=300)
        return out.returncode, json.loads(out.stdout or "{}").get("flow_decision", out.stderr[-200:])

    def test_a_call_from_outside_any_git_work_tree_is_judged_by_the_handlers_project(self) -> None:
        self.assertEqual(self.decide_outside("cd fx"), (0, "allow"))
        self.assertEqual(self.decide_outside("rm -rf fx"), (2, "deny"))


def inherited(base: type) -> dict:
    """The base class's tests set to None here: they run in the base's own module."""
    return dict.fromkeys(n for n in dir(base) if n.startswith("test"))


class OlderHooksPush(test_m7.RangeCheck):
    """Review A H1 (it held the 6.0.0-m8 tag): a clone that pulled 6.0.0-m8 still runs 6.0.0-m7's copied pre-push, which
    passes no --remote; the range check then trusted no remote's refs, and a new branch's push was refused for
    protected commits approved and recorded in another clone. With no --remote, every remote's refs count, as in m7."""

    locals().update(inherited(test_m7.RangeCheck))

    def test_a_push_without_remote_trusts_every_remote_as_before_and_a_url_trusts_none(self) -> None:
        rules = self.repo / "FLOW_RULES.md"
        self.commit("FLOW_RULES.md", rules.read_text(encoding="utf-8") + NL + "team" + NL, "T1: recorded elsewhere",
                    "--no-verify")
        self.git("push", "-q", "--no-verify", "origin", "work")
        self.git("checkout", "-q", "-b", "feature")
        tip = self.commit("docs/n.md", "n" + NL, "T2: a note", "--no-verify")
        updates = self.tmp / "updates.txt"
        updates.write_text(f"refs/heads/feature {tip} refs/heads/feature {'0' * 40}" + NL, encoding="utf-8")

        def check(*extra: str) -> int:
            return subprocess.run([sys.executable, "hooks/local/lib/range_check.py", "--push", str(updates), *extra],
                                  cwd=self.repo, capture_output=True, timeout=600).returncode
        self.assertEqual(check(), 0, "6.0.0-m7's pre-push (no --remote) refused a commit the remote holds")
        self.assertEqual(check("--remote", "origin"), 0)
        self.assertNotEqual(check("--remote", str(self.remote)), 0, "a URL trusts no tracking ref")


class NearbyMergeEdits(test_m8.MergeHead):
    """Review A N1 (it held the 6.0.0-m8 tag): `git diff-tree --cc` joins two sides' edits a few lines apart into one
    combined hunk, so a clean merge was refused ("changes src/app.py beyond what its parents hold"); 6.0.0-m7 passed it.
    A file whose staged bytes are git's clean three-way merge is no change of the merge's own."""

    locals().update(inherited(test_m8.MergeHead))

    def lines(self, name: str, edit: dict) -> None:
        test_m8.write(self.repo, name, "".join(f"line {n}{edit.get(n, '')}" + NL for n in range(16)))

    def test_sides_edited_one_to_nine_lines_apart_merge_clean(self) -> None:
        git = test_m8.git
        for gap in (1, 2, 3, 4, 9):  # unchanged lines between the two sides' edits
            name = f"f{gap}.txt"
            self.lines(name, {})
            git(self.repo, "add", "--", name)
            git(self.repo, "commit", "-q", "--no-verify", "-m", f"T1: {name}")
            git(self.repo, "checkout", "-q", "-b", f"side{gap}")
            self.lines(name, {3: " side"})
            git(self.repo, "commit", "-q", "--no-verify", "-am", f"T2: side {gap}")
            git(self.repo, "checkout", "-q", "main")
            self.lines(name, {3 + gap + 1: " main"})
            git(self.repo, "commit", "-q", "--no-verify", "-am", f"T3: main {gap}")
            merged = git(self.repo, "merge", "--no-commit", "--no-ff", f"side{gap}")
            self.assertEqual(merged.returncode, 0, merged.stdout + merged.stderr)
            out = self.subject(f"Merge branch 'side{gap}'")
            self.assertEqual(out.returncode, 0, f"{gap} unchanged lines between the edits: {out.stderr}")
            git(self.repo, "commit", "-q", "--no-verify", "-m", f"Merge branch 'side{gap}'")

    def merge_passes(self, branch: str) -> None:
        merged = test_m8.git(self.repo, "merge", "--no-commit", "--no-ff", branch)
        self.assertEqual(merged.returncode, 0, merged.stdout + merged.stderr)
        out = self.subject(f"Merge branch '{branch}'")
        self.assertEqual(out.returncode, 0, f"{branch}: {out.stderr}")
        test_m8.git(self.repo, "commit", "-q", "--no-verify", "-m", f"Merge branch '{branch}'")

    def commit_all(self, subject: str) -> None:
        test_m8.git(self.repo, "add", "-A")
        test_m8.git(self.repo, "commit", "-q", "--no-verify", "-m", subject)

    def test_a_rename_on_one_side_and_an_edit_on_the_other_merge_clean(self) -> None:
        # review A's re-check: merge-file had no side for a renamed path, so src/renamed.py stayed flagged
        git = test_m8.git
        for near, line in (("near", 2), ("far", 20)):
            src = f"src/ren_{near}.py"
            test_m8.write(self.repo, src, "".join(f"x{n} = {n}" + NL for n in range(30)))
            self.commit_all(f"T1: {src}")
            git(self.repo, "checkout", "-q", "-b", f"side-ren-{near}")
            git(self.repo, "mv", src, f"src/renamed_{near}.py")
            self.commit_all("T2: the rename")
            git(self.repo, "checkout", "-q", "main")
            test_m8.write(self.repo, src, "".join(f"x{n} = {n}{' + 1' if n == line else ''}" + NL for n in range(30)))
            self.commit_all("T3: an edit")
            self.merge_passes(f"side-ren-{near}")

    def test_a_union_file_and_a_criss_cross_merge_merge_clean(self) -> None:
        git = test_m8.git
        test_m8.write(self.repo, ".gitattributes", "notes.txt merge=union" + NL)
        test_m8.write(self.repo, "notes.txt", "first" + NL)
        self.lines("cc.txt", {})
        self.commit_all("T1: base")
        git(self.repo, "checkout", "-q", "-b", "union-side")
        test_m8.write(self.repo, "notes.txt", "first" + NL + "side" + NL)
        self.commit_all("T2: a side note")
        git(self.repo, "checkout", "-q", "main")
        test_m8.write(self.repo, "notes.txt", "first" + NL + "main" + NL)
        self.commit_all("T3: a main note")
        self.merge_passes("union-side")  # merge=union: both appended lines kept
        git(self.repo, "checkout", "-q", "-b", "left")
        self.lines("cc.txt", {2: " left"})
        self.commit_all("T4: left")
        git(self.repo, "checkout", "-q", "-b", "right", "main")
        self.lines("cc.txt", {12: " right"})
        self.commit_all("T5: right")
        git(self.repo, "merge", "-q", "--no-ff", "--no-edit", "left~0")  # right takes left
        git(self.repo, "checkout", "-q", "left")
        git(self.repo, "merge", "-q", "--no-ff", "--no-edit", "right~1")  # left takes right's own commit: criss-cross
        self.lines("cc.txt", {2: " left", 12: " right", 5: " left again"})
        self.commit_all("T6: left again")
        git(self.repo, "checkout", "-q", "right")
        self.lines("cc.txt", {2: " left", 12: " right", 9: " right again"})
        self.commit_all("T7: right again")
        for into, other in (("left", "right"), ("right", "left")):  # both orders
            git(self.repo, "checkout", "-q", "-b", f"cc-into-{into}", into)
            self.merge_passes(other)

    def test_a_resolution_picking_neither_side_and_new_binary_bytes_take_the_subject_rules(self) -> None:
        git = test_m8.git
        self.lines("r.txt", {})
        self.lines("n.txt", {})
        test_m8.write(self.repo, "b.bin", bytes(range(256)))
        self.commit_all("T1: base")
        git(self.repo, "checkout", "-q", "-b", "side-r")
        self.lines("r.txt", {4: " side"})
        self.lines("n.txt", {2: " side"})
        self.commit_all("T2: side")
        git(self.repo, "checkout", "-q", "main")
        self.lines("r.txt", {4: " main"})
        self.lines("n.txt", {5: " main"})
        self.commit_all("T3: main")
        git(self.repo, "merge", "--no-commit", "--no-ff", "side-r")  # a conflict on line 4: merge-tree exits 1
        self.lines("r.txt", {4: " neither"})
        test_m8.write(self.repo, "b.bin", bytes(reversed(range(256))))
        git(self.repo, "add", "--", "r.txt", "b.bin", "n.txt")
        out = self.subject("Merge branch 'side-r'")
        self.assertEqual(out.returncode, 1, "a resolution picking neither side took no subject rule")
        self.assertIn("beyond what its parents hold", out.stderr)
        self.assertIn("r.txt", out.stderr)
        self.assertIn("b.bin", out.stderr)
        self.assertNotIn("n.txt", out.stderr)  # merge-file, the fallback, still finds n.txt merged clean

    def test_an_added_change_in_a_merge_still_takes_the_subject_rules(self) -> None:
        git = test_m8.git
        self.lines("g.txt", {})
        test_m8.write(self.repo, "g.bin", bytes(range(256)))
        self.commit_all("T1: g")
        git(self.repo, "checkout", "-q", "-b", "side-g")
        self.lines("g.txt", {3: " side"})
        git(self.repo, "commit", "-q", "--no-verify", "-am", "T2: side")
        git(self.repo, "checkout", "-q", "main")
        self.lines("g.txt", {6: " main"})
        git(self.repo, "commit", "-q", "--no-verify", "-am", "T3: main")
        git(self.repo, "merge", "--no-commit", "--no-ff", "side-g")  # clean: merge-tree exits 0
        self.lines("g.txt", {3: " side", 6: " main", 9: " added in the merge"})
        test_m8.write(self.repo, "g.bin", bytes(reversed(range(256))))  # bytes neither side has
        git(self.repo, "add", "--", "g.txt", "g.bin")
        out = self.subject("Merge branch 'side-g'")
        self.assertEqual(out.returncode, 1, "an added change took no subject rule")
        self.assertIn("beyond what its parents hold", out.stderr)
        self.assertIn("g.txt", out.stderr)
        self.assertIn("g.bin", out.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
