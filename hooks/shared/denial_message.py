"""Fusebase Flow — denial_message: the one renderer for FR-12 approval denials (K12).

Both hook entry points (pre_tool_use, permission_request) render through here, so the
operator sees one message shape and the specific failure reason instead of a generic
"no artifact found" whether the artifact was absent, expired, action-mismatched or
digest-mismatched.

Design target (AC14, internal developer CLI): diagnostic precision + one copy-pasteable
next command. No colour/ANSI (MSYS and Windows consoles vary), no emoji, no interactive
prompts — pre_tool_use is non-interactive by contract.
"""
from __future__ import annotations

MAX_LINES = 8
_MAX_DETAIL_ROWS = 3
_MAX_COMMAND_CHARS = 110

# TRIPWIRE: the KEYS here are the stable reason tokens asserted by smoke S1/S2/S5 and by
# the audit-log `extra.approval_verdict`. Reword the prose freely; never rename a key —
# the token, not the sentence, is the contract.
_REASON = {
    "NO_ARTIFACT": "no approval artifact in state/approvals/",
    "MISSING_EXPIRY": "artifact has no expires_at (legacy; rejected once strict_approvals is on)",
    "EXPIRED": "an artifact exists but has EXPIRED",
    "MALFORMED": "artifact is present but malformed/unreadable",
    "ACTION_MISMATCH": "artifact's filename action and its JSON body action disagree",
    "BINDING_MISMATCH": "artifact is bound to a different command or repository",
    "LEGACY_SCHEMA": "artifact predates schema 3 and no longer authorizes commands; reissue it",
    "PROFILE_MISMATCH": "artifact carries a different binding profile than this rule requires",
    "UPDATE_MISMATCH": "artifact is bound to different ref update(s) than this push performs",
    "BINDING_UNRESOLVED": "the push could not be resolved to exact ref updates, so nothing can bind it",
}


def reason_for(verdict: str) -> str:
    return _REASON.get(verdict, f"artifact unusable ({verdict})")


def _truncate(text: str, limit: int = _MAX_COMMAND_CHARS) -> str:
    """Display-only shortening. TRIPWIRE: never apply this to the resolving invocation —
    the digest is over the EXACT command (K6), so an elided command mints an artifact that
    authorizes nothing. Line 1 may be shortened; the fix line runs long instead."""
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _sq(text: str) -> str:
    """POSIX single-quote a command so the emitted invocation is copy-paste safe."""
    return "'" + (text or "").replace("'", "'\\''") + "'"


SATISFIED = "SATISFIED"


def render_approval_denial(
    command: str,
    required_actions: list[str],
    action_verdicts: dict[str, str],
    *,
    unsatisfied_actions: list[str] | None = None,
    slug: str = "<slug>",
    details: dict[str, str] | None = None,
) -> str:
    """The AC14 message: blocked -> EVERY required action + status -> reason -> fix.

    `required_actions` is the COMPLETE set every matched rule demands (K18b), each
    rendered on line 2 with its status; `unsatisfied_actions` is the subset that still
    needs an artifact and is what the resolving invocation covers. Rendering only the
    unsatisfied set is the serial-denial UX AC14 exists to prevent.

    Guaranteed <= MAX_LINES lines. Detail rows are capped and the overflow counted, but
    line 2 always names every required action.
    """
    actions = [a for a in required_actions if a] or ["<unknown action>"]
    pending = [a for a in (unsatisfied_actions if unsatisfied_actions is not None else actions)
               if a] or actions

    def status(action: str) -> str:
        return action_verdicts.get(action, "NO_ARTIFACT") if action in pending else SATISFIED

    lines = [
        f"BLOCKED (FR-12): {_truncate(command)}",
        "Requires approval: " + ", ".join(f"{a} [{status(a)}]" for a in actions),
    ]
    why = next(((a, d) for a, d in (details or {}).items() if d and a in pending), None)
    shown = _MAX_DETAIL_ROWS - (1 if why else 0)      # the why line spends one row's budget
    for action in pending[:shown]:
        verdict = status(action)
        lines.append(f"  {action}: {verdict} - {reason_for(verdict)}")
    if why:
        lines.append(f"  why ({why[0]}): {_truncate(why[1], 140)}")
    hidden = len(pending) - shown
    if hidden > 0:
        lines.append(f"  (+{hidden} more action(s); see policies/command-policy.yml)")
    lines.append("Fix - run the push as one plain `git push <remote> <refspec>...`, then on your "
                 "go-ahead the agent runs:" if why else
                 "Fix - on your chat go-ahead the agent runs this; you type no command:")
    # K19: the copy-paste path must mint a COMMAND-BOUND artifact, so the exact blocked
    # command travels with the invocation, unelided. EXCEPT when the binding could not be
    # resolved: minting for that same text would be refused by the writer for the same
    # reason, so name the shape that can be approved instead of a command that cannot.
    quoted = "'<the plain git push command you will run>'" if why else _sq(command)
    lines.append(
        "  " + " && ".join(
            f"bash hooks/local/approve-local.sh {a} {slug} --command {quoted}" for a in pending
        )
    )
    return "\n".join(lines[:MAX_LINES])


def render_push_boundary_denial(
    endpoint: str,
    updates: tuple,
    unsatisfied_actions: list[str],
    action_verdicts: dict[str, str],
    *,
    detail: str = "",
    slug: str = "<slug>",
) -> str:
    """The pre-push form of the AC14 message. <= MAX_LINES; plain text; no command known.

    git hands the hook ref updates, not the command line, so the fix names the invocation
    shape instead of echoing a command.
    """
    lines = [f"BLOCKED (FR-12 pre-push): push to {_truncate(endpoint, 90)}",
             "Requires approval: " + ", ".join(
                 f"{a} [{action_verdicts.get(a, 'NO_ARTIFACT')}]" for a in unsatisfied_actions)]
    lead = action_verdicts.get(unsatisfied_actions[0], "NO_ARTIFACT")
    lines.append(f"  {unsatisfied_actions[0]}: {lead} - {reason_for(lead)}")
    for u in list(updates)[:2]:
        lines.append(f"  update {u[1]} <- {u[2] or '(delete)'}")
    if len(updates) > 2:
        lines.append(f"  (+{len(updates) - 2} more update(s) in this push)")
    elif detail:
        lines.append(f"  why: {_truncate(detail, 140)}")
    lines.append("Fix - on your chat go-ahead the agent mints an approval bound to this exact push:")
    lines.append(f"  bash hooks/local/approve-local.sh {unsatisfied_actions[0]} {slug} "
                 "--command '<the git push command, byte for byte>'")
    return "\n".join(lines[:MAX_LINES])


__all__ = ["MAX_LINES", "SATISFIED", "reason_for", "render_approval_denial",
           "render_push_boundary_denial"]
