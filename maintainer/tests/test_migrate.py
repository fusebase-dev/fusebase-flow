#!/usr/bin/env python3
"""flow migrate fixtures: `python maintainer/tests/test_migrate.py` (stdlib unittest).

A synthetic Flow 5.x project is built in a temporary folder and cloned; each test works on the
scratch clone. FLOW_MIGRATE_FIXTURE=<path to a real 5.x project> adds the same abort check on a
scratch clone of that project (done check 5 of milestone 2). The undo, rollback and finish-by-hand
tests are in test_migrate_recovery.py; this file runs them too (load_tests).
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from synthetic import FILES, FLOW, GIT, blob, build_project, commit_file, git, migrate, scratch_clone, snapshot


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
            "templates/plain.gif": b"GIF89a\r\nno NUL byte\r\n", "docs/flow/evidence/shot.png": b"\x89PNG\r\n\x00\r\n"}
EVIDENCE = "docs/flow/evidence/P1.md"  # a Flow document the lifecycle writes, not flow.py


class ApplyEndToEnd(unittest.TestCase):
    """One migration of the synthetic project, shared by the checks below (an apply takes minutes on a loaded host)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        cls.clone = scratch_clone(cls.tmp)
        commit_file(cls.clone, ".gitattributes", b"*.png binary\n*.gif binary\n", "chore: T1 the project's attributes")
        cls.pre = git(cls.clone, "rev-parse", "HEAD").stdout.strip()
        cls.applied = migrate(cls.clone, "--apply", "--go-ahead")

    def test_the_ledger_names_the_health_check_to_run_after_the_commit(self) -> None:
        """Item 4(i) of brief m5: `flow.py health` exists; check-cli-flow-conflicts.sh is still not in the core."""
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        ledger = blob(self.clone, "HEAD:docs/flow/ledger.md").decode("utf-8")
        line = next(ln for ln in ledger.splitlines() if ln.startswith("- not run: "))
        self.assertNotIn("neither is in the 6.0 core yet", line)
        self.assertIn("`python <the Flow core you migrated with>/maintainer/flow.py health --target .`", line)
        self.assertIn('h = sub.add_parser("health"', FLOW.read_text(encoding="utf-8"))
        self.assertFalse((FLOW.parents[1] / "hooks/local/check-cli-flow-conflicts.sh").exists(), "still not in 6.0")

    def test_binaries_in_flow_folders_keep_their_bytes(self) -> None:
        self.assertEqual(self.applied.returncode, 0, self.applied.stdout + self.applied.stderr)
        fresh = self.tmp / "binaries"
        run = lambda *args: subprocess.run([*GIT_CRLF, *args], cwd=fresh, capture_output=True, timeout=600)
        subprocess.run([*GIT_CRLF, "clone", "-q", "--no-hardlinks", str(self.clone), str(fresh)], timeout=600)
        for rel, data in {**BINARIES, EVIDENCE: b"# Evidence P1\n\n| Item | Status |\n"}.items():
            (fresh / rel).parent.mkdir(parents=True, exist_ok=True)
            (fresh / rel).write_bytes(data)
        self.assertEqual(run("add", "--", *BINARIES, EVIDENCE).returncode, 0)
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
                    ".claude/skills/plan/SKILL.md", "workflows/lifecycle.md", "hooks/git/pre-commit", EVIDENCE):
            self.assertNotIn(b"\r", (fresh / rel).read_bytes(), rel)
        self.assertIn(f"{EVIDENCE}: eol: lf", run("check-attr", "eol", "--", EVIDENCE).stdout.decode())

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
        self.assertRegex(run.stdout, r"committed: [0-9a-f]+ flow: migrate Fusebase Flow 5\.6 to ")
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
    def test_every_row_of_the_cores_baseline_names_a_file_the_core_ships(self) -> None:
        """Item 4 of brief m5: hooks/local/upgrade.sh is a 5.x file; 6.0 does not ship it."""
        sys.path.insert(0, str(FLOW.parent))
        import flow
        rows = flow.baseline_rows((FLOW.parents[1] / flow.BASELINE).read_bytes())
        self.assertEqual([p for p in rows if p not in flow.core_files()], [])

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


