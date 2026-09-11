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
    BINDING_PROFILES,
    NON_COMMAND_ACTIONS,
    NOT_OBSERVED,
    PROFILE_COMMAND_ONLY,
    PROFILE_GIT_PUSH,
    Verdict,
    compute_command_digest,
    compute_repo_id,
    evaluate_command_approval,
    load,
    valid_destination_ref,
)
from .command_rules import rule_actions, rule_matches
from .denial_message import render_approval_denial, render_push_boundary_denial
from .git_push_binding import boundary_updates, resolve_command_updates
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


# TRIPWIRE (E6): the SINGLE list of host tool names that carry a shell command. Every
# FR-06 deny and FR-12 require_approval below is reachable only for a tool named here — a
# host tool left out runs commands ungated (Claude Code exposes `PowerShell` beside `Bash`
# on Windows; that omission bypassed the whole command gate). Both hook entry points
# (pre_tool_use, permission_request) MUST read this set, never a local copy: the two
# handlers previously carried different, silently narrower sets. Membership is compared
# case-insensitively. Widen freely — a name no host emits never matches, while a missing
# name is a hole; only remove one when the host tool is proven gone.
COMMAND_TOOL_NAMES = frozenset({
    "Bash",            # Claude Code / Codex / most hosts (observed on this host)
    "PowerShell",      # Claude Code on Windows (observed on this host) — the E6 bypass
    "pwsh",            # PowerShell Core binary name, should a host use it
    "Shell",
    "Terminal",
    "ExecuteCommand",
})

# TRIPWIRE: COMMAND_TOOL_NAMES keeps each host's CANONICAL SPELLING because downstream
# consumers assert set membership against it directly (the E6 filing froze a
# `VETO_ONLY_TOOLS & BASH_LIKE_TOOLS == set()` arm designed to flip when we widen).
# Lower-casing the public set would silently defeat those arms. Matching normalizes here.
_COMMAND_TOOL_NAMES_LOWER = frozenset(n.lower() for n in COMMAND_TOOL_NAMES)


def is_command_tool(tool_name: str | None) -> bool:
    """True iff `tool_name` is a host tool that executes a shell command (E6).

    Case-insensitive: pre_tool_use matched exact-case and permission_request lower-cased,
    so the two gates disagreed on `powershell` vs `PowerShell`. One rule now, the wider one.
    """
    return bool(tool_name) and tool_name.strip().lower() in _COMMAND_TOOL_NAMES_LOWER


# Reporting priority when several artifacts for one action all fail: name the most
# specific failure, so the operator can tell a stale approval from an absent one (AC14).
_VERDICT_RANK = {
    Verdict.UPDATE_MISMATCH: 8,
    Verdict.PROFILE_MISMATCH: 7,
    Verdict.BINDING_MISMATCH: 6,
    Verdict.ACTION_MISMATCH: 5,
    Verdict.EXPIRED: 4,
    Verdict.LEGACY_SCHEMA: 3,
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
    profile: str = PROFILE_COMMAND_ONLY,
    updates=NOT_OBSERVED,
    updates_mode: str = "exact",
) -> tuple[bool, str]:
    """(acceptable-artifact-present, worst-failing-verdict) for one action name.

    TRIPWIRE: command approvals are schema 3 with EVERY binding mandatory, and VALID is the
    only acceptable verdict — `strict_approvals` is deliberately not consulted here. The
    pre-cutover path accepted digest-less artifacts even in strict mode, so one unexpired
    production_deploy file authorized any matching command (docs/backlog/approval-binding-omits-head/).
    `command=None` is the pre-push boundary, which binds ref updates, never command text.
    """
    resolved = resolve_root(root)
    if resolved is None:
        return False, NO_ARTIFACT
    approvals_dir = resolved / "state" / "approvals"
    if not approvals_dir.exists():
        return False, NO_ARTIFACT
    digest = compute_command_digest(command) if command is not None else NOT_OBSERVED
    repo_id = compute_repo_id(resolved)
    best: Verdict | None = None
    for f in sorted(approvals_dir.glob(f"{action}-*.json")):
        art = load(f)
        verdict = evaluate_command_approval(
            art.data if art else None, expected_action=action, required_profile=profile,
            command_digest=digest, repo_id=repo_id, updates=updates, updates_mode=updates_mode)
        if verdict is Verdict.VALID:
            return True, verdict.value
        if best is None or _VERDICT_RANK.get(verdict, 0) > _VERDICT_RANK.get(best, 0):
            best = verdict
    return False, best.value if best else NO_ARTIFACT


