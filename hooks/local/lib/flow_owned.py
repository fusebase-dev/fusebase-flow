"""Which staged paths are not Flow's own: the rule of the `flow:` subject (O-21), for hooks/local/lib/commit_msg.py.

Flow's own, besides the four documents (commit_msg.py checks those):
- an added or changed path whose staged bytes have the sha256 the staged audit/flow-install.json records for it, and
  that manifest itself;
- a deleted path recorded at HEAD by that manifest or by a 5.x Flow manifest, or whose name and HEAD bytes are those
  of a path one of them records (a 5.x command mirror); on a 5.x tree also the files the migration deletes by name;
- AGENTS.md, CLAUDE.md, .gitattributes and .gitignore when the change stays inside Flow's marked block, checked
  against HEAD; on a 5.x tree AGENTS.md and CLAUDE.md whole (the migration replaces 5.x's section, which no marker
  bounds).
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

MANIFEST, MC_5X = "audit/flow-install.json", "audit/managed-content-manifest.json"
ASSETS_5X = (MC_5X, "audit/hook-layer-manifest.json")  # {"assets": [{"path", "sha256"}]}
MIRRORS_5X = ("audit/skill-mirror-manifest.txt", "audit/agent-mirror-manifest.txt")  # "<path>  <sha256>" rows
ROW = re.compile(r"(.+?)  ([0-9a-f]{64})")
# What maintainer/migrate.py deletes by name (AUDIT_5X, ROOT_5X, ORPHANS; test_commits keeps the two in step).
RETIRED_5X = (*ASSETS_5X, *MIRRORS_5X, "audit/README.md", "audit/cli-upstream-manifest.json",
              "audit/cli-vendor-manifest.json", "GEMINI.md", "install.sh", "policies/model-routing.local.yml")
BYTECODE = re.compile(r"hooks/.*(/__pycache__/.*|\.py[co])")
MERGED, OVERLAYS = ("AGENTS.md", "CLAUDE.md", ".gitattributes", ".gitignore"), ("AGENTS.md", "CLAUDE.md")
MARK = re.compile(r"(?:<!-- |# )FLOW:(BEGIN|END)\b")
WRAP = ("<!-- CUSTOM:SKILL:BEGIN -->", "<!-- CUSTOM:SKILL:END -->")


def blobs(root: Path, specs: list[str]) -> dict[str, bytes | None]:
    """Each `<rev>:<path>` spec's bytes, from one `git cat-file --batch`; None when absent or not a blob."""
    try:
        out = subprocess.run(["git", "cat-file", "--batch"], cwd=root, capture_output=True, timeout=300,
                             input="".join(f"{s}\n" for s in specs).encode("utf-8")).stdout
    except (OSError, subprocess.TimeoutExpired):
        return {}
    got, at = {}, 0
    for spec in specs:
        nl = out.find(b"\n", at)
        head = out[at:nl].split() if nl >= 0 else []
        size = int(head[2]) if len(head) == 3 and head[2].isdigit() else -1
        got[spec] = out[nl + 1:nl + 1 + size] if size >= 0 and head[1] == b"blob" else None
        at = nl + 2 + size if size >= 0 else nl + 1
    return got


def outside(data: bytes | None) -> list[str] | None:
    """The lines outside Flow's one marked block (and the CUSTOM:SKILL wrapper right around it), blank lines at the
    seams dropped; the whole file when it has no block; None when its markers are not one BEGIN, then one END."""
    lines = (data or b"").decode("utf-8", "replace").replace("\r\n", "\n").split("\n")
    marks = [(i, m[1]) for i, ln in enumerate(lines) if (m := MARK.match(ln))]
    if marks and [k for _, k in marks] != ["BEGIN", "END"]:
        return None
    a, b = (marks[0][0], marks[1][0]) if marks else (len(lines), len(lines) - 1)
    if marks and a > 0 and lines[a - 1] == WRAP[0] and b + 1 < len(lines) and lines[b + 1] == WRAP[1]:
        a, b = a - 1, b + 1
    before, after = lines[:a], lines[b + 1:]
    while before and not before[-1].strip():
        before.pop()
    while after and not after[0].strip():
        after.pop(0)
    while after and not after[-1].strip():
        after.pop()
    return before + after


def foreign(root: Path, pairs: list[tuple[str, str]]) -> list[str]:
    """The staged (status, path) pairs' paths that are not Flow's own; empty when the `flow:` subject passes."""
    side = {p: "HEAD" if s.startswith("D") else "" for s, p in pairs}
    specs = [f"HEAD:{m}" for m in (MANIFEST, *ASSETS_5X, *MIRRORS_5X)] + [f":{MANIFEST}"]
    specs += [f"{side[p]}:{p}" for p in side] + [f"HEAD:{p}" for p in side if p in MERGED]
    b = blobs(root, specs)

    def rows(spec: str, key: str) -> list[tuple[str, str]]:
        try:
            return [(e["path"], e["sha256"]) for e in json.loads(b.get(spec) or b"{}").get(key) or []]
        except (ValueError, AttributeError, KeyError, TypeError):
            return []
    head = rows(f"HEAD:{MANIFEST}", "files") + [r for m in ASSETS_5X for r in rows(f"HEAD:{m}", "assets")]
    head += [(m[1], m[2]) for f in MIRRORS_5X for ln in (b.get(f"HEAD:{f}") or b"").decode("utf-8", "replace")
             .splitlines() if (m := ROW.fullmatch(ln))]
    staged, recorded = dict(rows(f":{MANIFEST}", "files")), {p for p, _ in head}
    named = {(p.rsplit("/", 1)[-1], s) for p, s in head}  # a mirror keeps its source's name and bytes
    tree_5x = b.get(f"HEAD:{MC_5X}") is not None

    def own(s: str, p: str) -> bool:
        data = b.get(f"{side[p]}:{p}")
        sha = hashlib.sha256(data).hexdigest() if data is not None else None
        if p == MANIFEST:
            return True
        if s.startswith("D"):
            return p in recorded or (p.rsplit("/", 1)[-1], sha) in named or (
                tree_5x and (p in RETIRED_5X or bool(BYTECODE.fullmatch(p))))
        if p in MERGED:
            kept = outside(data)
            return (tree_5x and p in OVERLAYS) or (kept is not None and kept == outside(b.get(f"HEAD:{p}")))
        return sha is not None and staged.get(p) == sha
    return [p for s, p in pairs if not own(s, p)]
