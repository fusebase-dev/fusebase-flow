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
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "hooks/local/lib/recovery-owned-write.py"
SKILL_MIRROR = ROOT / "hooks/local/mirror-skills.sh"
AGENT_MIRROR = ROOT / "hooks/local/mirror-agents.sh"

def bash_executable() -> str:
    git_path = Path(shutil.which("git") or "")
    for candidate in (
        git_path.parent.parent / "bin/bash.exe",
        git_path.parent.parent / "usr/bin/bash.exe",
        Path(shutil.which("sh") or ""),
    ):
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

class BootstrapTest(unittest.TestCase):
    def repo(self) -> Path:
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        root = Path(holder.name)
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
        root = Path(holder.name)
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
        spec = importlib.util.spec_from_file_location("recovery_owned_write", HELPER)
        self.assertIsNotNone(spec and spec.loader)
        module = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
