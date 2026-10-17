#!/usr/bin/env python3
"""flow migrate fixtures: `python maintainer/tests/test_migrate.py` (stdlib unittest).

A synthetic Flow 5.x project is built in a temporary folder and cloned; each test works on the
scratch clone. FLOW_MIGRATE_FIXTURE=<path to a real 5.x project> adds the same abort check on a
scratch clone of that project (done check 5 of milestone 2).
"""
from __future__ import annotations

import contextlib
import hashlib
import io
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


def migrate(target: Path, *extra: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(FLOW), "migrate", "--target", str(target), *extra], env=env,
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
    # manifest_self_sha256 as Flow 5.x's managed_content_manifest.py records it: the migrator trusts the record by it
    self_sha = hashlib.sha256(json.dumps({"schema_version": 1, "flow_version": "5.6", "assets": assets},
                                         sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    (root / "audit/managed-content-manifest.json").write_bytes((json.dumps(
        {"schema_version": 1, "flow_version": "5.6", "asset_count": len(assets), "manifest_self_sha256": self_sha,
         "assets": assets}, indent=2) + "\n").encode("utf-8"))
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "chore: T1 Flow 5.6 project")


def scratch_clone(tmp: Path) -> Path:
    """A clone of a fresh synthetic 5.6 project, with a committer identity for the migration commit."""
    build_project(tmp / "origin")
    clone = tmp / "scratch"
    git(tmp, "clone", "-q", "--no-hardlinks", str(tmp / "origin"), str(clone))
    git(clone, "config", "user.name", "flow-test")
    git(clone, "config", "user.email", "flow-test@example.invalid")
    return clone


def commit_file(clone: Path, rel: str, data: bytes, subject: str) -> None:
    (clone / rel).parent.mkdir(parents=True, exist_ok=True)
    (clone / rel).write_bytes(data)
    git(clone, "add", "--", rel)
    git(clone, "commit", "-q", "-m", subject)


def blob(clone: Path, spec: str) -> bytes:
    return subprocess.run([*GIT, "cat-file", "blob", spec], cwd=clone, capture_output=True, timeout=600).stdout


def install(target: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(FLOW), "install", "--target", str(target)],
                          capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1800)


def listed(output: str, key: str) -> list[str]:
    """The paths install prints under `[flow] <key>: N`."""
    lines, found, inside = output.splitlines(), [], False
    for line in lines:
        if line.startswith(f"[flow] {key}: "):
            inside = True
        elif inside and line.startswith("[flow]   "):
            found.append(line[len("[flow]   "):].split(" (")[0])
        elif inside:
            break
    return found


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


GIT_CRLF = [GIT[0], *GIT[1:-2], "-c", "core.autocrlf=true"]  # a Windows checkout
# CRLF pairs and NUL bytes; the GIF has no NUL, so only the project's own `*.gif binary` line makes it binary
BINARIES = {"templates/logo.png": b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\r\n", "hooks/blob.bin": b"BIN\r\n\x00\x01\r\nEND",
            "templates/plain.gif": b"GIF89a\r\nno NUL byte\r\n"}


