"""Fusebase Flow — command_policy.

Reads policies/command-policy.yml and policies/approval-policy.yml. Decides
whether a shell command is allowed, denied, or requires approval. Approval
checking looks in state/approvals/ for matching artifacts.
"""
from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .policy_loader import find_git_root, get_policy


@dataclass
class CommandDecision:
    command: str
    decision: str           # allow | deny | ask
    reason: str = ""
    rule_id: str = ""
    matched_pattern: str = ""
    approval_action: str = ""    # populated when require_approval triggered
    approval_artifact_present: bool = False


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _approval_artifact_present(action: str, *, root: Path | None = None) -> bool:
    """Look for a non-expired approval artifact for the given action name."""
    root = root or find_git_root()
    approvals_dir = root / "state" / "approvals"
    if not approvals_dir.exists():
        return False
    pattern = f"{action}-*.json"
    now = _now_iso()
    for f in approvals_dir.glob(pattern):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        expires = data.get("expires_at", "")
        if expires and expires < now:
            continue
        return True
    return False


def _evaluate_deny(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("deny", []) or []:
        try:
            if re.search(rule["pattern"], command):
                return CommandDecision(
                    command=command,
                    decision="deny",
                    reason=rule.get("reason", "denied by command-policy"),
                    rule_id=rule.get("rule_id", "FR-06"),
                    matched_pattern=rule["pattern"],
                )
        except re.error:
            continue
    return None


def _evaluate_require_approval(
    command: str,
    policy: dict[str, Any],
    approval_policy: dict[str, Any],
    *,
    root: Path | None = None,
) -> CommandDecision | None:
    workflow_mode = approval_policy.get("workflow_mode", "direct_to_main")
    on_missing = approval_policy.get("on_missing_artifact", "deny")
    for rule in policy.get("require_approval", []) or []:
        only_when = rule.get("only_when") or {}
        if only_when.get("workflow_mode") and only_when["workflow_mode"] != workflow_mode:
            continue
        try:
            if not re.search(rule["pattern"], command):
                continue
        except re.error:
            continue
        action = rule.get("action", "")
        present = _approval_artifact_present(action, root=root)
        if present:
            return CommandDecision(
                command=command,
                decision="allow",
                reason=f"require_approval matched ({action}); artifact present.",
                rule_id=rule.get("rule_id", "FR-12"),
                matched_pattern=rule["pattern"],
                approval_action=action,
                approval_artifact_present=True,
            )
        decision = "deny" if on_missing == "deny" else "ask"
        return CommandDecision(
            command=command,
            decision=decision,
            reason=(
                f"FR-12: command requires approval ({action}); no artifact found in "
                f"state/approvals/. "
                f"Author one with `bash hooks/local/approve-local.sh {action} <slug>`. "
                f"See workflows/violation-recovery.md for full recovery procedure; "
                f"role-specific don't-list at flow-skills/role-discipline/references/<role>.md."
            ),
            rule_id=rule.get("rule_id", "FR-12"),
            matched_pattern=rule["pattern"],
            approval_action=action,
            approval_artifact_present=False,
        )
    return None


def _evaluate_allow(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("allow", []) or []:
        try:
            if re.search(rule["pattern"], command):
                return CommandDecision(
                    command=command,
                    decision="allow",
                    reason=rule.get("reason", "allowed by command-policy allow list"),
                    rule_id=rule.get("rule_id", ""),
                    matched_pattern=rule["pattern"],
                )
        except re.error:
            continue
    return None


def evaluate(command: str, *, root: Path | None = None) -> CommandDecision:
    if not command:
        return CommandDecision(command=command, decision="allow", reason="empty command")
    policy = get_policy("command-policy")
    approval_policy = get_policy("approval-policy")
    order = policy.get("match_order", ["deny", "require_approval", "allow"])
    default = policy.get("default", "allow")

    for stage in order:
        if stage == "deny":
            d = _evaluate_deny(command, policy)
            if d:
                return d
        elif stage == "require_approval":
            d = _evaluate_require_approval(command, policy, approval_policy, root=root)
            if d:
                return d
        elif stage == "allow":
            d = _evaluate_allow(command, policy)
            if d:
                return d

    return CommandDecision(
        command=command,
        decision=default,
        reason=f"no rule matched; default={default}",
    )


__all__ = ["CommandDecision", "evaluate"]