# a Flow block whose END marker was lost, with the project's lines after it
NO_END = (b"*.psd binary\n# FLOW:BEGIN line endings (flow.py install writes this block; re-install replaces it)\n"
          b"/VERSION text eol=lf\n*.sketch binary\nproject line\n")


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

    def lint_that_writes(self, lint: str, written: str, tracked: list[str]) -> None:
        run = migrate(self.clone, "--apply", "--go-ahead", env=dict(os.environ, FUSEBASE_FLOW_LINT=lint))
        self.assertEqual(run.returncode, 2, run.stdout + run.stderr)
        stop = [line for line in run.stdout.splitlines() if "STOP: lint and typecheck" in line]
        self.assertEqual(len(stop), 1, run.stdout)
        self.assertIn(written, stop[0])
        self.assertIn(lint, stop[0])
        self.assertNotIn("nothing written", run.stdout)
        self.assertEqual(list(self.clone.glob(".flow-migrate-*")), [])
        self.assertTrue((self.clone / "audit/managed-content-manifest.json").is_file())
        self.assertEqual(git(self.clone, "diff", "--name-only", "HEAD").stdout.split(), tracked)

    def test_the_dry_run_names_lint_and_typecheck_as_not_run(self) -> None:
        cmds = {"FUSEBASE_FLOW_LINT": "npm run -s lint", "FUSEBASE_FLOW_TYPECHECK": "npm run -s typecheck"}
        dry = migrate(self.clone, env=dict(os.environ, **cmds))
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        lines = [line for line in dry.stdout.splitlines() if "lint and typecheck" in line]
        self.assertEqual([line for line in lines if "ok:" in line], [], lines)
        self.assertIn("--apply runs them", "\n".join(lines))
        for cmd in cmds.values():
            self.assertIn(f"[flow migrate]     $ {cmd}\n", dry.stdout)
        core = FLOW.parents[1]
        note = (core / "maintainer/release-notes" / f"{(core / 'VERSION').read_text().strip()}.md").read_text("utf-8")
        self.assertIn("only once those two also pass by hand", note)

    def test_a_flow_attributes_block_without_its_end_marker_stops_the_apply(self) -> None:
        commit_file(self.clone, ".gitattributes", NO_END, "chore: T1 a damaged Flow block")
        self.assert_stopped_with_nothing_changed(".gitattributes line 2", "FLOW:END")

    def test_install_refuses_a_flow_attributes_block_without_its_end_marker(self) -> None:
        repo = self.tmp / "fresh"
        repo.mkdir()
        git(repo, "init", "-q")
        commit_file(repo, ".gitattributes", NO_END, "chore: T1 a damaged Flow block")
        before, git_before = snapshot(repo), hooks_and_exclude(repo)
        run = install(repo)
        self.assertEqual(run.returncode, 2, run.stdout + run.stderr)
        self.assertIn(".gitattributes line 2", run.stdout)
        self.assertEqual(before, snapshot(repo), "the refused install changed the tree")
        self.assertEqual(git_before, hooks_and_exclude(repo), "the refused install changed .git/hooks or .git/info")

    def test_a_lint_that_writes_a_flow_file_and_passes_stops_the_apply(self) -> None:
        self.lint_that_writes("printf x >> FLOW_RULES.md", "FLOW_RULES.md", ["FLOW_RULES.md"])

    def test_a_lint_that_writes_and_fails_does_not_say_nothing_written(self) -> None:
        self.lint_that_writes("printf 'x\\n' > hooks/lint-report.txt; exit 1", "hooks/lint-report.txt", [])


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


def records(valid: bool) -> dict[str, bytes]:
    """The four records 5.x tooling writes per project: in their writers' layout (bytes of no release), or not."""
    sha, asset = "ab" * 32, ".claude/skills/app-backend/SKILL.md"
    vendor = {"schema_version": 2, "generated_at": "2026-09-30", "source_cli_version": "0.29.9",
              "reviewed_cli_policy": None, "description": "CLI provenance", "asset_count": 1,
              "assets": [{"path": asset, "sha256": sha, "upstream_sha256": sha, "merge_derived": False,
                          "matches_upstream": True}]}
    upstream = {"schema_version": 1, "generated_at": "2026-09-30", "cli_version": "0.29.9", "description": "upstream",
                "asset_count": 1, "superseded_custom_blocks": [],
                "assets": [{"path": asset, "upstream_source": "skills/app-backend/SKILL.md", "upstream_sha256": sha,
                            "merge_derived": False}]}
    if not valid:
        vendor, upstream = {"schema_version": 2, "assets": "our own notes"}, {"notes": "the project's own file"}
    return {"audit/cli-vendor-manifest.json": json.dumps(vendor, indent=2).encode() + b"\n",
            "audit/cli-upstream-manifest.json": json.dumps(upstream, indent=2).encode() + b"\n",
            "audit/skill-mirror-manifest.txt": f".agents/skills/communication/SKILL.md  {sha}\n".encode() if valid
            else b".agents/skills/communication/SKILL.md  not-a-sha256\n",
            "audit/agent-mirror-manifest.txt": f".claude/agents/ai-developer.md  {sha}\n".encode() if valid
            else b"# our agents\nreviewer\n"}


