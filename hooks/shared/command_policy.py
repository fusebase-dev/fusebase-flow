"""Fusebase Flow — command_policy.

Reads policies/command-policy.yml and policies/approval-policy.yml. Decides
whether a shell command is allowed, denied, or requires approval. Approval
checking looks in state/approvals/ for matching artifacts.
"""
from __future__ import annotations

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
from .command_rules import rule_actions, rule_matches
from .denial_message import render_approval_denial
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
    # TRIPWIRE (K18b): `required_actions` stays the UNSATISFIED set (its long-standing
    # meaning for callers); `all_required_actions` is every action the matched rules
    # demand, satisfied or not. AC6/AC14/S5 require the denial to name the full set.
    all_required_actions: list[str] = field(default_factory=list)


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
            if verdict is Verdict.MISSING_EXPIRY:
                _log_legacy_acceptance(f, action, root=resolved)
            return True, verdict.value
        if best is None or _VERDICT_RANK.get(verdict, 0) > _VERDICT_RANK.get(best, 0):
            best = verdict
    return False, best.value if best else NO_ARTIFACT


def _log_legacy_acceptance(path: Path, action: str, *, root: Path | None) -> None:
    """Compat-mode acceptance of an expiry-less artifact must be AUDITABLE (K7).

    Silent acceptance is the pre-fix behaviour; the one release of warning only buys the
    consumer anything if the acceptance leaves a trace they can grep before the flip.
    Import is local so approval evaluation never hard-depends on the logger.
    """
    try:
        from .audit_logger import emit
        emit(
            "approval_legacy_accepted",
            decision="allow",
            reason=(
                f"K7 compat: {path.name} has no parseable expires_at and was accepted. "
                f"Strict mode (strict_approvals: true) will REJECT it — reissue with "
                f"`bash hooks/local/approve-local.sh {action} <slug>`."
            ),
            rule_id="FR-12",
            extra={"artifact": path.name, "action": action,
                   "approval_verdict": Verdict.MISSING_EXPIRY.value},
            root=root,
        )
    except BaseException:                            # noqa: BLE001 — logging never gates
        pass


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


