#!/usr/bin/env python3
"""Fusebase Flow — post_tool_use handler.

Logs and inspects completed tool calls. Does NOT undo automatically. Reports:
- changed files after Edit/Write tools
- protected-path modifications (warn-level audit signal)
- diff summary (lightweight) when applicable
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.git_utils import diff_paths, status_short  # noqa: E402
from shared.path_policy import evaluate as evaluate_path  # noqa: E402
from shared.policy_loader import find_git_root  # noqa: E402


EDIT_LIKE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "ApplyDiff", "create_file"}


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        root = None

    tool_name = event.get("tool_name", "")
    extra: dict = {"tool_name": tool_name}

    if root and tool_name in EDIT_LIKE_TOOLS:
        # Snapshot what changed since HEAD; surface protected-path edits if any.
        try:
            changed = diff_paths(root, against="HEAD")
        except Exception:
            changed = []
        extra["changed_paths"] = changed
        protected_hits = []
        for p in changed:
            pd = evaluate_path(p, root=root)
            if pd.protected:
                protected_hits.append({"path": p, "category": pd.category, "has_exception": pd.has_exception})
        if protected_hits:
            extra["protected_paths_modified"] = protected_hits
            emit(
                "post_tool_use",
                decision="warn",
                reason="protected paths modified — verify approval artifact (FR-07)",
                rule_id="FR-07",
                extra=extra,
                root=root,
            )
            sys.stdout.write(json.dumps({"decision": "warn", "warnings": [
                f"protected path modified: {h['path']} (category={h['category']}, exception={h['has_exception']})"
                for h in protected_hits
            ]}))
            return 0

    # Lightweight short status snapshot for audit only.
    if root:
        try:
            extra["git_status_short_lines"] = len(status_short(root).splitlines())
        except Exception:
            pass

    emit("post_tool_use", decision="allow", reason="logged", extra=extra, root=root)
    sys.stdout.write(json.dumps({"decision": "allow"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