class FlowRecords(unittest.TestCase):
    def test_a_5x_record_goes_when_it_parses_and_stays_when_it_does_not(self) -> None:
        sys.path.insert(0, str(FLOW.parent))
        import migrate as mig
        import migrate_apply as mapply
        tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        try:
            for valid in (True, False):
                clone = scratch_clone(tmp / str(valid))
                for rel, data in records(valid).items():
                    commit_file(clone, rel, data, f"chore: T1 {rel}")
                inv = mig.inventory(clone.resolve(), {"claude", "codex"})
                listing = io.StringIO()
                with contextlib.redirect_stdout(listing):
                    mig.report(inv, False)
                folder, _ = mapply.backup(inv, "20990101T000000Z")
                mapply.remove(inv, folder)
                for rel, data in records(valid).items():
                    self.assertEqual((folder / rel).read_bytes(), data, f"{rel} is not in the backup folder")
                    self.assertEqual((clone / rel).is_file(), not valid, f"{rel} (parses as the 5.x record: {valid})")
                    self.assertEqual(rel in inv.foreign, not valid, rel)
                    if not valid:
                        self.assertIn(f"\n[flow migrate]     {rel}\n", listing.getvalue().split("left in place", 1)[1])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


def mirror_rows(files: dict[str, bytes]) -> bytes:
    return "".join(f"{p}  {hashlib.sha256(d).hexdigest()}\n" for p, d in sorted(files.items())).encode("utf-8")


