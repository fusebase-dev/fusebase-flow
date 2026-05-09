#!/usr/bin/env python3
"""Fusebase Flow — task_complete handler.

Lifecycle event for hosts that emit a task-completion signal. Generates a final
task summary and confirms required artifacts exist. Lighter than `stop` — does
not block; produces a checklist for the operator's next action.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.git_utils import is_clean, recent_commits  # noqa: E402
from shared.policy_loader import find_git_root  # noqa: E402


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        root = None

    summary_lines = ["Task complete — Fusebase Flow checklist:"]
    if root:
        try:
            clean = is_clean(root)
            summary_lines.append(f"  Working tree clean: {'yes' if clean else 'NO — uncommitted changes'}")
        except Exception:
            summary_lines.append("  Working tree clean: unknown")
        try:
            commits = recent_commits(root, n=5).strip().splitlines()
            summary_lines.append("  Recent commits:")
            for c in commits[:5]:
                summary_lines.append(f"    {c}")
        except Exception:
            pass

    summary_lines.extend([
        "",
        "Next operator actions to consider:",
        "  - Review the diff: `git log --oneline` and `git diff <baseline>..HEAD`",
        "  - Verify gate report against `docs/specs/<slug>/verification-gate.md`",
        "  - If clean: invoke `code-review` skill, then (if also clean) `release-deploy-reporting`",
        "  - If anything's off: file follow-up backlog ticket; don't bypass the gate",
    ])

    summary = "\n".join(summary_lines)
    print(summary, file=sys.stderr)

    emit(
        "task_complete",
        decision="allow",
        reason="checklist emitted",
        extra={"clean_tree": is_clean(root) if root else None},
        root=root,
    )

    sys.stdout.write(json.dumps({"decision": "allow", "summary": summary}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
