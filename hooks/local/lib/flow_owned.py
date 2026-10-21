"""Which staged paths are not Flow's own: the rule of the `flow:` subject (O-21), for hooks/local/lib/commit_msg.py.

Flow's own, besides the four documents (commit_msg.py checks those):
- an added or changed path whose staged bytes have the sha256 the staged audit/flow-install.json records for it, when
  HEAD's manifest records that path or it lies where the install writes (FLOW_PATHS); never because a row the same
  commit adds names it (M6-7, review r1-32); and that manifest itself, a protected path;
- a deleted path recorded at HEAD by that manifest or by a 5.x Flow manifest, or whose name and HEAD bytes are those
  of a path one of them records (a 5.x command mirror); on the migration commit also the files it deletes by name,
  bytecode and the orphan 5.x backups (`*.pre-flow-repair[.<n>]` under .claude/, .agents/ and .codex/);
- AGENTS.md, CLAUDE.md, .gitattributes and .gitignore when the change stays inside Flow's marked block, checked
  against HEAD (.gitattributes may also lose its Flow 5.x line-ending pins, eol_pins.py); on the migration commit
  AGENTS.md and CLAUDE.md whole (it replaces 5.x's section, which no marker
  bounds; the owner's decision of 2026-10-19).
The migration commit is the one that deletes HEAD's audit/managed-content-manifest.json, as every 5.x migration does.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eol_pins  # noqa: E402
from flow_docs import blobs  # noqa: E402  (git cat-file --batch, the shared git reader)

MANIFEST, MC_5X = "audit/flow-install.json", "audit/managed-content-manifest.json"
ASSETS_5X = (MC_5X, "audit/hook-layer-manifest.json")  # {"assets": [{"path", "sha256"}]}
MIRRORS_5X = ("audit/skill-mirror-manifest.txt", "audit/agent-mirror-manifest.txt")  # "<path>  <sha256>" rows
ROW = re.compile(r"(.+?)  ([0-9a-f]{64})")
# What maintainer/migrate.py deletes by name (AUDIT_5X, ROOT_5X, ORPHANS; test_commits keeps the two in step).
RETIRED_5X = (*ASSETS_5X, *MIRRORS_5X, "audit/README.md", "audit/cli-upstream-manifest.json",
              "audit/cli-vendor-manifest.json", "GEMINI.md", "install.sh", "policies/model-routing.local.yml")
BYTECODE = re.compile(r"hooks/.*(/__pycache__/.*|\.py[co])")
REPAIR_BACKUP = re.compile(r"\.(claude|agents|codex)/.+\.pre-flow-repair(\.\d+)?")  # migrate.py's orphan 5.x backups
MERGED, OVERLAYS = ("AGENTS.md", "CLAUDE.md", ".gitattributes", ".gitignore"), ("AGENTS.md", "CLAUDE.md")
# Where the install writes (maintainer/flow.py planned_files(): CORE_PATTERNS, the provider mirrors, the project's
# module-size rows; test_m8 keeps the two in step); `*` stays inside one folder, and the CLI's app-* agents are not Flow's.
FLOW_PATHS = ("FLOW_RULES.md", "VERSION", "hooks/requirements.txt", "hooks/git/*", "hooks/shared/*.py", "hooks/handlers/*.py",
              "hooks/local/*.sh", "hooks/local/*.py", "hooks/local/lib/*.sh", "hooks/local/lib/*.py", "policies/*.yml",
              "policies/module-size-baseline.txt", "policies/module-size-baseline.project.txt", "agents/*/AGENT.md",
              "flow-skills/*/SKILL.md", "templates/*.md", "workflows/*.md", ".claude/skills/*/SKILL.md",
              ".agents/skills/*/SKILL.md", ".claude/agents/*.md", ".codex/agents/*.toml")
MARK = re.compile(r"(?:<!-- |# )FLOW:(BEGIN|END)\b")
WRAP = ("<!-- CUSTOM:SKILL:BEGIN -->", "<!-- CUSTOM:SKILL:END -->")


def flow_path(path: str) -> bool:
    return not re.match(r"\.(claude|codex)/agents/app-", path) and any(
        fnmatch.fnmatchcase(path, g) and path.count("/") == g.count("/") for g in FLOW_PATHS)


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


def foreign(root: Path, pairs: list[tuple[str, str]], base: str = "HEAD", tip: str = "") -> list[str]:
    """The (status, path) pairs' paths that are not Flow's own, the change from `base` to `tip` ("" the index): empty
    when the `flow:` subject passes; range_check.py asks it of a commit already made (base its parent, tip the commit)."""
    side = {p: base if s.startswith("D") else tip for s, p in pairs}
    specs = [f"{base}:{m}" for m in (MANIFEST, *ASSETS_5X, *MIRRORS_5X)] + [f"{tip}:{MANIFEST}"]
    specs += [f"{side[p]}:{p}" for p in side] + [f"{base}:{p}" for p in side if p in MERGED]
    b = blobs(root, specs)

    def rows(spec: str, key: str) -> list[tuple[str, str]]:
        try:
            return [(e["path"], e["sha256"]) for e in json.loads(b.get(spec) or b"{}").get(key) or []]
        except (ValueError, AttributeError, KeyError, TypeError):
            return []
    head = rows(f"{base}:{MANIFEST}", "files") + [r for m in ASSETS_5X for r in rows(f"{base}:{m}", "assets")]
    head += [(m[1], m[2]) for f in MIRRORS_5X for ln in (b.get(f"{base}:{f}") or b"").decode("utf-8", "replace")
             .splitlines() if (m := ROW.fullmatch(ln))]
    staged, recorded = dict(rows(f"{tip}:{MANIFEST}", "files")), {p for p, _ in head}
    installed = {p for p, _ in rows(f"{base}:{MANIFEST}", "files")}
    named = {(p.rsplit("/", 1)[-1], s) for p, s in head}  # a mirror keeps its source's name and bytes
    migrating = b.get(f"{base}:{MC_5X}") is not None and side.get(MC_5X) == base

    def own(s: str, p: str) -> bool:
        data = b.get(f"{side[p]}:{p}")
        sha = hashlib.sha256(data).hexdigest() if data is not None else None
        if p == MANIFEST:
            return True
        if s.startswith("D"):
            return p in recorded or (p.rsplit("/", 1)[-1], sha) in named or (
                migrating and (p in RETIRED_5X or bool(BYTECODE.fullmatch(p) or REPAIR_BACKUP.fullmatch(p))))
        if p in MERGED:
            kept, old = outside(data), outside(b.get(f"{base}:{p}"))
            unpinned = p == ".gitattributes" and kept is not None and old is not None and [x for x in kept if x.strip()] \
                == [x for x in old if x.strip() and not eol_pins.is_5x_pin(x)]
            return (migrating and p in OVERLAYS) or (kept is not None and kept == old) or unpinned
        return sha is not None and staged.get(p) == sha and (p in installed or flow_path(p))
    return [p for s, p in pairs if not own(s, p)]
