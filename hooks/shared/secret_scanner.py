"""Fusebase Flow — secret_scanner.

Reads policies/secret-patterns.yml and scans text for matches. Always returns
pattern IDs and redacted snippets, never raw values.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from .audit_logger import redact
from .policy_loader import get_policy


@dataclass
class SecretMatch:
    pattern_id: str
    category: str
    confidence: str
    action: str           # block | warn | redact
    redacted_snippet: str
    rule_id: str = "FR-12"


def _compile_patterns(policy: dict[str, Any]) -> list[tuple[re.Pattern[str], dict[str, Any]]]:
    out: list[tuple[re.Pattern[str], dict[str, Any]]] = []
    for entry in policy.get("patterns", []) or []:
        try:
            out.append((re.compile(entry["pattern"]), entry))
        except re.error:
            continue
    return out


def scan(
    text: str,
    *,
    target_path: str | None = None,
    tool_context: str | None = None,    # "user_prompt_submit" | "pre_tool_use" | "git_pre_commit"
) -> list[SecretMatch]:
    """Scan text against the secret-patterns policy. Honors per-tool overrides."""
    if not text:
        return []
    policy = get_policy("secret-patterns")
    default_action = policy.get("default_action", "block")
    overrides = (policy.get("per_tool_overrides") or {}).get(tool_context or "", {})
    tool_action = overrides.get("action", default_action)
    # Per-pattern escalation in this tool context (e.g. cookie_session_value
    # is `warn` at pattern level but `block` when reached via pre_tool_use).
    pattern_overrides = overrides.get("pattern_overrides") or {}

    matches: list[SecretMatch] = []
    for regex, entry in _compile_patterns(policy):
        only_when = entry.get("only_when_target_path_matches")
        if only_when and target_path:
            if not re.search(only_when, target_path):
                continue
        elif only_when and not target_path:
            continue

        m = regex.search(text)
        if not m:
            continue
        # Whitelist check
        if _is_whitelisted(m.group(0), policy):
            continue
        # Precedence: pattern_overrides[id] > pattern-level action > tool action.
        action = pattern_overrides.get(entry["id"], entry.get("action", tool_action))
        matches.append(
            SecretMatch(
                pattern_id=entry["id"],
                category=entry.get("category", "unknown"),
                confidence=entry.get("confidence", "medium"),
                action=action,
                redacted_snippet=redact(m.group(0)),
            )
        )
    return matches


def _is_whitelisted(value: str, policy: dict[str, Any]) -> bool:
    for entry in policy.get("whitelist", []) or []:
        try:
            if re.search(entry.get("pattern", ""), value):
                return True
        except re.error:
            continue
    return False


def block_decision(matches: list[SecretMatch]) -> str:
    """Aggregate decision across matches. Block wins; warn second; allow last."""
    if any(m.action == "block" for m in matches):
        return "deny"
    if any(m.action == "warn" for m in matches):
        return "warn"
    return "allow"


__all__ = ["SecretMatch", "scan", "block_decision"]