def rule_profile(rule: dict[str, Any]) -> tuple[str, list[str], str | None]:
    """(binding profile, push destinations, policy-error) a require_approval rule selects.

    The POLICY selects the profile; an artifact cannot choose a weaker one. Absent means
    command_only_v1 — mandatory command + repository binding, and no claim about content.
    """
    profile = rule.get("binding_profile", PROFILE_COMMAND_ONLY)
    if profile not in BINDING_PROFILES:
        return "", [], (f"require_approval rule {rule.get('rule_id', '?')!r} has unknown "
                        f"binding_profile {profile!r} (known: {list(BINDING_PROFILES)}).")
    dests = rule.get("push_destinations")
    if profile != PROFILE_GIT_PUSH:
        if dests is not None:
            return "", [], (f"require_approval rule {rule.get('rule_id', '?')!r} sets "
                            f"push_destinations without binding_profile {PROFILE_GIT_PUSH}.")
        return profile, [], None
    if not isinstance(dests, list) or not dests or not all(valid_destination_ref(d) for d in dests):
        return "", [], (f"require_approval rule {rule.get('rule_id', '?')!r} uses "
                        f"{PROFILE_GIT_PUSH} and needs `push_destinations`: a non-empty list "
                        f"of full ref names (refs/heads/<branch>).")
    return profile, list(dests), None


def command_gated_actions(root: Path | None = None) -> set[str]:
    """Every action any require_approval rule names, in any mode: the schema-3 population.

    Raises when command-policy cannot be loaded or is missing/empty — the gate denies
    everything then (K4), so a report must not judge artifacts as if nothing were gated.
    """
    policy = get_policy("command-policy", root=resolve_root(root))
    if not isinstance(policy, dict) or not policy:
        raise ValueError("command-policy is missing or empty")
    out: set[str] = set()
    for rule in (policy.get("require_approval") if isinstance(policy, dict) else None) or []:
        if isinstance(rule, dict):
            out.update(rule_actions(rule, "require_approval")[0] or [])
    return out


def _rule_active(rule: Any, workflow_mode: str) -> bool:
    only_when = (rule.get("only_when") or {}) if isinstance(rule, dict) else {}
    return not (only_when.get("workflow_mode") and only_when["workflow_mode"] != workflow_mode)


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


#: S4a. Rendered verbatim from facts the deny decision ALREADY retains — no re-match, no
#: tokenizing, no quote parsing, no payload extraction, no span inference.
#:
#: TRIPWIRE: it claims NO location, deliberately. Pointing at the offending span requires the
#: shell-aware parsing decisions K21 and M8 reserve (see policies/command-policy.yml § MATCHING
#: IS REGEX OVER THE RAW COMMAND STRING and docs/backlog/command-gate-shell-evasion/). A wrong
#: location attached to a correct denial is worse than no explanation — never add one here.
_DENY_EXPLANATION = (
    "Denied: raw command matched rule {rule_id}, pattern {pattern}. "
    "Quoted prose can match this pattern; no match location is claimed."
)


def explain_rule_denial(rule_id: str, matched_pattern: str) -> str:
    """Why a deny-rule fired: which rule, which pattern, and that prose can trip it."""
    return _DENY_EXPLANATION.format(rule_id=rule_id, pattern=matched_pattern)


