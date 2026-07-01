#!/usr/bin/env python3
"""Fusebase Flow — session_start handler.

Loads lightweight repo state at agent/session start. Does NOT block by default;
exit 0 always (warnings printed to stderr).

Reads stdin JSON event matching hooks/flow_hook_event.schema.json.
Writes JSON decision to stdout.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Ensure shared/ is on sys.path when invoked as a script.
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.policy_loader import find_git_root  # noqa: E402


# Canonical skills live at flow-skills/ (v3.9.0+); root skills/ is the legacy
# pre-3.9.0 location, accepted as a fallback. SKILLS_CANON is resolved at runtime
# against the actual repo so a not-yet-migrated tree still validates.
REQUIRED_TOP_FILES_BASE = [
    "AGENTS.md",
    "FLOW_RULES.md",
    "VERSION",
]
# {canon} is substituted with the resolved canonical skills dir name.
REQUIRED_SKILL_FILES = [
    "{canon}/communication/SKILL.md",     # mandatory: Mode A / Mode B discipline
    "{canon}/role-discipline/SKILL.md",   # mandatory: per-role don't-list + refusal phrasing
]
REQUIRED_DIRS_BASE = [
    "workflows",
    "policies",
    "templates",
]


def _skills_canon(root: Path) -> str:
    return "flow-skills" if (root / "flow-skills").is_dir() else "skills"


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        out = {
            "decision": "warn",
            "reason": "Not a git repo or FUSEBASE_FLOW_ROOT not set; Fusebase Flow context unavailable.",
        }
        sys.stdout.write(json.dumps(out))
        return 0

    canon = _skills_canon(root)
    required_files = REQUIRED_TOP_FILES_BASE + [f.format(canon=canon) for f in REQUIRED_SKILL_FILES]
    required_dirs = REQUIRED_DIRS_BASE + [canon]
    missing_files = [f for f in required_files if not (root / f).exists()]
    missing_dirs = [d for d in required_dirs if not (root / d).is_dir()]

    version_path = root / "VERSION"
    version = version_path.read_text(encoding="utf-8").strip() if version_path.exists() else "unknown"

    summary_lines = [
        f"Fusebase Flow {version} — session bootstrap",
        f"Repo: {root}",
    ]
    if missing_files or missing_dirs:
        summary_lines.append("WARNING — incomplete installation:")
        for f in missing_files:
            summary_lines.append(f"  missing file: {f}")
        for d in missing_dirs:
            summary_lines.append(f"  missing dir:  {d}")
        summary_lines.append("Run `bash hooks/local/preflight.sh` to validate.")
    else:
        summary_lines.append("Required structure: ok")

    # Write-time discipline reminder (FR-24). Opt-in hook + no sub-agent reach — the
    # always-on carrier is role-discipline § Write-time discipline digest.
    summary_lines.append(
        "Write-time discipline (FR-24) in force when writing code/docs: "
        "FR-23 doc-budget · FR-09 Mode B · FR-22 comments · FR-18 supersede · "
        "FR-25 module-size ratchet (don't grow over-ceiling files; extract on a seam) "
        "— see role-discipline § Write-time discipline digest"
    )
    summary_lines.append(
        "Liveness (FR-27): never launch long/silent background work bare — bound it "
        "(source hooks/local/lib/bounded-run.sh), complete it in-turn, or return "
        "BLOCKED-AT-<gate> + a record-then-read pointer; a hung task emits no "
        "completion event and you idle silently — see flow-skills/liveness-discipline"
    )

    # Active project context (Layer 2 of artifact discovery — Claude Code accelerator).
    # Additive, read-only: surface project artifacts if the project has been onboarded.
    # Absent by default; absence changes nothing (AGENTS.md instruction + skill
    # existence-guards cover discovery universally, hook or no hook).
    project_artifacts = []
    for rel in ("docs/north-star.md", "docs/audience.md"):
        if (root / rel).exists():
            project_artifacts.append(rel)
    try:
        # rglob so nested app layouts (e.g. docs/apps/foo/product.md) are surfaced too.
        for name in ("product.md", "business-logic.md"):
            for p in sorted((root / "docs").rglob(name)):
                project_artifacts.append(str(p.relative_to(root)).replace("\\", "/"))
    except OSError:
        pass
    if project_artifacts:
        summary_lines.append("Active project context (read + follow these):")
        for a in project_artifacts:
            summary_lines.append(f"  • {a}")
    else:
        summary_lines.append("Active project context: none (not onboarded — run /onboard to capture vision).")

    # Problem catalog pointer (WS7): if the repo has filed problems, remind the session
    # to consult the index before touching a known-problem surface. Pointer-only (FR-23);
    # quiet on repos with no filed entries.
    try:
        catalog_entries = sorted((root / "docs" / "problem-catalog").glob("*/problem.md"))
    except OSError:
        catalog_entries = []
    if catalog_entries:
        summary_lines.append(
            f"Problem catalog: {len(catalog_entries)} filed problem(s) — read "
            "docs/problem-catalog/README.md index before touching MSYS/install-upgrade/"
            "secret-scan/FR-07 surfaces so you recognize a known problem, not re-diagnose it"
        )

    summary = "\n".join(summary_lines)
    print(summary, file=sys.stderr)

    emit(
        "session_start",
        decision="allow",
        reason="bootstrap context emitted",
        extra={
            "version": version,
            "missing_files": missing_files,
            "missing_dirs": missing_dirs,
        },
        root=root,
    )

    out = {
        "decision": "allow",
        "context_summary": summary,
        "version": version,
    }
    sys.stdout.write(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
