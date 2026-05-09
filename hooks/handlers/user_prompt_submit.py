#!/usr/bin/env python3
"""Fusebase Flow — user_prompt_submit handler.

Guards user prompts before the model acts. Detects:
- pasted secrets (from secret-patterns.yml)
- "skip the spec / just code it / force push / ignore approvals" patterns
- implementation requests without ticket/spec context

Does NOT block by default for the bypass-pattern detector — surfaces a warning
that the host should display. Blocks for high-confidence secret matches per
secret-patterns.yml per_tool_overrides.user_prompt_submit.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.policy_loader import find_git_root  # noqa: E402
from shared.secret_scanner import scan, block_decision  # noqa: E402


# Bypass-attempt patterns (case-insensitive). These indicate the operator may be
# asking the agent to short-circuit the flow; surface a warning, do not block.
BYPASS_PATTERNS = [
    (r"\b(just\s+)?code\s+it(\s+up)?\s+without(?:\s+a)?\s+spec\b", "FR-01"),
    (r"\bskip\s+(the\s+)?(spec|clarify|tests?|gate|verification|review)\b", "FR-01"),
    (r"\bforce[-\s]?push\b", "FR-06"),
    (r"\bignore\s+(approvals?|guardrails?|rails?|hooks?)\b", "FR-12"),
    (r"\bdeploy\s+(now|already|asap|right\s+away)\b", "FR-05"),
    (r"\bjust\s+ship\s+it\b", "FR-05"),
    (r"\b--no-verify\b", "FR-13"),
    (r"\bgit\s+(reset\s+--hard|push\s+--force|add\s+(\.|--all|-A))\b", "FR-06"),
]


# Implementation-without-spec heuristic: "implement / build / write code for X"
# without referencing an existing spec/ticket folder.
IMPL_REQUEST_PATTERNS = [
    r"\b(implement|build|write\s+code|create\s+endpoint|add\s+feature)\b",
    r"\bcode\s+up\b",
]
SPEC_REFERENCE_PATTERNS = [
    r"docs/specs?/",
    r"docs/backlog/",
    r"\bT\d+\b",                # T17 etc.
    r"\b(spec|ticket|backlog)\b",
]


def _detect_bypass(text: str) -> list[tuple[str, str]]:
    hits = []
    for pat, rule_id in BYPASS_PATTERNS:
        if re.search(pat, text, flags=re.IGNORECASE):
            hits.append((pat, rule_id))
    return hits


def _detect_impl_without_spec(text: str) -> bool:
    has_impl = any(re.search(p, text, flags=re.IGNORECASE) for p in IMPL_REQUEST_PATTERNS)
    if not has_impl:
        return False
    has_spec_ref = any(re.search(p, text, flags=re.IGNORECASE) for p in SPEC_REFERENCE_PATTERNS)
    return not has_spec_ref


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    user_prompt = event.get("user_prompt") or ""
    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        root = None

    # 1. Secret scan
    secret_matches = scan(user_prompt, tool_context="user_prompt_submit")
    sec_decision = block_decision(secret_matches)

    # 2. Bypass attempts
    bypass_hits = _detect_bypass(user_prompt)

    # 3. Impl request without spec
    impl_no_spec = _detect_impl_without_spec(user_prompt)

    warnings: list[str] = []
    rule_ids: list[str] = []

    if secret_matches:
        warnings.append(
            "Possible secret-shaped string detected in prompt: "
            + ", ".join(f"{m.pattern_id}({m.confidence})" for m in secret_matches)
        )
        rule_ids.append("FR-12")

    for pat, rule_id in bypass_hits:
        warnings.append(f"Prompt suggests bypassing flow ({rule_id}); pattern: {pat[:60]}")
        rule_ids.append(rule_id)

    if impl_no_spec:
        warnings.append(
            "Implementation request detected without a referenced spec/ticket. "
            "Per FR-01, drop into requirements-specification skill or cite an existing spec path."
        )
        rule_ids.append("FR-01")

    decision = "allow"
    if sec_decision == "deny":
        decision = "warn"   # for prompts, we surface but don't block; operator may need to discuss
    elif warnings:
        decision = "warn"

    emit(
        "user_prompt_submit",
        decision=decision,
        reason="; ".join(warnings) or "clean",
        rule_id=",".join(sorted(set(rule_ids))) or None,
        extra={
            "secret_match_ids": [m.pattern_id for m in secret_matches],
            "bypass_hits": [p for p, _ in bypass_hits],
            "impl_no_spec": impl_no_spec,
            "prompt_preview_chars": len(user_prompt),
        },
        root=root,
    )

    rule_id_str = ",".join(sorted(set(rule_ids))) if rule_ids else None
    out = {"decision": decision, "rule_id": rule_id_str, "warnings": warnings}
    sys.stdout.write(json.dumps(out))
    if warnings:
        for w in warnings:
            print(f"[fusebase-flow] WARN: {w}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
