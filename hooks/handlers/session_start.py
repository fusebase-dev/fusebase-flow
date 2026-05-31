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


REQUIRED_TOP_FILES = [
    "AGENTS.md",
    "FLOW_RULES.md",
    "VERSION",
    "skills/communication/SKILL.md",     # mandatory: Mode A / Mode B discipline
    "skills/role-discipline/SKILL.md",   # mandatory: per-role don't-list + refusal phrasing
]
REQUIRED_DIRS = [
    "skills",
    "workflows",
    "policies",
    "templates",
]


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

    missing_files = [f for f in REQUIRED_TOP_FILES if not (root / f).exists()]
    missing_dirs = [d for d in REQUIRED_DIRS if not (root / d).is_dir()]

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

    # Active project context (Layer 2 of artifact discovery — Claude Code accelerator).
    # Additive, read-only: surface project artifacts if the project has been onboarded.
    # Absent by default; absence changes nothing (AGENTS.md instruction + skill
    # existence-guards cover discovery universally, hook or no hook).
    project_artifacts = []
    for rel in ("docs/north-star.md", "docs/audience.md"):
        if (root / rel).exists():
            project_artifacts.append(rel)
    try:
        for p in sorted((root / "docs").glob("*/product.md")):
            project_artifacts.append(str(p.relative_to(root)).replace("\\", "/"))
        for p in sorted((root / "docs").glob("*/business-logic.md")):
            project_artifacts.append(str(p.relative_to(root)).replace("\\", "/"))
    except OSError:
        pass
    if project_artifacts:
        summary_lines.append("Active project context (read + follow these):")
        for a in project_artifacts:
            summary_lines.append(f"  • {a}")
    else:
        summary_lines.append("Active project context: none (not onboarded — run /onboard to capture vision).")

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