def _evaluate_deny(command: str, policy: dict[str, Any]) -> CommandDecision | None:
    for rule in policy.get("deny", []) or []:
        matched, err = rule_matches(rule, command, "deny")
        if err:
            return _policy_error(command, err)
        if matched:
            rule_id = rule.get("rule_id", "FR-06")
            pattern = rule["pattern"]
            return CommandDecision(
                command=command,
                decision="deny",
                reason=(f"{rule.get('reason', 'denied by command-policy')}\n"
                        f"{explain_rule_denial(rule_id, pattern)}"),
                rule_id=rule_id,
                matched_pattern=pattern,
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
            if stage == "require_approval":
                err = rule_profile(rule)[2]
                if err:
                    return err
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
    push: tuple | None = None          # resolved once, only if a git_push_v1 rule matches
    details: dict[str, str] = {}

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
        if not _rule_active(rule, workflow_mode):
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
        profile = rule_profile(rule)[0]
        display = actions[0]
        # `any_of` (decision K5): ANY listed action satisfies the rule — that is how a
        # documented FR-21 Lightweight deploy passes the same gate as a Full deploy. The
        # trust boundary is process-authoritative: the hook cannot verify LL-eligibility.
        chosen, chosen_verdict, present = display, NO_ARTIFACT, False
        updates = NOT_OBSERVED
        if profile == PROFILE_GIT_PUSH:
            push = push or resolve_command_updates(command, root)
            updates = push[0]
            if updates is None:
                chosen_verdict = Verdict.BINDING_UNRESOLVED.value
                details[display] = push[1]
        for candidate in (actions if updates is not None else []):
            ok, verdict = _approval_state(candidate, root=root, command=command,
                                          profile=profile, updates=updates)
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
                                      unsatisfied_actions=unsatisfied, details=details),
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


def _load_policies(command: str, resolved: Path | None):
    """(command-policy, approval-policy, None) or (None, None, policy-error decision)."""
    # FAIL-CLOSED at the policy load-point (K4): a missing, empty, unreadable or
    # non-mapping command-policy previously yielded {} and fell straight through to
    # `default: allow` — every gated command silently ungated. Deny instead.
    try:
        policy = get_policy("command-policy", root=resolved)
        approval_policy = get_policy("approval-policy", root=resolved)
    except BaseException as e:                       # noqa: BLE001 — load errors must deny
        return None, None, _policy_error(command, f"policy load failed ({e!r}).")
    if not isinstance(policy, dict) or not policy:
        return None, None, _policy_error(command, "command-policy is missing or empty.")
    if not isinstance(approval_policy, dict):
        return None, None, _policy_error(command, "approval-policy is not a mapping.")
    if not any(policy.get(stage) for stage in _STAGES):
        return None, None, _policy_error(
            command, "command-policy declares no deny/require_approval/allow rules.")
    shape_error = _validate_policy(policy)
    if shape_error:
        return None, None, _policy_error(command, shape_error)
    return policy, approval_policy, None