class ApplyEndToEnd(unittest.TestCase):
    """One migration of the synthetic project, shared by the checks below (an apply takes minutes on a loaded host)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        cls.clone = scratch_clone(cls.tmp)
        commit_file(cls.clone, ".gitattributes", b"*.png binary\n*.gif binary\n", "chore: T1 the project's attributes")
        cls.pre = git(cls.clone, "rev-parse", "HEAD").stdout.strip()
        cls.applied = migrate(cls.clone, "--apply", "--go-ahead")

    def test_binaries_in_flow_folders_keep_their_bytes(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        fresh = self.tmp / "binaries"
        run = lambda *args: subprocess.run([*GIT_CRLF, *args], cwd=fresh, capture_output=True, timeout=600)
        subprocess.run([*GIT_CRLF, "clone", "-q", "--no-hardlinks", str(self.clone), str(fresh)], timeout=600)
        for rel, data in BINARIES.items():
            (fresh / rel).write_bytes(data)
        self.assertEqual(run("add", "--", *BINARIES).returncode, 0)
        self.assertEqual(run("commit", "-q", "-m", "chore: T3 the project's binaries").returncode, 0)
        attrs = run("check-attr", "text", "--", *BINARIES).stdout.decode()
        for rel in BINARIES:
            self.assertNotIn(f"{rel}: text: set", attrs)
        self.assertEqual(run("checkout", "-q", self.pre).returncode, 0)
        self.assertEqual(run("checkout", "-q", "-").returncode, 0)
        for rel, data in BINARIES.items():
            self.assertEqual((fresh / rel).read_bytes(), data, rel)
            self.assertEqual(run("cat-file", "blob", f"HEAD:{rel}").stdout, data, rel)
        for rel in ("docs/flow/ledger.md", "audit/flow-install.json", "VERSION", ".codex/agents/builder.toml",
                    ".claude/skills/plan/SKILL.md", "workflows/lifecycle.md", "hooks/git/pre-commit"):
            self.assertNotIn(b"\r", (fresh / rel).read_bytes(), rel)

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_generated_files_are_lf_and_pinned_lf(self) -> None:
        clone = self.clone
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        generated = ["docs/flow/backlog.md", "docs/flow/phases.md", "docs/flow/evidence.md", "docs/flow/ledger.md",
                     "audit/flow-install.json", "VERSION", ".codex/agents/builder.toml", ".codex/agents/planner.toml",
                     "policies/module-size-baseline.txt", ".claude/skills/plan/SKILL.md", "workflows/lifecycle.md"]
        for rel in generated:
            self.assertNotIn(b"\r", (clone / rel).read_bytes(), rel)
        attrs = git(clone, "check-attr", "eol", "--", *generated).stdout
        for rel in generated:
            self.assertIn(f"{rel}: eol: lf", attrs)
        # a Windows checkout (core.autocrlf=true) of the migration commit keeps them LF
        fresh = self.tmp / "fresh"
        done = subprocess.run(["git", "-c", "core.autocrlf=true", "clone", "-q", "--no-hardlinks", str(clone), str(fresh)],
                              capture_output=True, text=True, timeout=600)
        self.assertEqual(done.returncode, 0, done.stderr)
        for rel in generated:
            self.assertNotIn(b"\r", (fresh / rel).read_bytes(), f"{rel} in a core.autocrlf=true clone")
        self.assertNotIn("AGENTS.md: eol: lf", git(clone, "check-attr", "eol", "--", "AGENTS.md", "src/app.ts").stdout)

    def test_second_apply_is_a_no_op_and_rollback_is_one_checkout(self) -> None:
        clone, run, pre = self.clone, self.applied, self.pre
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


class BaselineCarry(unittest.TestCase):
    def test_a_project_row_is_carried_and_a_following_install_keeps_it(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            clone = scratch_clone(tmp)
            baseline = "policies/module-size-baseline.txt"
            commit_file(clone, baseline, (FILES[baseline] + "900 src/big.ts\n").encode("utf-8"),
                        "chore: T5 the ratchet adds a project row")
            run = migrate(clone, "--apply", "--go-ahead")
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("committed: ", run.stdout)
            core = (FLOW.parents[1] / baseline).read_bytes().replace(b"\r\n", b"\n")
            committed = blob(clone, f"HEAD:{baseline}")
            self.assertEqual(committed, core + b"900 src/big.ts\n")
            manifest = json.loads(blob(clone, "HEAD:audit/flow-install.json"))
            recorded = {e["path"]: e["sha256"] for e in manifest["files"]}
            self.assertEqual(recorded[baseline], hashlib.sha256(committed).hexdigest())
            again = install(clone)
            self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
            self.assertIn(baseline, listed(again.stdout, "unchanged"), again.stdout)
            self.assertEqual(git(clone, "status", "--porcelain").stdout, "")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


def hooks_and_exclude(clone: Path) -> dict[str, bytes]:
    found = {}
    for sub in ("hooks", "info"):
        for p in sorted((clone / ".git" / sub).glob("*")):
            if p.is_file() and not p.name.endswith(".sample"):
                found[f"{sub}/{p.name}"] = p.read_bytes()
    return found


class Preflight(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        self.clone = scratch_clone(self.tmp)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def assert_stopped_with_nothing_changed(self, *names: str) -> subprocess.CompletedProcess:
        before, git_before = snapshot(self.clone), hooks_and_exclude(self.clone)
        dry = migrate(self.clone)
        self.assertEqual(dry.returncode, 2, dry.stdout + dry.stderr)
        run = migrate(self.clone, "--apply", "--go-ahead")
        self.assertEqual(run.returncode, 2, run.stdout + run.stderr)
        self.assertIn("STOPPED before any change", run.stdout)
        for name in names:
            self.assertIn(name, dry.stdout)
            self.assertIn(name, run.stdout)
        self.assertEqual(before, snapshot(self.clone), "the stopped run changed the tree")
        self.assertEqual(git_before, hooks_and_exclude(self.clone), "the stopped run changed .git/hooks or .git/info")
        self.assertEqual(list(self.clone.glob(".flow-migrate-*")), [])
        return run

    def test_a_custom_git_hook_stops_the_apply_before_any_change(self) -> None:
        hook = self.clone / ".git/hooks/pre-commit"
        hook.write_bytes(b"#!/bin/sh\n# the project's own pre-commit\nexit 0\n")
        run = self.assert_stopped_with_nothing_changed(".git/hooks/pre-commit")
        self.assertIn("mv .git/hooks/pre-commit .git/hooks/pre-commit.pre-flow", run.stdout)

    def test_an_edited_flow_hook_stops_the_apply_before_any_change(self) -> None:
        hook = self.clone / ".git/hooks/pre-commit"
        hook.write_bytes(b"#!/bin/sh\n# fusebase-flow-managed-hook: v1\n# a local edit\nexit 0\n")
        self.assert_stopped_with_nothing_changed(".git/hooks/pre-commit", "match no Flow 5.x release")

    def test_core_hookspath_stops_the_apply_before_any_change(self) -> None:
        git(self.clone, "config", "core.hooksPath", ".husky")
        self.assert_stopped_with_nothing_changed("core.hooksPath", ".husky")

    @unittest.skipUnless(shutil.which("npm"), "npm is not on PATH")
    def test_a_failing_lint_stops_the_apply_before_any_change(self) -> None:
        commit_file(self.clone, "package.json", b'{\n  "name": "demo",\n  "private": true,\n'
                    b'  "scripts": {"lint": "exit 3"}\n}\n', "chore: T5 the project's lint")
        before, git_before = snapshot(self.clone), hooks_and_exclude(self.clone)
        run = migrate(self.clone, "--apply", "--go-ahead")
        self.assertEqual(run.returncode, 2, run.stdout + run.stderr)
        self.assertIn("STOPPED before any change", run.stdout)
        self.assertIn("lint failed: `npm run -s lint` exited", run.stdout)
        self.assertEqual(before, snapshot(self.clone), "the stopped run changed the tree")
        self.assertEqual(git_before, hooks_and_exclude(self.clone), "the stopped run changed .git/hooks or .git/info")
        self.assertEqual(list(self.clone.glob(".flow-migrate-*")), [])
        dry = migrate(self.clone)
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        self.assertIn("npm run -s lint", dry.stdout)


def steps(output: str) -> list[str]:
    """The commands a message prints as `[flow migrate]   $ <command>`."""
    return [line.split("$ ", 1)[1] for line in output.splitlines() if line.startswith("[flow migrate]   $ ")]


def outside_backup(snap: tuple[str, dict[str, str]]) -> tuple[str, dict[str, str]]:
    return snap[0], {p: h for p, h in snap[1].items() if not p.startswith(".flow-migrate-")}


class Interrupted(unittest.TestCase):
    def test_a_stop_right_after_removal_prints_the_rollback_and_no_commit(self) -> None:
        sys.path.insert(0, str(FLOW.parent))
        import migrate as mig
        import migrate_apply as mapply
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            clone = scratch_clone(tmp)
            (clone / "hooks/shared/__pycache__").mkdir()
            (clone / "hooks/shared/__pycache__/x.cpython-312.pyc").write_bytes(b"\x00untracked bytecode")
            before = snapshot(clone)
            inv = mig.inventory(clone.resolve(), {"claude", "codex"})
            folder, _ = mapply.backup(inv, "20990101T000000Z")
            mapply.remove(inv, folder)  # the apply stops here
            self.assertFalse((clone / "audit/managed-content-manifest.json").exists())
            run = migrate(clone)
            self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
            self.assertIn("stopped part-way", run.stdout)
            self.assertNotIn("git commit", run.stdout)
            rollback = steps(run.stdout)
            self.assertIn("git checkout -- .", rollback)
            # the same core.autocrlf as this file's git() helper, so the restored files compare byte for byte
            env = dict(os.environ, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.autocrlf", GIT_CONFIG_VALUE_0="false")
            for step in rollback:
                done = subprocess.run([shutil.which("bash") or "bash", "-c", step], cwd=clone, env=env,
                                      capture_output=True, text=True, timeout=600)
                self.assertEqual(done.returncode, 0, f"{step}\n{done.stdout}{done.stderr}")
            self.assertEqual(outside_backup(before), outside_backup(snapshot(clone)))
            again = migrate(clone)
            self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


MINT = "FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh --slug flow-migrate"
CONSUME = "bash hooks/local/write-bootstrap-approval.sh --consume --slug flow-migrate"


class CommitFailure(unittest.TestCase):
    def test_a_failed_commit_keeps_the_approval_and_every_printed_step_finishes_it_twice(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            clone = scratch_clone(tmp)
            pre = git(clone, "rev-parse", "HEAD").stdout.strip()
            plain = {k: v for k, v in os.environ.items() if k != "FUSEBASE_FLOW_LINT"}
            # passes the preflight (no ledger yet) and fails the commit's pre-commit, like a lint rule over a Flow path
            failing = dict(plain, FUSEBASE_FLOW_LINT="test ! -e docs/flow/ledger.md")
            run = migrate(clone, "--apply", "--go-ahead", env=failing)
            self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
            self.assertIn("lint failed", run.stdout + run.stderr)
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
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


UNWRAPPED = ("# AGENTS.md\n\nCLI text.\n\n## FuseBase Flow — workflow lifecycle overlay\n\n"
             "Fusebase Flow 5.x overlay text.\n\n"
             "<!-- FLOW:PRESERVE:BEGIN (operator-owned — kept verbatim) -->\n| Project name | demo |\n\n"
             "## Project values\n\n| Deploy owner | Sabina |\n<!-- FLOW:PRESERVE:END -->\n\n"
             "more Fusebase Flow 5.x text\n\n## Project section\n\nThe project's own text.\n")


WRAPPED = UNWRAPPED.replace("## FuseBase Flow", "<!-- CUSTOM:SKILL:BEGIN -->\n\n---\n\n## FuseBase Flow").replace(
    "more Fusebase Flow 5.x text\n\n", "more Fusebase Flow 5.x text\n\n<!-- CUSTOM:SKILL:END -->\n\n")


class Overlay(unittest.TestCase):
    def test_a_level_2_line_inside_preserve_without_a_wrapper_is_carried_whole(self) -> None:
        self.carried_whole(UNWRAPPED)

    def test_a_level_2_line_inside_preserve_in_a_wrapper_is_carried_whole(self) -> None:
        self.carried_whole(WRAPPED)

    def carried_whole(self, agents: str) -> None:
        sys.path.insert(0, str(FLOW.parent))
        import migrate as mig
        import migrate_apply as mapply
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            clone = scratch_clone(tmp)
            commit_file(clone, "AGENTS.md", agents.encode("utf-8"), "docs: T5 the operator's region holds a heading")
            raw = (clone / "AGENTS.md").read_bytes()
            region = raw[raw.index(b"<!-- FLOW:PRESERVE:BEGIN"):raw.index(b"<!-- FLOW:PRESERVE:END")]
            inv = mig.inventory(clone.resolve(), {"claude", "codex"})
            self.assertEqual(inv.overlays["AGENTS.md"].preserve, region)
            mapply.overlay_and_version(inv)
            after = (clone / "AGENTS.md").read_bytes()
            self.assertIn(region, after)
            self.assertEqual(after.count(b"## FuseBase Flow"), 1)
            self.assertNotIn(b"Flow 5.x", after)
            self.assertTrue(after.startswith(b"# AGENTS.md\n\nCLI text.\n\n"))
            self.assertTrue(after.endswith(b"## Project section\n\nThe project's own text.\n"), after)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


GEMINI = b"# GEMINI.md\n\nFusebase Flow 5.x adapter for Gemini.\n"
GEMINI_V56 = "b7ccaddba289e7f6091d2492cb8c1bc15996daa88e4695731630b2719c591806"  # v5.6:GEMINI.md


class ContentCheck(unittest.TestCase):
    def setUp(self) -> None:
        sys.path.insert(0, str(FLOW.parent))
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_an_edited_gemini_md_stays_and_an_unedited_one_goes(self) -> None:
        import migrate as mig
        import migrate_apply as mapply
        real = getattr(mig, "flow5_shas", lambda rel: set())
        # the synthetic GEMINI.md stands for a release's bytes, as v5.6's does in the shipped table
        table = lambda rel: real(rel) | ({hashlib.sha256(GEMINI).hexdigest()} if rel == "GEMINI.md" else set())
        for edited in (False, True):
            clone = scratch_clone(self.tmp / ("edited" if edited else "unedited"))
            data = GEMINI + (b"Our project's own Gemini notes.\n" if edited else b"")
            commit_file(clone, "GEMINI.md", data, "docs: T5 GEMINI.md")
            with mock.patch.object(mig, "flow5_shas", table, create=True):
                inv = mig.inventory(clone.resolve(), {"claude", "codex"})
                listing = io.StringIO()
                with contextlib.redirect_stdout(listing):
                    mig.report(inv, False)
            folder, _ = mapply.backup(inv, "20990101T000000Z")
            mapply.remove(inv, folder)
            if edited:
                self.assertEqual((clone / "GEMINI.md").read_bytes(), data, "an edited GEMINI.md was deleted")
                self.assertEqual((folder / "GEMINI.md").read_bytes(), data)
                self.assertIn("left in place", listing.getvalue())
                self.assertIn("GEMINI.md", listing.getvalue().split("left in place", 1)[1])
            else:
                self.assertFalse((clone / "GEMINI.md").exists())
                self.assertEqual((folder / "GEMINI.md").read_bytes(), data)
        self.assertIn(GEMINI_V56, real("GEMINI.md"))

    def test_an_edited_install_record_aborts(self) -> None:
        import migrate as mig
        clone = scratch_clone(self.tmp)
        record = json.loads((clone / "audit/managed-content-manifest.json").read_text(encoding="utf-8"))
        record["assets"] = record["assets"][1:]
        commit_file(clone, "audit/managed-content-manifest.json", (json.dumps(record, indent=2) + "\n").encode(),
                    "chore: T5 an edited install record")
        with self.assertRaises(mig.Abort) as raised:
            mig.inventory(clone.resolve(), {"claude", "codex"})
        self.assertIn("manifest_self_sha256", str(raised.exception))


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