class ProjectMirrors(unittest.TestCase):
    """13 skills and an agent of the project's own, mirrored by 5.x tooling beside a Flow skill's mirrors."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="flow-migrate-"))
        cls.clone = clone = scratch_clone(cls.tmp)
        flow_skill = FILES["flow-skills/communication/SKILL.md"].encode("utf-8")
        own_skills = {f"team-{n:02d}": f"---\nname: team-{n:02d}\n---\nOur own notes.\n".encode() for n in range(1, 14)}
        own_agent = b"---\nname: team-reviewer\n---\n"
        skills = {f"{root}/{name}/SKILL.md": data for root in (".claude/skills", ".agents/skills")
                  for name, data in (("communication", flow_skill), *own_skills.items())}
        agents = {".claude/agents/team-reviewer.md": own_agent, ".codex/agents/team-reviewer.md": own_agent}
        cls.own = {**{f"flow-skills/{name}/SKILL.md": data for name, data in own_skills.items()},
                   "agents/team-reviewer/AGENT.md": own_agent,
                   **{p: d for p, d in {**skills, **agents}.items() if "team-" in p}}
        files = {**skills, **agents, **cls.own, "audit/skill-mirror-manifest.txt": mirror_rows(skills),
                 "audit/agent-mirror-manifest.txt": mirror_rows(agents)}
        for rel, data in files.items():
            (clone / rel).parent.mkdir(parents=True, exist_ok=True)
            (clone / rel).write_bytes(data)
        git(clone, "add", "--", *files)
        git(clone, "commit", "-q", "-m", "chore: T1 the project's own skills and agent, mirrored by 5.x tooling")
        cls.dry, cls.full = migrate(clone), migrate(clone, "--full")
        cls.applied = migrate(clone, "--apply", "--go-ahead")

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_a_project_skill_and_agent_mirrored_by_5x_tooling_survive_the_migration(self) -> None:
        clone, run = self.clone, self.applied
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        for rel, data in self.own.items():
            self.assertTrue((clone / rel).is_file(), f"the migration deleted {rel}")
            self.assertEqual((clone / rel).read_bytes(), data, rel)
            self.assertEqual(blob(clone, f"HEAD:{rel}"), data, rel)
        self.assertIn("skill mirrors under .claude/skills/: 1 skills, 1 files: communication", run.stdout)
        self.assertFalse((clone / ".claude/skills/communication/SKILL.md").exists())

    def test_every_kept_mirror_is_listed_in_the_dry_run_the_full_list_and_the_ledger(self) -> None:
        self.assertEqual(len(self.own), 42)
        for run in (self.dry, self.full, self.applied):
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            keep = run.stdout.split("keep (project-owned):", 1)[1].split("\n[flow migrate] overlay")[0]
            self.assertEqual([p for p in self.own if f"[flow migrate]     {p}" not in keep.splitlines()], [], keep)
        ledger = blob(self.clone, "HEAD:docs/flow/ledger.md").decode("utf-8")
        keep = next(line for line in ledger.splitlines() if line.startswith("- keep: "))
        self.assertEqual([p for p in self.own if p not in keep], [], keep)


class ReleaseNote(unittest.TestCase):
    def test_each_command_names_only_paths_that_exist_when_it_runs(self) -> None:
        """The note's commands in order, inline and fenced: each path is `<a folder an earlier git clone made>/<a path
        the core tracks>`. The undo block runs in the migrated project; the Undo tests paste it."""
        core = FLOW.parents[1]
        version = (core / "VERSION").read_text().strip()
        note = (core / "maintainer/release-notes" / f"{version}.md").read_text("utf-8")
        tracked = set(git(core, "ls-files").stdout.splitlines())
        commands = []
        for fenced, inline in re.findall(r"^```\n(.*?)^```$|`([^`\n]+)`", note, flags=re.M | re.S):
            if not fenced.startswith("( set -e"):
                commands += fenced.splitlines() if fenced else [inline]
        cloned, named, wrong = set(), [], []
        for line in (c for c in commands if c.split()[:1] in (["git"], ["pip"], ["python"])):
            words = line.split()
            for word in words[1:]:
                if "/" in word and "://" not in word and not word.startswith(("<", "-")):
                    named.append(word)
                    folder, _, rest = word.partition("/")
                    if folder not in cloned or rest not in tracked:
                        wrong.append(f"{line}  ({word})")
            if words[:2] == ["git", "clone"]:
                cloned.add(words[-1])
        self.assertEqual(wrong, [], "paths that do not exist when their command runs")
        self.assertEqual(cloned, {f"fusebase-flow-{version}"})
        self.assertIn(f"fusebase-flow-{version}/hooks/requirements.txt", named)

    def test_the_m4_upgrade_steps_name_only_paths_the_release_ships(self) -> None:
        """brief m5-finish B: every command of the step-by-step section names a path the release ships, under the
        release's clone folder or, inside the project, as the install put it there."""
        core = FLOW.parents[1]
        version = (core / "VERSION").read_text().strip()
        note = (core / "maintainer/release-notes" / f"{version}.md").read_text("utf-8")
        section = note.split("## Upgrading a 6.0.0-m4 project, step by step\n", 1)[1].split("\n## ", 1)[0]
        tracked = set(git(core, "ls-files").stdout.splitlines())
        blocks = re.findall(r"^```\n(.*?)^```$", section, flags=re.M | re.S)
        self.assertEqual(len(blocks), 2, "the plain install and the wired one")
        named, wrong = [], []
        for line in (ln for block in blocks for ln in block.splitlines()):
            for word in line.split():
                if "/" in word and "://" not in word and not word.startswith(("<", "-")):
                    named.append(word.removeprefix(f"fusebase-flow-{version}/"))
                    if named[-1] not in tracked:
                        wrong.append(f"{line}  ({word})")
        self.assertEqual(wrong, [], "paths the release does not ship")
        self.assertLessEqual({"maintainer/flow.py", "hooks/requirements.txt", "hooks/local/write-bootstrap-approval.sh"},
                             set(named))


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


def load_tests(loader: unittest.TestLoader, tests: unittest.TestSuite, pattern: str | None) -> unittest.TestSuite:
    """core-verify.yml runs only this file, so it carries every migrate test, the milestone 3 fixtures and the 6.0.0
    pass's and its micro-pass's."""
    import test_commits
    import test_core
    import test_migrate_recovery
    import test_scripts
    tests.addTests(loader.loadTestsFromModule(test_migrate_recovery))
    tests.addTests(loader.loadTestsFromModule(test_scripts))
    tests.addTests(loader.loadTestsFromModule(test_core))
    tests.addTests(loader.loadTestsFromModule(test_commits))
    return tests


if __name__ == "__main__":
    unittest.main(verbosity=2)
