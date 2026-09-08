#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "hooks/local/lib/recovery-owned-write.py"
PREFLIGHT = ROOT / "hooks/local/lib/recovery-preflight.py"
VERIFY = ROOT / "hooks/local/lib/recovery-verify.py"
SKILL_MIRROR = ROOT / "hooks/local/mirror-skills.sh"
AGENT_MIRROR = ROOT / "hooks/local/mirror-agents.sh"

def bash_executable() -> str:
    git_value = shutil.which("git")
    git_roots = []
    if git_value:
        git_path = Path(git_value)
        git_roots.append(git_path.parent.parent)
        if git_path.parent.parent.name.lower() in {"mingw32", "mingw64"}:
            git_roots.insert(0, git_path.parent.parent.parent)
    candidates = tuple(
        root / rel for root in git_roots for rel in ("bin/bash.exe", "usr/bin/bash.exe")
    )
    if os.name != "nt":
        candidates = (Path(shutil.which("bash") or ""),) + candidates
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    raise RuntimeError("Git Bash is unavailable")

def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def put(root: Path, rel: str, value: bytes) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)

def run(root: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        args, cwd=root, env=merged, text=True, capture_output=True, timeout=45,
    )


def git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    result = run(root, "git", *args)
    if result.returncode:
        raise AssertionError(result.stderr)
    return result


def fingerprint(path: Path) -> tuple[bytes, int]:
    return path.read_bytes(), path.stat().st_mtime_ns

