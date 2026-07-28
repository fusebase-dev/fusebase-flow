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

from .approval_artifact import (
    Verdict,
    compute_command_digest,
    compute_repo_id,
    evaluate_file,
    is_acceptable,
)
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
    action_verdicts: dict[str, str] = field(default_factory=dict)


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


def _approval_state(
    action: str,
    *,
    root: Path | None = None,
    command: str | None = None,
    strict: bool = False,
) -> tuple[bool, str]:
    """(acceptable-artifact-present, worst-failing-verdict) for one action name.

    Binding (decision K2) is ADDITIVE: an artifact carrying `command_digest` and/or
    `repo_id` authorizes only a matching command in a matching repo; one carrying
    neither stays action-scoped, plus the AC1-AC3 tightening.
    """
    resolved = resolve_root(root)
    if resolved is None:
        return False, NO_ARTIFACT
    approvals_dir = resolved / "state" / "approvals"
    if not approvals_dir.exists():
        return False, NO_ARTIFACT
    digest = compute_command_digest(command) if command is not None else None
    repo_id = compute_repo_id(resolved)
    best: Verdict | None = None
    for f in sorted(approvals_dir.glob(f"{action}-*.json")):
        verdict = evaluate_file(
            f, expected_action=action, command_digest=digest, repo_id=repo_id
        )
        if is_acceptable(verdict, strict=strict):
            return True, verdict.value
        if best is None or _VERDICT_RANK.get(verdict, 0) > _VERDICT_RANK.get(best, 0):
            best = verdict
    return False, best.value if best else NO_ARTIFACT


def _approval_artifact_present(action: str, *, root: Path | None = None) -> bool:
    """Back-compat wrapper: callers that only need the boolean."""
    return _approval_state(action, root=root)[0]


POLICY_ERROR_RULE_ID = "FLOW-POLICY-ERROR"


def _policy_error(command: str, detail: str) -> CommandDecision:
    return CommandDecision(
        command=command,
        decision="deny",
        reason=(
            f"FR-12/K4: command-policy is defective, so the gate cannot be evaluated — "
            f"denying (fail closed). {detail} Fix policies/command-policy.yml."
        ),
        rule_id=POLICY_ERROR_RULE_ID,
    )


def _rule_matches(rule: Any, command: str, stage: str) -> tuple[bool, str | None]:
    """(matched, policy-error-detail). A defective rule NEVER silently skips (K4).

    TRIPWIRE: `re.error` and a malformed rule must DENY, not `continue`. The original
    code skipped both, so a typo in a deny pattern silently disabled that rule and the
    command fell through to `default: allow` — a gate whose failure mode is "allow".
    """
    if not isinstance(rule, dict):
        return False, f"{stage} rule is not a mapping"
    pattern = rule.get("pattern")
    if not isinstance(pattern, str) or not pattern:
        return False, f"{stage} rule has no usable `pattern`"
    try:
        return bool(re.search(pattern, command)), None
    except re.error as e:
        return False, f"{stage} rule pattern {pattern!r} is not a valid regex ({e})."


def _evaluate_deny(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("deny", []) or []:
        matched, err = _rule_matches(rule, command, "deny")
        if err:
            return _policy_error(command, err)
        if matched:
            return CommandDecision(
                command=command,
                decision="deny",
                reason=rule.get("reason", "denied by command-policy"),
                rule_id=rule.get("rule_id", "FR-06"),
                matched_pattern=rule["pattern"],
            )
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

    # ALL-MATCH (decision K8): every matching rule contributes its action to the required
    # set. First-match-wins let `fusebase deploy && npx prisma migrate deploy` be authorized
    # by the deploy artifact alone, leaving the migration ungated. Stage order is unchanged —
    # `deny` short-circuits, so a denied command never reaches this stage (K16).
    matched_rule: dict[str, Any] | None = None
    unsatisfied: list[str] = []
    satisfied: list[str] = []
    verdicts: dict[str, str] = {}

    for rule in policy.get("require_approval", []) or []:
        if isinstance(rule, dict):
            only_when = rule.get("only_when") or {}
            if only_when.get("workflow_mode") and only_when["workflow_mode"] != workflow_mode:
                continue
        matched, err = _rule_matches(rule, command, "require_approval")
        if err:
            return _policy_error(command, err)
        if not matched:
            continue
        if matched_rule is None:
            matched_rule = rule
        action = rule.get("action", "")
        if action in verdicts:
            continue
        present, verdict = _approval_state(action, root=root, command=command)
        verdicts[action] = verdict
        (satisfied if present else unsatisfied).append(action)

    if matched_rule is None:
        return None

    if not unsatisfied:
        return CommandDecision(
            command=command,
            decision="allow",
            reason=f"require_approval matched ({', '.join(satisfied)}); artifact(s) present.",
            rule_id=matched_rule.get("rule_id", "FR-12"),
            matched_pattern=matched_rule["pattern"],
            approval_action=satisfied[0] if satisfied else "",
            approval_artifact_present=True,
            approval_verdict=verdicts.get(satisfied[0], "") if satisfied else "",
            required_actions=list(satisfied),
            action_verdicts=verdicts,
        )

    lead = unsatisfied[0]
    states = "; ".join(f"{a}: {verdicts[a]}" for a in unsatisfied)
    mint = " && ".join(f"bash hooks/local/approve-local.sh {a} <slug>" for a in unsatisfied)
    return CommandDecision(
        command=command,
        decision="deny" if on_missing == "deny" else "ask",
        reason=(
            f"FR-12: command requires approval for {', '.join(unsatisfied)}; "
            f"artifact state — {states}. "
            f"On the operator's approval, the agent authors them (the operator runs nothing): "
            f"`{mint}`. "
            f"See workflows/violation-recovery.md for full recovery procedure; "
            f"role-specific don't-list at flow-skills/role-discipline/references/<role>.md."
        ),
        rule_id=matched_rule.get("rule_id", "FR-12"),
        matched_pattern=matched_rule["pattern"],
        approval_action=lead,
        approval_artifact_present=False,
        approval_verdict=verdicts[lead],
        required_actions=list(unsatisfied),
        action_verdicts=verdicts,
    )


def _evaluate_allow(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("allow", []) or []:
        matched, err = _rule_matches(rule, command, "allow")
        if err:
            return _policy_error(command, err)
        if matched:
            return CommandDecision(
                command=command,
                decision="allow",
                reason=rule.get("reason", "allowed by command-policy allow list"),
                rule_id=rule.get("rule_id", ""),
                matched_pattern=rule["pattern"],
            )
    return None


def evaluate(command: str, *, root: Path | None = None) -> CommandDecision:
    if not command:
        return CommandDecision(command=command, decision="allow", reason="empty command")
    resolved = resolve_root(root)
    # FAIL-CLOSED at the policy load-point (K4): a missing, empty, unreadable or
    # non-mapping command-policy previously yielded {} and fell straight through to
    # `default: allow` — every gated command silently ungated. Deny instead.
    try:
        policy = get_policy("command-policy", root=resolved)
        approval_policy = get_policy("approval-policy", root=resolved)
    except BaseException as e:                       # noqa: BLE001 — load errors must deny
        return _policy_error(command, f"policy load failed ({e!r}).")
    if not isinstance(policy, dict) or not policy:
        return _policy_error(command, "command-policy is missing or empty.")
    if not isinstance(approval_policy, dict):
        return _policy_error(command, "approval-policy is not a mapping.")
    if not any(policy.get(stage) for stage in ("deny", "require_approval", "allow")):
        return _policy_error(command, "command-policy declares no deny/require_approval/allow rules.")
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
