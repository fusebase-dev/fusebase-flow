"""Fusebase Flow — command_rules: the shape of one command-policy rule.

Extracted from command_policy.py on the rule-shape responsibility seam (FR-25) when
per-rule `flags` and `any_of` landed. command_policy owns decisions; this module owns
"what is a rule, does it match, and which actions does it demand".

Rule shape (locked by decision K5's task):
    {pattern, action | any_of, flags?, reason, rule_id, only_when?}
`action` and `any_of` are mutually exclusive and exactly one is required on a
require_approval rule. `flags` accepts ["i"] only, for now.
"""
from __future__ import annotations

import re
from typing import Any

# TRIPWIRE: widening this map widens what a policy author can switch on per rule.
# Anything beyond case-insensitivity (DOTALL, VERBOSE, MULTILINE) changes how patterns
# read against a whole command line and needs its own review; unknown flags FAIL CLOSED.
_FLAG_MAP = {"i": re.IGNORECASE}


def rule_flags(rule: dict[str, Any], stage: str) -> tuple[int, str | None]:
    """(compiled re flags, policy-error detail). An unknown flag denies (K4)."""
    raw = rule.get("flags")
    if raw is None:
        return 0, None
    if isinstance(raw, str):
        raw = [raw]
    if not isinstance(raw, list):
        return 0, f"{stage} rule `flags` must be a list (got {type(raw).__name__})"
    out = 0
    for f in raw:
        if not isinstance(f, str) or f not in _FLAG_MAP:
            return 0, f"{stage} rule has unsupported flag {f!r} (supported: {sorted(_FLAG_MAP)})"
        out |= _FLAG_MAP[f]
    return out, None


def rule_actions(rule: dict[str, Any], stage: str) -> tuple[list[str], str | None]:
    """(actions this rule demands, policy-error detail).

    A single `action` yields one entry. `any_of` yields the full list, and the rule is
    satisfied when ANY of them has an acceptable artifact (decision K5). The FIRST entry
    is the rule's display name for the denial renderer and the --inventory report.
    """
    action = rule.get("action")
    any_of = rule.get("any_of")
    if action is not None and any_of is not None:
        return [], f"{stage} rule sets both `action` and `any_of` (mutually exclusive)"
    if any_of is not None:
        if not isinstance(any_of, list) or not any_of or not all(
            isinstance(a, str) and a.strip() for a in any_of
        ):
            return [], f"{stage} rule `any_of` must be a non-empty list of action names"
        return [a.strip() for a in any_of], None
    if isinstance(action, str) and action.strip():
        return [action.strip()], None
    if stage == "require_approval":
        return [], f"{stage} rule declares neither `action` nor `any_of`"
    return [], None


def rule_matches(rule: Any, command: str, stage: str) -> tuple[bool, str | None]:
    """(matched, policy-error detail). A defective rule NEVER silently skips (K4).

    TRIPWIRE: `re.error` and a malformed rule must DENY, not `continue`. The original
    code skipped both, so a typo in a deny pattern silently disabled that rule and the
    command fell through to `default: allow` — a gate whose failure mode is "allow".
    """
    if not isinstance(rule, dict):
        return False, f"{stage} rule is not a mapping"
    pattern = rule.get("pattern")
    if not isinstance(pattern, str) or not pattern:
        return False, f"{stage} rule has no usable `pattern`"
    flags, err = rule_flags(rule, stage)
    if err:
        return False, err
    try:
        return bool(re.search(pattern, command, flags)), None
    except re.error as e:
        return False, f"{stage} rule pattern {pattern!r} is not a valid regex ({e})."


__all__ = ["rule_actions", "rule_flags", "rule_matches"]
