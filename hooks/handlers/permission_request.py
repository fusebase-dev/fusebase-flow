#!/usr/bin/env python3
"""Fusebase Flow — permission_request handler.

Handles explicit permission prompts where the host runtime supports them.
Reads the pending action's category and looks up an approval artifact in
state/approvals/. If found and unexpired, allow. Otherwise deny.

This is a complement to pre_tool_use, not a replacement: command-policy +
git hooks remain as defense-in-depth.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.command_policy import (  # noqa: E402
    evaluate as evaluate_command,
    is_command_tool,
)
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

    pr = event.get("permission_request") or {}
    tool_name = pr.get("tool_name") or event.get("tool_name") or ""
    tool_input = pr.get("tool_input") or event.get("tool_input") or {}

    # If this is a command-carrying tool, defer to command_policy (E6). The set is
    # shared.command_policy.COMMAND_TOOL_NAMES — this handler used to keep its own
    # literal, which was narrower still than pre_tool_use's (no ExecuteCommand, no
    # PowerShell), so a gated command arriving here fell through to the "ask" default
    # and an FR-06 hard deny silently degraded to an operator prompt.
    if is_command_tool(tool_name):
        command = tool_input.get("command") or ""
        if command:
            cd = evaluate_command(command, root=root)
            decision = cd.decision
            reason = cd.reason
            rule_id = cd.rule_id
            emit(
                "permission_request",
                decision=decision,
                reason=reason,
                rule_id=rule_id,
                extra={
                    "tool_name": tool_name,
                    "matched_pattern": cd.matched_pattern,
                    "approval_action": cd.approval_action,
                    "approval_verdict": cd.approval_verdict,
                    "required_actions": cd.required_actions,
                    "all_required_actions": cd.all_required_actions,
                    "action_verdicts": cd.action_verdicts,
                },
                root=root,
            )
            sys.stdout.write(json.dumps({"decision": decision, "reason": reason, "rule_id": rule_id}))
            return 2 if decision == "deny" else 0

    # Otherwise, surface to operator for manual confirmation. Default: ask.
    decision = "ask"
    reason = (
        "Action requires explicit operator confirmation. "
        "If approval artifact exists at state/approvals/, "
        "it will be honored; otherwise operator must approve in chat."
    )
    emit("permission_request", decision=decision, reason=reason, root=root, extra={"tool_name": tool_name})
    sys.stdout.write(json.dumps({"decision": decision, "reason": reason}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