def evaluate_push_boundary(remote_url: str, update_lines: list[str], *,
                           root: Path | None = None) -> CommandDecision:
    """The pre-push execution boundary for every active git_push_v1 rule.

    A push is gated when any update it performs targets one of a rule's
    `push_destinations`; then EVERY update git hands the hook for this endpoint must be
    bound by one unexpired schema-3 git_push_v1 artifact of a rule action (no unbound
    extra ref). The command text is not observable here; the command gate binds it.
    """
    label = f"git push -> {remote_url}"
    resolved = resolve_root(root)
    policy, approval_policy, error = _load_policies(label, resolved)
    if error:
        return error
    mode = approval_policy.get("workflow_mode", "direct_to_main")
    observed, why = boundary_updates(remote_url, update_lines)
    # Same framing rule as boundary_updates: exactly one space between fields, nothing
    # trimmed. A trimmed ref name is a different destination than the one git is updating.
    rows = [line.split(" ") for line in update_lines if line]
    readable = all(len(r) == 4 for r in rows)      # else the destinations themselves are unknown
    dests_seen = {r[2] for r in rows if len(r) == 4}
    unsatisfied: list[str] = []
    verdicts: dict[str, str] = {}
    matched_rule: dict[str, Any] | None = None
    for rule in policy.get("require_approval", []) or []:
        if not isinstance(rule, dict) or not _rule_active(rule, mode):
            continue
        profile, dests, _err = rule_profile(rule)
        if profile != PROFILE_GIT_PUSH or (readable and not dests_seen & set(dests)):
            continue
        matched_rule = matched_rule or rule
        actions, err = rule_actions(rule, "require_approval")
        if err:
            return _policy_error(label, err)
        ok, verdict = False, Verdict.BINDING_UNRESOLVED.value
        for candidate in (actions if observed is not None else []):
            ok, verdict = _approval_state(candidate, root=resolved, command=None,
                                          profile=PROFILE_GIT_PUSH, updates=observed,
                                          updates_mode="subset")
            if ok:
                break
        if ok:
            continue
        unsatisfied.append(actions[0])
        verdicts.setdefault(actions[0], verdict)
    if matched_rule is None:
        return CommandDecision(command=label, decision="allow",
                               reason="pre-push: no update targets a gated destination.")
    if not unsatisfied:
        return CommandDecision(command=label, decision="allow",
                               reason="pre-push: every update is bound by an approval.",
                               rule_id=matched_rule.get("rule_id", "FR-12"),
                               approval_artifact_present=True)
    lead = unsatisfied[0]
    return CommandDecision(
        command=label, decision="deny",
        reason=render_push_boundary_denial(remote_url, observed or (), unsatisfied,
                                           verdicts, detail=why),
        rule_id=matched_rule.get("rule_id", "FR-12"),
        matched_pattern=matched_rule.get("pattern", ""),
        approval_action=lead, approval_verdict=verdicts[lead],
        required_actions=list(unsatisfied), action_verdicts=verdicts,
        all_required_actions=list(unsatisfied))


def approval_binding_for(command: str, action: str, *,
                         root: Path | None = None) -> tuple[dict[str, Any] | None, str]:
    """(binding fields, "") a NEW approval of `action` for `command` must carry, or (None, why).

    TRIPWIRE: approve-local.sh mints through this and the gate verifies through the same
    rule_profile + resolve_command_updates, so writer and verifier cannot drift. The
    profile comes from the matching rules — never from the caller.
    """
    resolved = resolve_root(root)
    policy, approval_policy, error = _load_policies(command, resolved)
    if error:
        return None, error.reason
    mode = approval_policy.get("workflow_mode", "direct_to_main")
    profiles: set[str] = set()
    for rule in policy.get("require_approval", []) or []:
        if not _rule_active(rule, mode) or not rule_matches(rule, command, "require_approval")[0]:
            continue
        if action in (rule_actions(rule, "require_approval")[0] or []):
            profiles.add(rule_profile(rule)[0])
    if not profiles:
        return None, (f"no active require_approval rule gates this command with {action!r} "
                      f"(workflow_mode {mode}); an artifact would authorize nothing.")
    profile = max(profiles, key=BINDING_PROFILES.index)   # the strongest satisfies every rule
    fields: dict[str, Any] = {"repo_id": compute_repo_id(resolved) if resolved else "",
                              "command_digest": compute_command_digest(command),
                              "binding_profile": profile}
    if not fields["repo_id"]:
        return None, "repository root unknown; repo_id cannot be bound."
    if profile == PROFILE_GIT_PUSH:
        updates, why = resolve_command_updates(command, resolved)
        if updates is None:
            return None, f"the push cannot be bound: {why}."
        fields["updates"] = updates
    return fields, ""


def evaluate(command: str, *, root: Path | None = None) -> CommandDecision:
    if not command:
        return CommandDecision(command=command, decision="allow", reason="empty command")
    resolved = resolve_root(root)
    policy, approval_policy, error = _load_policies(command, resolved)
    if error:
        return error
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


__all__ = ["COMMAND_TOOL_NAMES", "CommandDecision", "NON_COMMAND_ACTIONS", "NO_ARTIFACT",
           "approval_binding_for",
           "command_gated_actions", "evaluate", "evaluate_push_boundary", "explain_rule_denial",
           "is_command_tool", "resolve_root", "rule_profile"]
