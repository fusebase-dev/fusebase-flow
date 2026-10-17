#!/usr/bin/env python3
"""flow migrate fixtures: `python maintainer/tests/test_migrate.py` (stdlib unittest).

A synthetic Flow 5.x project is built in a temporary folder and cloned; each test works on the
scratch clone. FLOW_MIGRATE_FIXTURE=<path to a real 5.x project> adds the same abort check on a
scratch clone of that project (done check 5 of milestone 2).
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

FLOW = Path(__file__).resolve().parents[1] / "flow.py"
GIT = ["git", "-c", "user.name=flow-test", "-c", "user.email=flow-test@example.invalid",
       "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false"]
OVERLAY = ("<!-- CUSTOM:SKILL:BEGIN -->\n\n---\n\n## FuseBase Flow — workflow lifecycle overlay\n\n"
           "Fusebase Flow 5.x overlay text.\n\n"
           "<!-- FLOW:PRESERVE:BEGIN (operator-owned — kept verbatim) -->\n| Project name | demo |\n"
           "<!-- FLOW:PRESERVE:END -->\n\n<!-- CUSTOM:SKILL:END -->\n")
FILES = {
    "VERSION": "5.6\n",
    "FLOW_RULES.md": "# Fusebase Flow 5.x rules\n",
    "workflows/verification-gate.md": "# Verification gate\n",
    "flow-skills/communication/SKILL.md": "---\nname: communication\n---\n",
    "hooks/shared/__init__.py": "",
    "policies/module-size-baseline.txt": "# baseline\n821 hooks/local/upgrade.sh\n",
    "hooks/local/upgrade.sh": "#!/usr/bin/env bash\n",
    "AGENTS.md": "# AGENTS.md\n\nCLI text.\n\n" + OVERLAY,
    "scripts/slice.mjs": "read('verification-gate.md')\n",
    "state/approvals/.gitkeep": "",
    ".gitignore": "__pycache__/\nstate/approvals/*\n!state/approvals/.gitkeep\n",
}


def git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([*GIT, *args], cwd=cwd, capture_output=True, text=True, timeout=600)


def migrate(target: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(FLOW), "migrate", "--target", str(target), *extra],
                          capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1800)


def snapshot(root: Path) -> tuple[str, dict[str, str]]:
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all").stdout
    hashes = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            p = Path(dirpath, name)
            hashes[p.relative_to(root).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return status, hashes


def build_project(root: Path) -> None:
    root.mkdir(parents=True)
    git(root, "init", "-q")
    for rel, text in FILES.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_bytes(text.encode("utf-8"))
    assets = [{"path": rel, "sha256": hashlib.sha256((root / rel).read_bytes()).hexdigest()}
              for rel in sorted(FILES) if rel.split("/")[0] in ("workflows", "flow-skills", "hooks", "policies")
              or rel == "FLOW_RULES.md"]
    (root / "audit").mkdir()
    (root / "audit/managed-content-manifest.json").write_text(json.dumps(
        {"schema_version": 1, "flow_version": "5.6", "asset_count": len(assets), "assets": assets}, indent=2) + "\n",
        encoding="utf-8")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "chore: T1 Flow 5.6 project")


class AbortFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        build_project(self.tmp / "origin")
        self.clone = self.tmp / "scratch"
        git(self.tmp, "clone", "-q", "--no-hardlinks", str(self.tmp / "origin"), str(self.clone))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_unedited_dry_run_passes(self) -> None:
        before = snapshot(self.clone)
        run = migrate(self.clone)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("dry run: nothing changed", run.stdout)
        self.assertIn("scripts/slice.mjs: verification-gate", run.stdout)
        self.assertEqual(before, snapshot(self.clone))

    def test_planted_edit_aborts(self) -> None:
        planted = "workflows/verification-gate.md"
        with open(self.clone / planted, "a", encoding="utf-8", newline="\n") as fh:
            fh.write("a project edit inside a Flow-owned file\n")
        before = snapshot(self.clone)
        run = migrate(self.clone)
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertIn("changed-by-both", run.stdout)
        self.assertIn(planted, run.stdout)
        self.assertEqual(before, snapshot(self.clone), "the aborted run changed the tree")


class RemovalFallback(unittest.TestCase):
    def test_refused_deletion_moves_the_file_into_the_backup(self) -> None:
        sys.path.insert(0, str(FLOW.parent))
        import migrate
        import migrate_apply
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            build_project(tmp / "origin")
            clone = tmp / "scratch"
            git(tmp, "clone", "-q", "--no-hardlinks", str(tmp / "origin"), str(clone))
            inv = migrate.inventory(clone.resolve(), {"claude", "codex"})
            folder, _ = migrate_apply.backup(inv, "20990101T000000Z")

            def refuse(self: Path, *args: object, **kwargs: object) -> None:
                raise PermissionError(13, "deletion refused by the surface", str(self))

            with mock.patch.object(Path, "unlink", refuse), mock.patch("os.chmod"):
                moved, failed, _ = migrate_apply.remove(inv, folder)
            self.assertEqual(failed, [])
            self.assertEqual(sorted(moved), sorted(inv.removals()))
            self.assertTrue(moved)
            for rel in moved:
                self.assertFalse((clone / rel).exists(), rel)
                self.assertTrue((folder / migrate_apply.backup_rel(rel)).is_file(), rel)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


class ApplyEndToEnd(unittest.TestCase):
    def test_second_apply_is_a_no_op_and_rollback_is_one_checkout(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            build_project(tmp / "origin")
            clone = tmp / "scratch"
            git(tmp, "clone", "-q", "--no-hardlinks", str(tmp / "origin"), str(clone))
            git(clone, "config", "user.name", "flow-test")
            git(clone, "config", "user.email", "flow-test@example.invalid")
            pre = git(clone, "rev-parse", "HEAD").stdout.strip()
            run = migrate(clone, "--apply", "--go-ahead")
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("committed: ", run.stdout)
            self.assertIn("chore(flow): T2 migrate Fusebase Flow 5.6 to ", run.stdout)
            self.assertEqual(git(clone, "status", "--porcelain").stdout, "")
            self.assertEqual(sorted(p.name for p in (clone / "state/approvals").iterdir()), [".gitkeep"])
            self.assertFalse((clone / "workflows/verification-gate.md").exists())
            again = migrate(clone, "--apply", "--go-ahead")
            self.assertEqual(again.returncode, 0, again.stdout)
            self.assertIn("nothing to migrate", again.stdout)
            self.assertEqual(git(clone, "status", "--porcelain").stdout, "")
            after = git(clone, "rev-parse", "HEAD").stdout.strip()
            self.assertEqual(git(clone, "checkout", "-q", pre).returncode, 0)
            self.assertEqual((clone / "FLOW_RULES.md").read_text(encoding="utf-8"), FILES["FLOW_RULES.md"])
            self.assertTrue((clone / "workflows/verification-gate.md").is_file())
            self.assertEqual(git(clone, "checkout", "-q", "-").returncode, 0)
            self.assertEqual(git(clone, "rev-parse", "HEAD").stdout.strip(), after)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


@unittest.skipUnless(os.environ.get("FLOW_MIGRATE_FIXTURE"), "FLOW_MIGRATE_FIXTURE not set")
class RealProjectAbort(unittest.TestCase):
    def test_planted_edit_aborts_on_a_scratch_clone(self) -> None:
        source = Path(os.environ["FLOW_MIGRATE_FIXTURE"])
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-real-"))
        try:
            clone = tmp / "scratch"
            git(tmp, "clone", "-q", "--no-hardlinks", str(source), str(clone))
            git(clone, "checkout", "-q", git(source, "rev-parse", "HEAD").stdout.strip())
            assets = json.loads((clone / "audit/managed-content-manifest.json").read_text(encoding="utf-8"))["assets"]
            planted = assets[len(assets) // 2]["path"]
            with open(clone / planted, "a", encoding="utf-8", newline="\n") as fh:
                fh.write("a project edit inside a Flow-owned file\n")
            before = snapshot(clone)
            run = migrate(clone, "--providers", "claude,codex")
            print(f"\n[real fixture] planted: {planted}; exit {run.returncode}\n{run.stdout.strip()}")
            self.assertNotEqual(run.returncode, 0)
            self.assertIn(planted, run.stdout)
            self.assertEqual(before, snapshot(clone), "the aborted run changed the tree")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
