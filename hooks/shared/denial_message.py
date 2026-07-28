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
    for action in pending[:_MAX_DETAIL_ROWS]:
        verdict = status(action)
        lines.append(f"  {action}: {verdict} - {reason_for(verdict)}")
    hidden = len(pending) - _MAX_DETAIL_ROWS
    if hidden > 0:
        lines.append(f"  (+{hidden} more action(s); see policies/command-policy.yml)")
    lines.append("Fix - on your chat go-ahead the agent runs this; you type no command:")
    # K19: the copy-paste path must mint a COMMAND-BOUND artifact, so the exact blocked
    # command travels with the invocation, unelided.
    quoted = _sq(command)
    lines.append(
        "  " + " && ".join(
            f"bash hooks/local/approve-local.sh {a} {slug} --command {quoted}" for a in pending
        )
    )
    return "\n".join(lines[:MAX_LINES])


__all__ = ["MAX_LINES", "SATISFIED", "reason_for", "render_approval_denial"]
