"""flow migrate: the undo of a completed migration, the rollback of a part-way apply and the finish-by-hand
steps, each run as printed. `python maintainer/tests/test_migrate.py` runs these tests with the others.
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


def plant_5x_hooks(clone: Path) -> None:
    for rel, text in HOOKS_5X.items():
        (clone / ".git/hooks" / Path(rel).name).write_bytes(text.encode("utf-8"))


def assert_5x_hooks(test: unittest.TestCase, clone: Path) -> None:
    for rel, text in HOOKS_5X.items():
        hook = clone / ".git/hooks" / Path(rel).name
        test.assertEqual(hook.read_bytes() if hook.is_file() else None, text.encode("utf-8"), rel)


def files_under(root: Path, folder: str) -> dict[str, str]:
    return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8")
            for p in sorted((root / folder).rglob("*")) if p.is_file()}


def tracked(clone: Path) -> dict[str, str]:
    paths = git(clone, "ls-files", "-z").stdout.split("\0")
    return {p: hashlib.sha256((clone / p).read_bytes()).hexdigest() for p in paths if p}


def steps(output: str) -> list[str]:
    """The commands a message prints as `[flow migrate]   $ <command>`."""
    return [line.split("$ ", 1)[1] for line in output.splitlines() if line.startswith("[flow migrate]   $ ")]


def run_steps(test: unittest.TestCase, clone: Path, commands: list[str]) -> None:
    # the same core.autocrlf as the git() helper, so the restored files compare byte for byte
    env = dict(os.environ, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.autocrlf", GIT_CONFIG_VALUE_0="false")
    for step in commands:
        done = subprocess.run([shutil.which("bash") or "bash", "-c", step], cwd=clone, env=env,
                              capture_output=True, text=True, timeout=600)
        test.assertEqual(done.returncode, 0, f"{step}\n{done.stdout}{done.stderr}")


def outside_backup(snap: tuple[str, dict[str, str]]) -> tuple[str, dict[str, str]]:
    return snap[0], {p: h for p, h in snap[1].items() if not p.startswith(".flow-migrate-")}


class Interrupted(unittest.TestCase):
    def test_a_stop_right_after_removal_prints_the_rollback_and_no_commit(self) -> None:
        self.rolled_back(hooks_path=False)

    def test_the_rollback_puts_the_hooks_back_in_git_hooks_when_core_hookspath_is_set(self) -> None:
        self.rolled_back(hooks_path=True)

    def rolled_back(self, hooks_path: bool) -> None:
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
            rollback = steps(run.stdout)
            self.assertFalse([s for s in rollback if "checkout -- ." in s or "reset" in s], rollback)
            run_steps(self, clone, rollback)
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
    """A completed migration in a folder whose path has a space, undone by the steps it printed, run as printed."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow migrate "))
        cls.clone = scratch_clone(cls.tmp, {**HOOKS_5X, **HUSKY})
        plant_5x_hooks(cls.clone)
        (cls.clone / "hooks/shared/__pycache__").mkdir()
        (cls.clone / "hooks/shared/__pycache__/x.cpython-312.pyc").write_bytes(b"\x00untracked bytecode")
        cls.pre, cls.before = git(cls.clone, "rev-parse", "HEAD").stdout.strip(), tracked(cls.clone)
        cls.applied = migrate(cls.clone, "--apply", "--go-ahead")
        cls.undo = steps(cls.applied.stdout.split("to undo the migration", 1)[-1])
        cls.stamp = next(cls.clone.glob(".flow-migrate-*")).name.split("-")[-1]
        cls.husky = cls.tmp / "husky"  # each undo test runs on its own copy of the migrated clone
        shutil.copytree(cls.clone, cls.husky, symlinks=True)

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_the_printed_undo_restores_the_tree_and_the_5x_hooks(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        self.assertEqual(len(self.undo), 3, self.applied.stdout)
        ledger = blob(self.clone, "HEAD:docs/flow/ledger.md").decode("utf-8")
        for text in (self.applied.stdout, ledger):
            self.assertNotIn("reset --hard", text)
            self.assertTrue(all(step in text for step in self.undo))
        run_steps(self, self.clone, self.undo)
        self.assertEqual(git(self.clone, "rev-parse", "HEAD").stdout.strip(), self.pre)
        self.assertEqual(git(self.clone, "status", "--porcelain", "--untracked-files=no").stdout, "")
        self.assertEqual(tracked(self.clone), self.before)
        assert_5x_hooks(self, self.clone)
        self.assertTrue((self.clone / "hooks/shared/__pycache__/x.cpython-312.pyc").is_file())

    def test_the_undo_puts_the_hooks_back_in_git_hooks_when_core_hookspath_is_set(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        git(self.husky, "config", "core.hooksPath", ".husky")
        run_steps(self, self.husky, self.undo)
        assert_5x_hooks(self, self.husky)
        self.assertEqual(files_under(self.husky, ".husky"), HUSKY)
        self.assertEqual(tracked(self.husky), self.before)

    def test_the_release_note_states_the_printed_undo_word_for_word(self) -> None:
        core = FLOW.parents[1]
        note = (core / "maintainer/release-notes" / f"v{(core / 'VERSION').read_text().strip()}.md").read_text("utf-8")
        block = note.split("```\ngit checkout -b flow-5x-", 1)[-1].split("```", 1)[0]
        printed = [s.replace(self.stamp, "<UTC time>").replace(self.pre, "<the pre-migration commit>")
                   for s in self.undo]
        self.assertEqual(("git checkout -b flow-5x-" + block).splitlines(), printed)


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

    def copy(self, name: str) -> Path:
        shutil.copytree(self.clone, self.tmp / name, symlinks=True)
        return self.tmp / name

    def test_a_failed_commit_keeps_the_approval_and_every_printed_step_finishes_it_twice(self) -> None:
        run, plain, pre = self.failed, self.plain, self.pre
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn("lint failed", run.stdout + run.stderr)
        clone = self.copy("twice")
        kept = sorted((clone / "state/approvals").glob("protected_path_edit-flow-migrate-*.json"))
        self.assertEqual(len(kept), 1, "the approval was consumed although the commit failed")
        commands = steps(run.stdout)
        self.assertIn(MINT, commands)
        self.assertEqual(commands[-1], CONSUME)
        again = migrate(clone, env=plain)
        self.assertEqual(again.returncode, 1, again.stdout)
        self.assertIn("applied but not committed", again.stdout)
        self.assertEqual(steps(again.stdout), commands)
        message = next(clone.glob(".flow-migrate-*/.migrate/message.txt")).read_text(encoding="utf-8")
        for attempt in (1, 2):  # the cause is gone; every step is safe to run again
            for step in commands:
                done = subprocess.run([shutil.which("bash") or "bash", "-c", step], cwd=clone, env=plain,
                                      capture_output=True, text=True, timeout=1800)
                self.assertEqual(done.returncode, 0, f"attempt {attempt}: {step}\n{done.stdout}{done.stderr}")
            self.assertEqual(git(clone, "status", "--porcelain").stdout, "")
            self.assertEqual(sorted(p.name for p in (clone / "state/approvals").iterdir()), [".gitkeep"])
            self.assertEqual(git(clone, "rev-parse", "HEAD~1").stdout.strip(), pre)
            self.assertEqual(git(clone, "log", "-1", "--format=%B").stdout.strip(), message.strip())
        self.assertIn("nothing to migrate", migrate(clone, env=plain).stdout)

    def test_another_staged_path_stops_the_steps_before_the_commit(self) -> None:
        self.assertEqual(self.failed.returncode, 1, self.failed.stdout + self.failed.stderr)
        clone = self.copy("stray")
        (clone / "notes.txt").write_text("the operator's own change\n", encoding="utf-8")
        git(clone, "add", "--", "notes.txt")
        ran = []
        for step in steps(self.failed.stdout):  # in order, as printed, up to the first step that fails
            ran.append((step, subprocess.run([shutil.which("bash") or "bash", "-c", step], cwd=clone, env=self.plain,
                                             capture_output=True, text=True, timeout=1800)))
            if ran[-1][1].returncode:
                break
        head = git(clone, "show", "--name-only", "--format=%s", "HEAD").stdout.splitlines()
        self.assertEqual(git(clone, "rev-parse", "HEAD").stdout.strip(), self.pre,
                         f"the steps committed '{head[0]}', {len(head) - 2} paths, notes.txt among them: {'notes.txt' in head}")
        self.assertIn("notes.txt", git(clone, "diff", "--cached", "--name-only").stdout.split())
        step, done = ran[-1]
        self.assertTrue(done.returncode and "grep" in step, step)
        self.assertIn("notes.txt", done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
