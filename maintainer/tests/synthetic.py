"""The synthetic Flow 5.6 project the migrate tests build, and the helpers test_migrate.py and
test_migrate_recovery.py share."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

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


def no_auto_gc(repo: Path) -> Path:
    """Every test repository, in its own config: a commit (the migration's, a hook's) starts `git gc --auto` detached,
    whose packing deletes loose objects and their folders while copy_of()'s copytree reads them (m5 publish, run
    39364326527). The repository's config, not GIT's -c: flow.py and the hooks run their own git."""
    for key, value in (("gc.auto", "0"), ("maintenance.auto", "false")):
        subprocess.run(["git", "config", key, value], cwd=repo, capture_output=True, timeout=600, check=True)
    return repo


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


def build_project(root: Path, extra: dict[str, str] | None = None) -> None:
    root.mkdir(parents=True)
    git(root, "init", "-q")
    no_auto_gc(root)
    files = {**FILES, **(extra or {})}
    for rel, text in files.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_bytes(text.encode("utf-8"))
    assets = [{"path": rel, "sha256": hashlib.sha256((root / rel).read_bytes()).hexdigest()}
              for rel in sorted(files) if rel.split("/")[0] in ("workflows", "flow-skills", "hooks", "policies")
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


def scratch_clone(tmp: Path, extra: dict[str, str] | None = None) -> Path:
    """A clone of a fresh synthetic 5.6 project, with a committer identity for the migration commit."""
    build_project(tmp / "origin", extra)
    clone = tmp / "scratch"
    git(tmp, "clone", "-q", "--no-hardlinks", str(tmp / "origin"), str(clone))
    no_auto_gc(clone)
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
