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
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def render_approval_denial(
    command: str,
    required_actions: list[str],
    action_verdicts: dict[str, str],
    *,
    slug: str = "<slug>",
) -> str:
    """The AC14 message: blocked -> every required action -> per-artifact reason -> fix.

    Guaranteed <= MAX_LINES lines. Per-action detail rows are capped and the overflow is
    counted, but line 2 always names EVERY required action (K8's single-round-trip rule).
    """
    actions = [a for a in required_actions if a] or ["<unknown action>"]
    lines = [
        f"BLOCKED (FR-12): {_truncate(command)}",
        f"Requires approval: {', '.join(actions)}",
    ]
    for action in actions[:_MAX_DETAIL_ROWS]:
        verdict = action_verdicts.get(action, "NO_ARTIFACT")
        lines.append(f"  {action}: {verdict} - {reason_for(verdict)}")
    hidden = len(actions) - _MAX_DETAIL_ROWS
    if hidden > 0:
        lines.append(f"  (+{hidden} more action(s); see policies/command-policy.yml)")
    lines.append("Fix - on your chat go-ahead the agent runs this; you type no command:")
    lines.append(
        "  " + " && ".join(f"bash hooks/local/approve-local.sh {a} {slug}" for a in actions)
    )
    return "\n".join(lines[:MAX_LINES])


__all__ = ["MAX_LINES", "reason_for", "render_approval_denial"]
