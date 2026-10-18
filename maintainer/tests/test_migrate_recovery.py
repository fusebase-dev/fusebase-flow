"""flow migrate: the undo of a completed migration, the rollback of a part-way apply and the finish-by-hand
steps, each pasted as printed. `python maintainer/tests/test_migrate.py` runs these tests with the others.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from synthetic import FLOW, blob, git, migrate, scratch_clone, snapshot


# the git hooks of a 5.x project: committed under hooks/git/, installed byte for byte into .git/hooks
HOOKS_5X = {f"hooks/git/{h}": f"#!/usr/bin/env bash\n# fusebase-flow-managed-hook: v1\n# Flow 5.6 {h}\nexit 0\n"
            for h in ("pre-commit", "commit-msg", "pre-push")}
# Husky v5 to v8 track their hooks here and set core.hooksPath to it on npm install (review S1)
HUSKY = {".husky/pre-commit": "#!/usr/bin/env sh\n# the project's own Husky hook\nnpm test\n"}
# the same core.autocrlf as the git() helper, so the restored files compare byte for byte
AUTOCRLF_OFF = {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.autocrlf", "GIT_CONFIG_VALUE_0": "false"}


def plant_5x_hooks(clone: Path) -> None:
    for rel, text in HOOKS_5X.items():
        (clone / ".git/hooks" / Path(rel).name).write_bytes(text.encode("utf-8"))


def assert_5x_hooks(test: unittest.TestCase, clone: Path) -> None:
    for rel, text in HOOKS_5X.items():
        hook = clone / ".git/hooks" / Path(rel).name
        test.assertEqual(hook.read_bytes() if hook.is_file() else None, text.encode("utf-8"), rel)


def hooks_in(clone: Path) -> dict[str, str]:
    """The sha256 of each git hook in .git/hooks, or 'absent'."""
    return {h: hashlib.sha256((clone / ".git/hooks" / h).read_bytes()).hexdigest()
            if (clone / ".git/hooks" / h).is_file() else "absent" for h in ("pre-commit", "commit-msg", "pre-push")}


def files_under(root: Path, folder: str) -> dict[str, str]:
    return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8")
            for p in sorted((root / folder).rglob("*")) if p.is_file()}


def tracked(clone: Path) -> dict[str, str]:
    paths = git(clone, "ls-files", "-z").stdout.split("\0")
    return {p: hashlib.sha256((clone / p).read_bytes()).hexdigest() for p in paths if p}


def pasted(output: str) -> str:
    """The block an output prints for the operator to paste, `( set -e` to `)`, as printed."""
    lines = output.splitlines()
    start = lines.index("( set -e")
    return "\n".join(lines[start:lines.index(")", start) + 1]) + "\n"


def paste(clone: Path, text: str, env: dict[str, str] | None = None) -> tuple[int | None, str]:
    """Pastes `text` into one bash session as a unit: its exit status (None when it ended the session, as a top-level
    set -e or exit ends the operator's shell) and the session's output."""
    done = subprocess.run([shutil.which("bash") or "bash"], input=(text + 'echo "block exit=$?"\n').encode("utf-8"),
                          cwd=clone, env=env or dict(os.environ, **AUTOCRLF_OFF), capture_output=True, timeout=1800)
    out = (done.stdout + done.stderr).decode("utf-8", "replace")
    status = [line for line in out.splitlines() if line.startswith("block exit=")]
    return (int(status[-1][len("block exit="):]) if status else None), out


def copy_of(clone: Path, dst: Path) -> Path:
    """A copy of a migrated clone, .git included, for one test to change."""
    shutil.copytree(clone, dst, symlinks=True)
    return dst


def outside_backup(snap: tuple[str, dict[str, str]]) -> tuple[str, dict[str, str]]:
    return snap[0], {p: h for p, h in snap[1].items() if not p.startswith(".flow-migrate-")}


class Interrupted(unittest.TestCase):
    def test_a_stop_right_after_removal_prints_the_rollback_and_no_commit(self) -> None:
        self.rolled_back(hooks_path=False, locked=False)

    def test_the_rollback_puts_the_hooks_back_in_git_hooks_when_core_hookspath_is_set(self) -> None:
        self.rolled_back(hooks_path=True, locked=False)

    def test_a_failing_step_stops_the_rollback_with_nothing_else_changed(self) -> None:
        self.rolled_back(hooks_path=False, locked=True)

    def rolled_back(self, hooks_path: bool, locked: bool) -> None:
        sys.path.insert(0, str(FLOW.parent))
        import migrate as mig
        import migrate_apply as mapply
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            clone = scratch_clone(tmp, {**HOOKS_5X, **HUSKY})
            plant_5x_hooks(clone)
            (clone / "hooks/shared/__pycache__").mkdir()
            (clone / "hooks/shared/__pycache__/x.cpython-312.pyc").write_bytes(b"\x00untracked bytecode")
            with open(clone / "scripts/slice.mjs", "a", encoding="utf-8", newline="\n") as fh:
                fh.write("// the operator's own edit, outside the migration's paths\n")
            before = snapshot(clone)
            inv = mig.inventory(clone.resolve(), {"claude", "codex"})
            folder, _ = mapply.backup(inv, "20990101T000000Z")
            mapply.remove(inv, folder)  # the apply stops here
            self.assertFalse((clone / "audit/managed-content-manifest.json").exists())
            if hooks_path:
                git(clone, "config", "core.hooksPath", ".husky")
            run = migrate(clone)
            self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
            self.assertIn("stopped part-way", run.stdout)
            self.assertNotIn("git commit", run.stdout)
            rollback = pasted(run.stdout)
            self.assertFalse("checkout -- ." in rollback or "reset" in rollback, rollback)
            if locked:  # another git process holds the index, so the block's first step fails
                (clone / ".git/index.lock").write_bytes(b"")
                stopped, hooks = snapshot(clone), hooks_in(clone)
                status, out = paste(clone, rollback)
                self.assertEqual(hooks_in(clone), hooks, f".git/hooks changed after the first step failed:\n{out}")
                self.assertEqual(snapshot(clone), stopped, f"the tree changed after the first step failed:\n{out}")
                self.assertTrue(status, f"block exit={status}:\n{out}")
                (clone / ".git/index.lock").unlink()
            status, out = paste(clone, rollback)
            self.assertEqual(status, 0, out)
            assert_5x_hooks(self, clone)
            self.assertEqual(files_under(clone, ".husky"), HUSKY)
            self.assertEqual(outside_backup(before), outside_backup(snapshot(clone)))  # the operator's edit included
            if hooks_path:  # the preflight stops on it
                git(clone, "config", "--unset", "core.hooksPath")
            git(clone, "checkout", "--", "scripts/slice.mjs")  # the preflight wants a clean tracked tree again
            again = migrate(clone)
            self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


class Undo(unittest.TestCase):
    """A completed migration in a folder whose path has a space, undone by the block it printed, pasted as printed.
    Each test pastes it into its own copy of the migrated clone."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow migrate "))
        cls.clone = scratch_clone(cls.tmp, {**HOOKS_5X, **HUSKY})
        plant_5x_hooks(cls.clone)
        (cls.clone / "hooks/shared/__pycache__").mkdir()
        (cls.clone / "hooks/shared/__pycache__/x.cpython-312.pyc").write_bytes(b"\x00untracked bytecode")
        cls.pre, cls.before = git(cls.clone, "rev-parse", "HEAD").stdout.strip(), tracked(cls.clone)
        cls.applied = migrate(cls.clone, "--apply", "--go-ahead")
        cls.undo = pasted(cls.applied.stdout.split("to undo the migration", 1)[-1]) if not cls.applied.returncode else ""
        cls.stamp = next(cls.clone.glob(".flow-migrate-*")).name.split("-")[-1]

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_the_printed_undo_restores_the_tree_and_the_5x_hooks(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        self.assertEqual(len(self.undo.splitlines()), 6, self.undo)
        ledger = blob(self.clone, "HEAD:docs/flow/ledger.md").decode("utf-8")
        for text in (self.applied.stdout, ledger):
            self.assertNotIn("reset --hard", text)
            self.assertIn(self.undo, text)
        clone = copy_of(self.clone, self.tmp / "undone")
        status, out = paste(clone, self.undo)
        self.assertEqual(status, 0, out)
        self.assertEqual(git(clone, "rev-parse", "HEAD").stdout.strip(), self.pre)
        self.assertEqual(git(clone, "status", "--porcelain", "--untracked-files=no").stdout, "")
        self.assertEqual(tracked(clone), self.before)
        assert_5x_hooks(self, clone)
        self.assertTrue((clone / "hooks/shared/__pycache__/x.cpython-312.pyc").is_file())

    def test_the_undo_puts_the_hooks_back_in_git_hooks_when_core_hookspath_is_set(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        clone = copy_of(self.clone, self.tmp / "husky")
        git(clone, "config", "core.hooksPath", ".husky")
        status, out = paste(clone, self.undo)
        self.assertEqual(status, 0, out)
        assert_5x_hooks(self, clone)
        self.assertEqual(files_under(clone, ".husky"), HUSKY)
        self.assertEqual(tracked(clone), self.before)

    def test_a_failing_first_step_stops_the_undo_with_nothing_else_changed(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        clone = copy_of(self.clone, self.tmp / "dirty")
        with open(clone / "docs/flow/ledger.md", "a", encoding="utf-8", newline="\n") as fh:
            fh.write("a row the 6.0 lifecycle wrote, not committed yet\n")  # git checkout -b refuses to drop it
        before, hooks, head = snapshot(clone), hooks_in(clone), git(clone, "rev-parse", "HEAD").stdout.strip()
        status, out = paste(clone, self.undo)
        self.assertEqual(hooks_in(clone), hooks, f".git/hooks changed after the first step failed:\n{out}")
        self.assertFalse((clone / "hooks/shared/__pycache__/x.cpython-312.pyc").exists(), "an untracked file was copied")
        self.assertEqual(snapshot(clone), before, out)
        self.assertTrue(status, f"block exit={status}:\n{out}")
        self.assertIn("would be overwritten by checkout", out)
        self.assertEqual(git(clone, "rev-parse", "HEAD").stdout.strip(), head)
        self.assertEqual(git(clone, "branch", "--list", "flow-5x-*").stdout, "")

    def test_without_the_backup_folder_the_hooks_come_from_the_5x_tree(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        clone = copy_of(self.clone, self.tmp / "no backup")
        shutil.rmtree(next(clone.glob(".flow-migrate-*")))  # the migration report says to, once it is accepted
        status, out = paste(clone, self.undo)
        assert_5x_hooks(self, clone)  # the pre-migration commit's hooks/git/ copies
        self.assertEqual(status, 0, out)
        self.assertIn("NOTE: the backup folder .flow-migrate-", out)
        self.assertIn("cannot be restored", out)
        self.assertEqual(git(clone, "rev-parse", "HEAD").stdout.strip(), self.pre)
        self.assertEqual(git(clone, "status", "--porcelain", "--untracked-files=no").stdout, "")
        self.assertEqual(tracked(clone), self.before)
        self.assertFalse((clone / "hooks/shared/__pycache__/x.cpython-312.pyc").exists())
        if os.name != "nt":
            for h in ("pre-commit", "commit-msg", "pre-push"):
                self.assertTrue(os.access(clone / ".git/hooks" / h, os.X_OK), h)

    def test_the_release_note_states_the_printed_undo_word_for_word(self) -> None:
        core = FLOW.parents[1]
        note = (core / "maintainer/release-notes" / f"{(core / 'VERSION').read_text().strip()}.md").read_text("utf-8")
        start = note.index("( set -e\n")
        printed = self.undo.replace(self.stamp, "<UTC time>").replace(self.pre, "<the pre-migration commit>")
        self.assertEqual(note[start:note.index("\n)\n", start) + 3], printed)


class UndoWithoutHookCopies(unittest.TestCase):
    def test_without_the_backup_folder_or_tree_hooks_the_undo_stops_before_any_change(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="flow migrate "))
        try:
            clone = scratch_clone(tmp)  # a 5.x project whose commit has no hooks/git/ copies
            applied = migrate(clone, "--apply", "--go-ahead")
            self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
            undo = pasted(applied.stdout.split("to undo the migration", 1)[-1])
            shutil.rmtree(next(clone.glob(".flow-migrate-*")))
            before, hooks = snapshot(clone), hooks_in(clone)
            head, branches = git(clone, "rev-parse", "HEAD").stdout, git(clone, "branch", "--list").stdout
            status, out = paste(clone, undo)
            self.assertEqual(hooks_in(clone), hooks, f".git/hooks changed:\n{out}")
            self.assertEqual(git(clone, "rev-parse", "HEAD").stdout, head, out)
            self.assertEqual(git(clone, "branch", "--list").stdout, branches, out)
            self.assertEqual(snapshot(clone), before, out)
            self.assertTrue(status, f"block exit={status}:\n{out}")
            self.assertIn("STOPPED", out)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


MINT = "FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh --slug flow-migrate"
CONSUME = "bash hooks/local/write-bootstrap-approval.sh --consume --slug flow-migrate"


class CommitFailure(unittest.TestCase):
    """One migration whose commit fails in the pre-commit, shared by the tests below; each works on its own copy."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        cls.clone = scratch_clone(cls.tmp)
        cls.pre = git(cls.clone, "rev-parse", "HEAD").stdout.strip()
        cls.plain = {k: v for k, v in os.environ.items() if k != "FUSEBASE_FLOW_LINT"}
        # passes the preflight (no ledger yet) and fails the commit's pre-commit, like a lint rule over a Flow path
        failing = dict(cls.plain, FUSEBASE_FLOW_LINT="test ! -e docs/flow/ledger.md")
        cls.failed = migrate(cls.clone, "--apply", "--go-ahead", env=failing)

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_a_failed_commit_keeps_the_approval_and_every_printed_step_finishes_it_twice(self) -> None:
        run, plain, pre = self.failed, self.plain, self.pre
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn("lint failed", run.stdout + run.stderr)
        clone = copy_of(self.clone, self.tmp / "twice")
        kept = sorted((clone / "state/approvals").glob("protected_path_edit-flow-migrate-*.json"))
        self.assertEqual(len(kept), 1, "the approval was consumed although the commit failed")
        text = pasted(run.stdout)
        self.assertIn(f"  {MINT}", text.splitlines())
        self.assertEqual(text.splitlines()[-2:], [f"  {CONSUME}", ")"])
        again = migrate(clone, env=plain)
        self.assertEqual(again.returncode, 1, again.stdout)
        self.assertIn("applied but not committed", again.stdout)
        self.assertEqual(pasted(again.stdout), text)
        message = next(clone.glob(".flow-migrate-*/.migrate/message.txt")).read_text(encoding="utf-8")
        for attempt in (1, 2):  # the cause is gone; the whole block is safe to paste again
            status, out = paste(clone, text, plain)
            self.assertEqual(status, 0, f"attempt {attempt}:\n{out}")
            self.assertEqual(git(clone, "status", "--porcelain").stdout, "")
            self.assertEqual(sorted(p.name for p in (clone / "state/approvals").iterdir()), [".gitkeep"])
            self.assertEqual(git(clone, "rev-parse", "HEAD~1").stdout.strip(), pre)
            self.assertEqual(git(clone, "log", "-1", "--format=%B").stdout.strip(), message.strip())
        self.assertIn("nothing to migrate", migrate(clone, env=plain).stdout)

    def test_another_staged_path_stops_the_steps_before_the_commit(self) -> None:
        self.assertEqual(self.failed.returncode, 1, self.failed.stdout + self.failed.stderr)
        clone = copy_of(self.clone, self.tmp / "stray")
        (clone / "notes.txt").write_text("the operator's own change\n", encoding="utf-8")
        git(clone, "add", "--", "notes.txt")
        approval = next((clone / "state/approvals").glob("protected_path_edit-flow-migrate-*.json"))
        kept = approval.read_bytes()
        status, out = paste(clone, pasted(self.failed.stdout), self.plain)
        head = git(clone, "show", "--name-only", "--format=%s", "HEAD").stdout.splitlines()
        self.assertEqual(git(clone, "rev-parse", "HEAD").stdout.strip(), self.pre,
                         f"the block committed '{head[0]}', {len(head) - 2} paths, notes.txt among them: "
                         f"{'notes.txt' in head}")
        self.assertIn("notes.txt", git(clone, "diff", "--cached", "--name-only").stdout.split())
        self.assertTrue(status, f"block exit={status}:\n{out}")
        self.assertIn("notes.txt\nSTOPPED: the paths above are staged but are not part of the migration", out)
        self.assertEqual(approval.read_bytes(), kept, "the block went on to the mint")


if __name__ == "__main__":
    unittest.main(verbosity=2)
