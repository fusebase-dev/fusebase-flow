#!/usr/bin/env python3
"""Writes maintainer/flow5-sha256.json: the sha256 of each Flow 5.x file `flow.py migrate` deletes by name.

`python maintainer/flow5_table.py` reads every v5.* tag of this clone of the Fusebase Flow repository with
`git cat-file`. The migrator deletes a file of these names only when its bytes match one of the recorded values
(CRLF-tolerant, as install compares); any other copy is backed up and left in place. Re-run it after a 5.x release.
Maintainer data: install never copies maintainer/.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "hooks/local/lib"))
import flow_docs as fd  # noqa: E402  (its `git cat-file --batch` reader)
OUT = ROOT / "maintainer" / "flow5-sha256.json"
PATHS = (
    "GEMINI.md", "install.sh",
    "audit/README.md", "audit/agent-mirror-manifest.txt", "audit/cli-upstream-manifest.json",
    "audit/cli-vendor-manifest.json", "audit/hook-layer-manifest.json", "audit/managed-content-manifest.json",
    "audit/skill-mirror-manifest.txt",
    "policies/model-routing.yml",  # the shipped default a policies/model-routing.local.yml may copy
    "hooks/git/pre-commit", "hooks/git/commit-msg", "hooks/git/pre-push",
)
PREFIXES = (".claude/commands/",)


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def main() -> int:
    tags = sorted(git("tag", "-l", "v5*").decode().split(), key=lambda t: [int(n) for n in re.findall(r"\d+", t)])
    if not tags:
        print("no v5.* tags in this clone: fetch them first (git fetch --tags)", file=sys.stderr)
        return 1
    files: dict[str, dict[str, list[str]]] = {}
    for tag in tags:
        names = git("ls-tree", "-r", "--name-only", "-z", tag).decode("utf-8").split("\0")
        wanted = [n for n in names if n in PATHS or (n.startswith(PREFIXES) and n.endswith(".md"))]
        got = fd.blobs(ROOT, [f"{tag}:{n}" for n in wanted])
        for path in wanted:
            files.setdefault(path, {}).setdefault(hashlib.sha256(got[f"{tag}:{path}"]).hexdigest(), []).append(tag)
    doc = {"source": "git cat-file of each path at each v5.* tag; regenerate: python maintainer/flow5_table.py",
           "tags": " ".join(tags),
           "files": {p: {sha: " ".join(t) for sha, t in sorted(files[p].items())} for p in sorted(files)}}
    OUT.write_bytes((json.dumps(doc, indent=1) + "\n").encode("utf-8"))
    print(f"{OUT.relative_to(ROOT).as_posix()}: {len(files)} paths, {len(tags)} tags")
    return 0


if __name__ == "__main__":
    sys.exit(main())
