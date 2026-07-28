"""Fusebase Flow — command_policy.

Reads policies/command-policy.yml and policies/approval-policy.yml. Decides
whether a shell command is allowed, denied, or requires approval. Approval
checking looks in state/approvals/ for matching artifacts.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .approval_artifact import Verdict, evaluate_file, is_acceptable
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
    approval_verdict: str = ""   # the failing Verdict, for the AC14 denial renderer
    required_actions: list[str] = field(default_factory=list)


# Reporting priority when several artifacts for one action all fail: name the most
# specific failure, so the operator can tell a stale approval from an absent one (AC14).
_VERDICT_RANK = {
    Verdict.BINDING_MISMATCH: 5,
    Verdict.ACTION_MISMATCH: 4,
    Verdict.EXPIRED: 3,
    Verdict.MISSING_EXPIRY: 2,
    Verdict.MALFORMED: 1,
}
NO_ARTIFACT = "NO_ARTIFACT"


def resolve_root(root: Path | None) -> Path | None:
    """The repo root every policy read and artifact lookup anchors on (AC4).

    TRIPWIRE: policy files MUST be read with this root, never from the process CWD —
    a hook invoked from a subdirectory or a foreign CWD would otherwise silently load
    a different (or no) policy while artifact lookup used the passed root.
    """
    if root is not None:
        return root
    try:
        return find_git_root()
    except (FileNotFoundError, OSError):
        return None


def _approval_state(action: str, *, root: Path | None = None) -> tuple[bool, str]:
    """(acceptable-artifact-present, worst-failing-verdict) for one action name."""
    resolved = resolve_root(root)
    if resolved is None:
        return False, NO_ARTIFACT
    approvals_dir = resolved / "state" / "approvals"
    if not approvals_dir.exists():
        return False, NO_ARTIFACT
    best: Verdict | None = None
    for f in sorted(approvals_dir.glob(f"{action}-*.json")):
        verdict = evaluate_file(f, expected_action=action)
        if is_acceptable(verdict, strict=False):
            return True, verdict.value
        if best is None or _VERDICT_RANK.get(verdict, 0) > _VERDICT_RANK.get(best, 0):
            best = verdict
    return False, best.value if best else NO_ARTIFACT


def _approval_artifact_present(action: str, *, root: Path | None = None) -> bool:
    """Back-compat wrapper: callers that only need the boolean."""
    return _approval_state(action, root=root)[0]


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
        present, verdict = _approval_state(action, root=root)
        if present:
            return CommandDecision(
                command=command,
                decision="allow",
                reason=f"require_approval matched ({action}); artifact present.",
                rule_id=rule.get("rule_id", "FR-12"),
                matched_pattern=rule["pattern"],
                approval_action=action,
                approval_artifact_present=True,
                approval_verdict=verdict,
                required_actions=[action],
            )
        decision = "deny" if on_missing == "deny" else "ask"
        return CommandDecision(
            command=command,
            decision=decision,
            reason=(
                f"FR-12: command requires approval ({action}); artifact state: {verdict}. "
                f"On the operator's approval, the agent authors it (the operator runs nothing): "
                f"`bash hooks/local/approve-local.sh {action} <slug>`. "
                f"See workflows/violation-recovery.md for full recovery procedure; "
                f"role-specific don't-list at flow-skills/role-discipline/references/<role>.md."
            ),
            rule_id=rule.get("rule_id", "FR-12"),
            matched_pattern=rule["pattern"],
            approval_action=action,
            approval_artifact_present=False,
            approval_verdict=verdict,
            required_actions=[action],
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
    resolved = resolve_root(root)
    policy = get_policy("command-policy", root=resolved)
    approval_policy = get_policy("approval-policy", root=resolved)
    order = policy.get("match_order", ["deny", "require_approval", "allow"])
    default = policy.get("default", "allow")

    for stage in order:
        if stage == "deny":
            d = _evaluate_deny(command, policy)
            if d:
                return d
        elif stage == "require_approval":
            d = _evaluate_require_approval(command, policy, approval_policy, root=resolved)
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


__all__ = ["CommandDecision", "NO_ARTIFACT", "evaluate", "resolve_root"]