def production_load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location("recovery_preflight_test", PREFLIGHT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load preflight: {PREFLIGHT}")
    preflight = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(preflight)
    return preflight.load_module(path, name)

def load_path(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class BootstrapTest(unittest.TestCase):
    def repo(self) -> Path:
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        root = Path(holder.name).resolve()
        put(root, "hooks/local/lib/recovery-owned-write.py", HELPER.read_bytes())
        put(root, "hooks/local/mirror-skills.sh", SKILL_MIRROR.read_bytes())
        put(root, "hooks/local/mirror-agents.sh", AGENT_MIRROR.read_bytes())
        skill = b"skill-v1\n"
        reference = b"reference-v1\n"
        agent = b"agent-v1\n"
        paths = {
            "flow-skills/alpha/SKILL.md": skill,
            "flow-skills/alpha/references/note.md": reference,
            ".agents/skills/alpha/SKILL.md": skill,
            ".agents/skills/alpha/references/note.md": reference,
            ".claude/skills/alpha/SKILL.md": skill,
            ".claude/skills/alpha/references/note.md": reference,
            "agents/builder/AGENT.md": agent,
            ".claude/agents/builder.md": agent,
            ".codex/agents/builder.md": agent,
        }
        for rel, value in paths.items():
            put(root, rel, value)
        skill_rows = [
            f"{rel}  {sha(value)}" for rel, value in paths.items()
            if rel.startswith((".agents/skills/", ".claude/skills/"))
        ]
        agent_rows = [
            f"{rel}  {sha(value)}" for rel, value in paths.items()
            if rel.startswith((".claude/agents/", ".codex/agents/"))
        ]
        put(root, "audit/skill-mirror-manifest.txt", ("\n".join(sorted(skill_rows)) + "\n").encode())
        put(root, "audit/agent-mirror-manifest.txt", ("\n".join(sorted(agent_rows)) + "\n").encode())
        git(root, "init", "-q")
        git(root, "config", "user.name", "T34 fixture")
        git(root, "config", "user.email", "t34@example.invalid")
        git(root, "add", ".")
        git(root, "commit", "-qm", "baseline")
        return root

    def preflight_repo(self) -> Path:
        root = self.repo()
        health = b"health-v1\n"
        put(root, "flow-skills/fusebase-flow-health-check/SKILL.md", health)
        put(root, ".agents/skills/fusebase-flow-health-check/SKILL.md", health)
        put(root, ".claude/skills/fusebase-flow-health-check/SKILL.md", health)
        put(root, "hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md", b"fallback\n")
        put(root, "hooks/local/fusebase-flow-overlays/commands/health.md", b"command\n")
        put(root, "flow-skills/README.md", b"ignored\n")
        put(root, "flow-skills/alpha/references/nested/ignored.md", b"ignored\n")
        manifest = root / "audit/skill-mirror-manifest.txt"
        rows = manifest.read_text(encoding="utf-8").splitlines()
        rows.extend(
            f"{provider}/skills/fusebase-flow-health-check/SKILL.md  {sha(health)}"
            for provider in (".agents", ".claude")
        )
        manifest.write_text("\n".join(sorted(rows)) + "\n", encoding="utf-8")
        git(root, "add", ".")
        git(root, "commit", "-qm", "preflight baseline")
        put(root, "flow-skills/alpha/SKILL.md", b"skill-v2\n")
        put(root, "flow-skills/alpha/references/note.md", b"reference-v2\n")
        put(root, "agents/builder/AGENT.md", b"agent-v2\n")
        return root

    def helper(
        self, root: Path, source: str, target: str, surface: str = "skill",
    ) -> subprocess.CompletedProcess[str]:
        plan = root / "plan.tsv"
        result = root / "result.tsv"
        plan.write_text(f"{root / source}\t{target}\n", encoding="utf-8")
        return run(
            root, "python", str(root / "hooks/local/lib/recovery-owned-write.py"),
            "--root", str(root), "--plan", str(plan), "--result", str(result),
            "--surface", surface,
        )

    def assert_refused(self, root: Path, source: str, target: str, surface: str = "skill") -> None:
        path = root / target
        before = fingerprint(path)
        result = self.helper(root, source, target, surface)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(fingerprint(path), before)
        self.assertFalse((root / "state/audit/recovery-owned-targets.json").exists())
        self.assertFalse(path.with_name(path.name + ".pre-flow-repair").exists())

    def test_entry_points_bootstrap_and_three_noops(self) -> None:
        root = self.repo()
        put(root, "flow-skills/alpha/SKILL.md", b"skill-v2\n")
        put(root, "flow-skills/alpha/references/note.md", b"reference-v2\n")
        put(root, "agents/builder/AGENT.md", b"agent-v2\n")
        shell = bash_executable()
        skills = run(root, shell, "hooks/local/mirror-skills.sh")
        agents = run(root, shell, "hooks/local/mirror-agents.sh")
        self.assertEqual(skills.returncode, 0, skills.stdout + skills.stderr)
        self.assertEqual(agents.returncode, 0, agents.stdout + agents.stderr)
        self.assertIn("copied 4;", skills.stdout)
        self.assertIn("copied 2;", agents.stdout)
        for provider in (".agents", ".claude"):
            self.assertEqual(
                (root / f"{provider}/skills/alpha/SKILL.md").read_bytes(), b"skill-v2\n",
            )
            self.assertEqual(
                (root / f"{provider}/skills/alpha/references/note.md").read_bytes(),
                b"reference-v2\n",
            )
        for provider in (".claude", ".codex"):
            self.assertEqual((root / f"{provider}/agents/builder.md").read_bytes(), b"agent-v2\n")
        self.assertEqual(
            (root / ".agents/skills/alpha/SKILL.md.pre-flow-repair").read_bytes(), b"skill-v1\n",
        )
        observed = [
            ".agents/skills/alpha/SKILL.md", ".claude/skills/alpha/SKILL.md",
            ".agents/skills/alpha/references/note.md", ".claude/skills/alpha/references/note.md",
            ".claude/agents/builder.md", ".codex/agents/builder.md",
            "audit/skill-mirror-manifest.txt", "audit/agent-mirror-manifest.txt",
            "state/audit/recovery-owned-targets.json",
        ]
        before = {rel: fingerprint(root / rel) for rel in observed}
        for _ in range(3):
            skills = run(root, shell, "hooks/local/mirror-skills.sh")
            agents = run(root, shell, "hooks/local/mirror-agents.sh")
            self.assertEqual((skills.returncode, agents.returncode), (0, 0))
            self.assertIn("copied 0;", skills.stdout)
            self.assertIn("copied 0;", agents.stdout)
            self.assertEqual({rel: fingerprint(root / rel) for rel in observed}, before)

    def test_proof_conjunct_and_authority_refusals(self) -> None:
        cases = (
            "target-disagrees", "target-edited", "manifest-forged", "manifest-stale",
            "manifest-duplicate", "manifest-malformed", "manifest-missing-row",
            "source-missing", "target-nonregular", "wrong-mapping", "legacy-root",
            "wrong-surface",
        )
        for case in cases:
            with self.subTest(case=case):
                root = self.repo()
                target = ".agents/skills/alpha/SKILL.md"
                manifest = root / "audit/skill-mirror-manifest.txt"
                if case == "target-disagrees":
                    put(root, target, b"custom\n")
                    git(root, "add", target)
                    git(root, "commit", "-qm", case)
                elif case == "manifest-forged":
                    manifest.write_text("", encoding="utf-8")
                    git(root, "add", str(manifest))
                    git(root, "commit", "-qm", case)
                    manifest.write_text(f"{target}  {sha(b'skill-v1\n')}\n", encoding="utf-8")
                elif case in {"manifest-stale", "manifest-duplicate", "manifest-malformed", "manifest-missing-row"}:
                    row = f"{target}  {sha(b'skill-v1\n')}"
                    values = {
                        "manifest-stale": f"{target}  {'0' * 64}\n",
                        "manifest-duplicate": f"{row}\n{row}\n",
                        "manifest-malformed": f"{row}\nbroken\n",
                        "manifest-missing-row": "",
                    }
                    manifest.write_text(values[case], encoding="utf-8")
                    git(root, "add", str(manifest))
                    git(root, "commit", "-qm", case)
                elif case == "source-missing":
                    git(root, "rm", "-q", "flow-skills/alpha/SKILL.md")
                    git(root, "commit", "-qm", case)
                elif case == "target-nonregular":
                    blob = git(root, "hash-object", "-w", target).stdout.strip()
                    git(root, "update-index", "--cacheinfo", f"120000,{blob},{target}")
                    git(root, "commit", "-qm", case)
                elif case == "wrong-mapping":
                    put(root, "custom/alpha.md", b"skill-v1\n")
                    git(root, "add", "custom/alpha.md")
                    git(root, "commit", "-qm", case)
                elif case == "legacy-root":
                    put(root, "skills/alpha/SKILL.md", b"legacy-v1\n")
                    git(root, "add", "skills/alpha/SKILL.md")
                    git(root, "commit", "-qm", case)
                if case == "target-edited":
                    put(root, target, b"edited-after-commit\n")
                put(root, "flow-skills/alpha/SKILL.md", b"skill-v2\n")
                if case == "wrong-mapping":
                    self.assert_refused(root, "flow-skills/alpha/SKILL.md", "custom/alpha.md")
                elif case == "legacy-root":
                    put(root, "skills/alpha/SKILL.md", b"legacy-v2\n")
                    self.assert_refused(root, "skills/alpha/SKILL.md", target)
                elif case == "wrong-surface":
                    for surface in ("command", "health-skill", "git", "settings"):
                        self.assert_refused(root, "flow-skills/alpha/SKILL.md", target, surface)
                else:
                    self.assert_refused(root, "flow-skills/alpha/SKILL.md", target)

    def test_missing_head_refuses_existing_target(self) -> None:
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        root = Path(holder.name).resolve()
        put(root, "hooks/local/lib/recovery-owned-write.py", HELPER.read_bytes())
        put(root, "flow-skills/alpha/SKILL.md", b"new\n")
        put(root, ".agents/skills/alpha/SKILL.md", b"old\n")
        self.assert_refused(root, "flow-skills/alpha/SKILL.md", ".agents/skills/alpha/SKILL.md")

    def test_interruption_retains_original_and_retry_converges(self) -> None:
        root = self.repo()
        put(root, "flow-skills/alpha/SKILL.md", b"skill-v2\n")
        env = {"FF_RECOVERY_WRITE_INTERRUPT": "after-retain:.agents/skills/alpha/SKILL.md"}
        shell = bash_executable()
        interrupted = run(root, shell, "hooks/local/mirror-skills.sh", env=env)
        self.assertEqual(interrupted.returncode, 1)
        self.assertEqual((root / ".agents/skills/alpha/SKILL.md").read_bytes(), b"skill-v1\n")
        self.assertEqual(
            (root / ".agents/skills/alpha/SKILL.md.pre-flow-repair").read_bytes(), b"skill-v1\n",
        )
        retry = run(root, shell, "hooks/local/mirror-skills.sh")
        self.assertEqual(retry.returncode, 0, retry.stdout + retry.stderr)
        self.assertEqual((root / ".agents/skills/alpha/SKILL.md").read_bytes(), b"skill-v2\n")

    def test_pinned_head_change_refuses_before_retained_copy(self) -> None:
        root = self.repo()
        put(root, "flow-skills/alpha/SKILL.md", b"skill-v2\n")
        plan = root / "plan.tsv"
        result = root / "result.tsv"
        target = ".agents/skills/alpha/SKILL.md"
        plan.write_text(f"{root / 'flow-skills/alpha/SKILL.md'}\t{target}\n", encoding="utf-8")
        name = "recovery_owned_write_pinned_head"
        sys.modules.pop(name, None)
        module = production_load(HELPER, name)
        self.assertNotIn(name, sys.modules)
        original = module.Baseline.revalidate_head

        def advance(instance):
            git(root, "commit", "--allow-empty", "-qm", "advance")
            return original(instance)

        before = fingerprint(root / target)
        with mock.patch.object(module.Baseline, "revalidate_head", advance):
            rc = module.apply(root, plan, result, "skill")
        self.assertEqual(rc, 1)
        self.assertEqual(fingerprint(root / target), before)
        self.assertFalse((root / f"{target}.pre-flow-repair").exists())

    def test_production_loader_supports_immutable_records_without_registration(self) -> None:
        name = "recovery_owned_write_unregistered"
        sys.modules.pop(name, None)
        module = production_load(HELPER, name)
        self.assertNotIn(name, sys.modules)
        plan = module.PlanRow(
            source_raw="raw", source_rel="source", target_rel="target", manifest_rel="manifest",
        )
        records = (
            (plan, "source_raw", "raw"),
            (module.TreeEntry("100644", "blob", "oid"), "mode", "100644"),
            (module.BootstrapProof(head="head", source_hash="source", target_hash="target"), "head", "head"),
            (module.PreparedRow(plan, None, None, "status", "detail", None, None), "status", "status"),
        )
        for record, field, value in records:
            self.assertEqual(getattr(record, field), value)
            with self.assertRaises(AttributeError):
                setattr(record, field, "changed")

    def test_legacy_classifier_is_conservative_without_git_context(self) -> None:
        module = production_load(HELPER, "recovery_owned_write_legacy")
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        root = Path(holder.name).resolve()
        source = root / "source"
        target = root / "target"
        source.write_bytes(b"new\n")
        with mock.patch.object(module, "git_run", side_effect=AssertionError("unexpected Git")):
            self.assertEqual(module.classify(source, target, "target", {}),
                             ("missing-and-authorized", sha(b"new\n")))
            target.write_bytes(b"new\n")
            self.assertEqual(module.classify(source, target, "target", {})[0], "current")
            target.write_bytes(b"old\n")
            receipt = {"target": {"sha256": sha(b"old\n")}}
            self.assertEqual(module.classify(source, target, "target", receipt)[0], "owned-repair")
            self.assertEqual(module.classify(source, target, "target", {})[0], "unowned-collision")
            source.unlink()
            result = module.classify(source, target, "target", {})
            self.assertEqual(result, ("unsafe", "source is missing, non-file, or symlink"))
            self.assertEqual(len(result), 2)

    def test_preflight_writer_and_verifier_share_bootstrap_classification(self) -> None:
        root = self.preflight_repo()
        module = production_load(root / "hooks/local/lib/recovery-owned-write.py", "owned_seam")
        preflight = load_path(PREFLIGHT, "preflight_seam")
        verifier = load_path(VERIFY, "verify_seam")
        planned = preflight.target_rows(root, module)
        mirrored = [row for row in planned if row["surface"] in {"skill_mirrors", "agent_mirrors"}]
        changed = [row for row in mirrored if "/alpha/" in row["target"] or "builder.md" in row["target"]]
        self.assertTrue(changed)
        self.assertEqual({row["classification"] for row in changed}, {"owned-repair"})
        health_targets = [row for row in planned if "fusebase-flow-health-check" in row["target"]]
        self.assertEqual(len(health_targets), 2)
        self.assertEqual({row["surface"] for row in health_targets}, {"skill_mirrors"})
        self.assertFalse(any("README.md" in row["target"] or "/nested/" in row["target"]
                             for row in planned))
        for label, rows in (("skill", [row for row in mirrored if row["surface"] == "skill_mirrors"]),
                            ("agent", [row for row in mirrored if row["surface"] == "agent_mirrors"])):
            plan = root / f"{label}.tsv"
            result = root / f"{label}.result"
            plan.write_text("".join(f"{root / row['source']}\t{row['target']}\n" for row in rows),
                            encoding="utf-8")
            self.assertEqual(module.apply(root, plan, result, label), 0, result.read_text())
        self.assertEqual(verifier.verify_targets(root, {"targets": mirrored}), {})

    def test_preflight_collisions_remain_unowned_after_writer(self) -> None:
        for case in ("custom-target", "bad-manifest"):
            with self.subTest(case=case):
                root = self.preflight_repo()
                target_rel = ".agents/skills/alpha/SKILL.md"
                target = root / target_rel
                if case == "custom-target":
                    target.write_bytes(b"custom\n")
                else:
                    manifest = root / "audit/skill-mirror-manifest.txt"
                    manifest.write_text("broken\n", encoding="utf-8")
                    git(root, "add", str(manifest))
                    git(root, "commit", "-qm", "bad manifest")
                module = production_load(root / "hooks/local/lib/recovery-owned-write.py", f"owned_{case}")
                preflight = load_path(PREFLIGHT, f"preflight_{case}")
                verifier = load_path(VERIFY, f"verify_{case}")
                before = fingerprint(target)
                row = next(row for row in preflight.target_rows(root, module)
                           if row["target"] == target_rel)
                self.assertEqual(row["classification"], "unowned-collision")
                plan = root / "collision.tsv"
                result = root / "collision.result"
                plan.write_text(f"{root / row['source']}\t{target_rel}\n", encoding="utf-8")
                self.assertEqual(module.apply(root, plan, result, "skill"), 1)
                self.assertEqual(fingerprint(target), before)
                again = next(item for item in preflight.target_rows(root, module)
                             if item["target"] == target_rel)
                self.assertEqual(again["classification"], "unowned-collision")
                self.assertIn("skill_mirrors", verifier.verify_targets(root, {"targets": [row]}))

    def test_preparation_rejects_invalid_inputs_without_writes_and_uses_one_baseline(self) -> None:
        root = self.preflight_repo()
        module = production_load(root / "hooks/local/lib/recovery-owned-write.py", "owned_invalid")
        preflight = load_path(PREFLIGHT, "preflight_invalid")
        target = root / ".agents/skills/alpha/SKILL.md"
        before = fingerprint(target)
        command = root / "hooks/local/fusebase-flow-overlays/commands/health.md"
        command.unlink()
        command.mkdir()
        with self.assertRaises(ValueError):
            preflight.target_rows(root, module)
        self.assertEqual(fingerprint(target), before)
        command.rmdir()
        put(root, "hooks/local/fusebase-flow-overlays/commands/health.md", b"command\n")
        put(root, "state/audit/recovery-owned-targets.json", b"{broken\n")
        with self.assertRaises(ValueError):
            preflight.target_rows(root, module)
        self.assertEqual(fingerprint(target), before)
        (root / "state/audit/recovery-owned-targets.json").unlink()
        first = module.make_plan_row(root, str(root / "flow-skills/alpha/SKILL.md"),
                                     ".agents/skills/alpha/SKILL.md", "skill")
        conflict = module.make_plan_row(root, str(root / "agents/builder/AGENT.md"),
                                        ".agents/skills/alpha/SKILL.md", "agent")
        with self.assertRaises(RuntimeError):
            module.prepare_rows(root, [first, conflict], {})
        count = 0
        original = module.Baseline
        class CountingBaseline(original):
            def __init__(self, *args):
                nonlocal count
                count += 1
                super().__init__(*args)
        with mock.patch.object(module, "Baseline", CountingBaseline):
            baseline, prepared = module.prepare_rows(root, [first, first], {})
        self.assertIsInstance(baseline, original)
        self.assertEqual((count, len(prepared)), (1, 1))
        self.assertEqual(fingerprint(target), before)

    def test_real_symlink_refusals(self) -> None:
        probe_root = self.repo()
        probe = probe_root / "symlink-probe"
        try:
            probe.symlink_to(probe_root / "flow-skills/alpha/SKILL.md")
        except OSError as exc:
            self.skipTest(f"real symlinks unavailable: {exc}")
        probe.unlink()
        for case in ("source", "target", "target-ancestor"):
            with self.subTest(case=case):
                root = self.repo()
                put(root, "flow-skills/alpha/new.md", b"skill-v2\n")
                if case == "source":
                    (root / "flow-skills/alpha/SKILL.md").unlink()
                    (root / "flow-skills/alpha/SKILL.md").symlink_to(root / "flow-skills/alpha/new.md")
                elif case == "target":
                    (root / ".agents/skills/alpha/SKILL.md").unlink()
                    (root / ".agents/skills/alpha/SKILL.md").symlink_to(root / "flow-skills/alpha/SKILL.md")
                else:
                    shutil.move(root / ".agents/skills", root / "skill-targets")
                    (root / ".agents/skills").symlink_to(root / "skill-targets", target_is_directory=True)
                self.assert_refused(root, "flow-skills/alpha/SKILL.md", ".agents/skills/alpha/SKILL.md")

    def test_race_revalidation_and_concurrent_receipt_union(self) -> None:
        target_rel = ".agents/skills/alpha/SKILL.md"
        user_bytes = b"operator-race\n"
        for case in ("current", "receipt-owned", "missing"):
            with self.subTest(case=case):
                root = self.repo()
                source = root / "flow-skills/alpha/SKILL.md"
                target = root / target_rel
                if case == "receipt-owned":
                    source.write_bytes(b"skill-v2\n")
                    put(root, "state/audit/recovery-owned-targets.json", json.dumps({
                        "schema": 1,
                        "targets": {target_rel: {"sha256": sha(b"skill-v1\n"), "surface": "skill"}},
                    }, sort_keys=True, indent=2).encode() + b"\n")
                elif case == "missing":
                    target.unlink()
                receipt = root / "state/audit/recovery-owned-targets.json"
                receipt_before = receipt.read_bytes() if receipt.exists() else None
                plan = root / "race.tsv"
                result = root / "race.result"
                plan.write_text(f"{source}\t{target_rel}\n", encoding="utf-8")
                module = production_load(HELPER, f"owned_race_{case}")
                original_prepare = module.prepare_rows

                def inject(*args):
                    prepared = original_prepare(*args)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(user_bytes)
                    return prepared

                with mock.patch.object(module, "prepare_rows", inject):
                    self.assertEqual(module.apply(root, plan, result, "skill"), 1)
                self.assertEqual(target.read_bytes(), user_bytes)
                receipt_after = receipt.read_bytes() if receipt.exists() else None
                self.assertEqual(receipt_after, receipt_before)
                self.assertFalse(target.with_name(target.name + ".pre-flow-repair").exists())

        root = self.repo()
        source = root / "flow-skills/alpha/SKILL.md"
        target = root / target_rel
        source.write_bytes(b"skill-v2\n")
        put(root, "state/audit/recovery-owned-targets.json", json.dumps({
            "schema": 1,
            "targets": {target_rel: {"sha256": sha(b"skill-v1\n"), "surface": "skill"}},
        }, sort_keys=True, indent=2).encode() + b"\n")
        plan = root / "owned.tsv"
        result = root / "owned.result"
        plan.write_text(f"{source}\t{target_rel}\n", encoding="utf-8")
        module = production_load(HELPER, "owned_unchanged_control")
        self.assertEqual(module.apply(root, plan, result, "skill"), 0)
        self.assertEqual(target.read_bytes(), b"skill-v2\n")
        self.assertEqual(target.with_name(target.name + ".pre-flow-repair").read_bytes(), b"skill-v1\n")

        root = self.repo()
        module = production_load(HELPER, "owned_concurrent_union")
        plans = []
        targets = [
            ".agents/skills/alpha/SKILL.md",
            ".claude/skills/alpha/SKILL.md",
        ]
        for index, rel in enumerate(targets):
            plan = root / f"union-{index}.tsv"
            plan.write_text(f"{root / 'flow-skills/alpha/SKILL.md'}\t{rel}\n", encoding="utf-8")
            plans.append(plan)
        active = 0
        maximum = 0
        guard = threading.Lock()
        original_load = module.load_receipt

        def slow_load(path):
            nonlocal active, maximum
            with guard:
                active += 1
                maximum = max(maximum, active)
            time.sleep(0.1)
            value = original_load(path)
            with guard:
                active -= 1
            return value

        def writer(index):
            return module.apply(root, plans[index], root / f"union-{index}.result", "skill")

        with mock.patch.object(module, "load_receipt", slow_load):
            with ThreadPoolExecutor(max_workers=2) as executor:
                outcomes = list(executor.map(writer, range(2)))
        self.assertEqual(outcomes, [0, 0])
        self.assertEqual(maximum, 1)
        receipt = json.loads((root / "state/audit/recovery-owned-targets.json").read_text())
        self.assertEqual(set(receipt["targets"]), set(targets))
        print("PASS: T51 current, receipt-owned, and missing races preserved user bytes")
        print("PASS: T51 rejected races left ownership authority unchanged")
        print("PASS: T51 unchanged owned repair retained and copied exact bytes")
        print("PASS: T51 concurrent writers serialized and retained receipt union")


if __name__ == "__main__":
    if sys.argv[1:] == ["--only", "race"]:
        suite = unittest.TestSuite([
            BootstrapTest("test_race_revalidation_and_concurrent_receipt_union")
        ])
        raise SystemExit(0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1)
    unittest.main(verbosity=2)