def _evaluate_deny(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("deny", []) or []:
        matched, err = rule_matches(rule, command, "deny")
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


_STAGES = ("deny", "require_approval", "allow")


def _validate_policy(policy: dict[str, Any]) -> str | None:
    """Whole-policy shape check run BEFORE any command is evaluated (decision K4).

    TRIPWIRE: both defects here fail OPEN, so they must be caught at load time, not at
    use time. A non-mapping `only_when` raised AttributeError out of evaluate(); a
    `match_order` omitting `require_approval` silently skipped the approval stage and
    every gated command reached `default: allow`.
    """
    order = policy.get("match_order")
    if order is not None:
        if not isinstance(order, list) or not all(isinstance(s, str) for s in order):
            return "`match_order` must be a list of stage names."
        unknown = [s for s in order if s not in _STAGES]
        if unknown:
            return f"`match_order` names unknown stage(s) {unknown} (known: {list(_STAGES)})."
        if len(set(order)) != len(order):
            return f"`match_order` repeats a stage: {order}."
        missing = [s for s in _STAGES if policy.get(s) and s not in order]
        if missing:
            return (f"`match_order` omits stage(s) {missing} for which rules ARE declared — "
                    f"those rules would never run.")
    for stage in _STAGES:
        for rule in policy.get(stage) or []:
            if not isinstance(rule, dict):
                continue                      # rule_matches reports this per-rule
            only_when = rule.get("only_when")
            if only_when is not None and not isinstance(only_when, dict):
                return (f"{stage} rule {rule.get('rule_id', '?')!r} has a non-mapping "
                        f"`only_when` ({type(only_when).__name__}).")
    return None


def _unique(names: list[str]) -> list[str]:
    """Order-preserving de-duplication of display names."""
    return list(dict.fromkeys(names))


def _evaluate_require_approval(
    command: str,
    policy: dict[str, Any],
    approval_policy: dict[str, Any],
    *,
    root: Path | None = None,
) -> CommandDecision | None:
    workflow_mode = approval_policy.get("workflow_mode", "direct_to_main")
    on_missing = approval_policy.get("on_missing_artifact", "deny")
    strict = approval_policy.get("strict_approvals") is True      # K7; default compat

    # ALL-MATCH (decision K8): every matching rule contributes its action to the required
    # set. First-match-wins let `fusebase deploy && npx prisma migrate deploy` be authorized
    # by the deploy artifact alone, leaving the migration ungated. Stage order is unchanged —
    # `deny` short-circuits, so a denied command never reaches this stage (K16).
    # TRIPWIRE (decision K18a): requirements are PER-RULE. Never skip a matched rule
    # because its display action was already recorded — the `fusebase deploy` any_of rule
    # (display production_deploy) then absorbed the separate `git push origin main` rule,
    # and a lightweight_deploy artifact alone allowed `fusebase deploy && git push origin
    # main`. Deduplicate only AFTER satisfaction is known, and only for identical
    # (accept-set, satisfied) outcomes, which are genuinely the same requirement.
    matched_rule: dict[str, Any] | None = None
    unsatisfied: list[str] = []
    satisfied: list[str] = []
    verdicts: dict[str, str] = {}
    seen_outcomes: set[tuple[tuple[str, ...], bool]] = set()

    for rule in policy.get("require_approval", []) or []:
        if isinstance(rule, dict):
            only_when = rule.get("only_when") or {}
            if only_when.get("workflow_mode") and only_when["workflow_mode"] != workflow_mode:
                continue
        matched, err = rule_matches(rule, command, "require_approval")
        if err:
            return _policy_error(command, err)
        if not matched:
            continue
        if matched_rule is None:
            matched_rule = rule
        actions, err = rule_actions(rule, "require_approval")
        if err:
            return _policy_error(command, err)
        display = actions[0]
        # `any_of` (decision K5): ANY listed action satisfies the rule — that is how a
        # documented FR-21 Lightweight deploy passes the same gate as a Full deploy. The
        # trust boundary is process-authoritative: the hook cannot verify LL-eligibility.
        chosen, chosen_verdict, present = display, NO_ARTIFACT, False
        for candidate in actions:
            ok, verdict = _approval_state(candidate, root=root, command=command,
                                          strict=strict)
            if ok:
                chosen, chosen_verdict, present = candidate, verdict, True
                break
            if candidate == display:
                chosen_verdict = verdict
        outcome = (tuple(actions), present)
        if outcome in seen_outcomes:
            continue
        seen_outcomes.add(outcome)
        if present:
            satisfied.append(display)
            verdicts.setdefault(display, chosen_verdict)
            if chosen != display:
                verdicts.setdefault(chosen, chosen_verdict)
        else:
            unsatisfied.append(display)
            verdicts[display] = chosen_verdict     # a failure always wins the report slot

    if matched_rule is None:
        return None

    # Display-name folding is for RENDERING only and happens after every rule has been
    # evaluated on its own (K18a). An action still unsatisfied by any rule stays
    # unsatisfied even if another rule with a wider accept-set was satisfied by it.
    unsatisfied = _unique(unsatisfied)
    satisfied = [a for a in _unique(satisfied) if a not in unsatisfied]

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
            all_required_actions=list(satisfied),
        )

    lead = unsatisfied[0]
    all_required = _unique(satisfied + unsatisfied)
    return CommandDecision(
        command=command,
        decision="deny" if on_missing == "deny" else "ask",
        reason=render_approval_denial(command, all_required, verdicts,
                                      unsatisfied_actions=unsatisfied),
        rule_id=matched_rule.get("rule_id", "FR-12"),
        matched_pattern=matched_rule["pattern"],
        approval_action=lead,
        approval_artifact_present=False,
        approval_verdict=verdicts[lead],
        required_actions=list(unsatisfied),
        action_verdicts=verdicts,
        all_required_actions=all_required,
    )


def _evaluate_allow(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("allow", []) or []:
        matched, err = rule_matches(rule, command, "allow")
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
    if not any(policy.get(stage) for stage in _STAGES):
        return _policy_error(command, "command-policy declares no deny/require_approval/allow rules.")
    shape_error = _validate_policy(policy)
    if shape_error:
        return _policy_error(command, shape_error)
    order = policy.get("match_order", list(_STAGES))
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
