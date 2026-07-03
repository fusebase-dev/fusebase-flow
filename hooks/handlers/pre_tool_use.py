#!/usr/bin/env python3
"""Fusebase Flow — pre_tool_use handler.

Blocks unsafe tool actions before execution. Three checks:
1. Command policy (Bash-style tools): match command against deny / require_approval rules.
2. Path policy (Edit/Write/MultiEdit-style tools): block edits to protected paths
   without an active exception artifact.
3. Secret policy (Edit/Write tools writing .env-like files): block content with
   high-confidence secret matches.

Output: Claude Code-compatible hookSpecificOutput.permissionDecision shape AND
exit code 2 on deny so hosts that read exit codes are also covered.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.command_policy import evaluate as evaluate_command  # noqa: E402
from shared.path_policy import (  # noqa: E402
    assert_protected_policy_loaded,
    evaluate as evaluate_path,
)
from shared.policy_loader import find_git_root  # noqa: E402
from shared.secret_scanner import scan, block_decision  # noqa: E402


BASH_LIKE_TOOLS = {"Bash", "Shell", "Terminal", "ExecuteCommand"}
EDIT_LIKE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "ApplyDiff", "create_file"}


def _command_path(event: dict) -> tuple[str | None, str | None]:
    """Return (command, target_path) extracted from event['tool_input']."""
    inp = event.get("tool_input") or {}
    if event.get("tool_name") in BASH_LIKE_TOOLS:
        return inp.get("command") or "", None
    if event.get("tool_name") in EDIT_LIKE_TOOLS:
        target = inp.get("file_path") or inp.get("path") or inp.get("filePath") or ""
        content = inp.get("content") or inp.get("new_string") or ""
        return content, target
    return None, None


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        root = None

    tool_name = event.get("tool_name", "")

    # 1. Command-policy check (Bash-like)
    if tool_name in BASH_LIKE_TOOLS:
        command = (event.get("tool_input") or {}).get("command") or ""
        cd = evaluate_command(command, root=root)
        if cd.decision != "allow":
            emit(
                "pre_tool_use",
                decision=cd.decision,
                reason=cd.reason,
                rule_id=cd.rule_id,
                extra={"tool_name": tool_name, "matched_pattern": cd.matched_pattern},
                root=root,
            )
            _output_decision(cd.decision, cd.reason, cd.rule_id)
            return 2 if cd.decision == "deny" else 0

    # 2. Path-policy check (Edit-like)
    if tool_name in EDIT_LIKE_TOOLS:
        inp = event.get("tool_input") or {}
        target = inp.get("file_path") or inp.get("path") or inp.get("filePath") or ""
        if target:
            # TOOL-TIME FAIL-CLOSED (T28/#7): evaluate_path() classifies via is_protected(),
            # which reads protected-paths.yml. A MISSING/EMPTY/malformed policy makes
            # is_protected() always False -> a protected-path Edit/Write would pass at
            # tool-time (the pre-commit still blocks the commit, but this load-point must be
            # fail-closed too — a security control never waves an edit through on an
            # unenforceable policy). Assert the policy is present + enforceable FIRST; on any
            # BaseException (missing/empty policy, load error) DENY the tool action. The
            # SHIPPED policy present => this is a no-op and normal edits are unaffected.
            try:
                assert_protected_policy_loaded(root)
            except BaseException as e:
                reason = (
                    "FR-07: protected-paths policy missing/empty/unenforceable; refusing "
                    f"the {tool_name} on {target} (fail closed). Fix "
                    f"policies/protected-paths.yml. ({e!r})"
                )
                emit(
                    "pre_tool_use",
                    decision="deny",
                    reason=reason,
                    rule_id="FR-07",
                    extra={"tool_name": tool_name, "path": target, "fail_closed": True},
                    root=root,
                )
                _output_decision("deny", reason, "FR-07")
                return 2
            # Make path repo-relative if it's absolute under root.
            rel = target
            if root and Path(target).is_absolute():
                try:
                    rel = str(Path(target).relative_to(root))
                except ValueError:
                    rel = target
            pd = evaluate_path(rel, root=root)
            if pd.decision != "allow":
                emit(
                    "pre_tool_use",
                    decision=pd.decision,
                    reason=pd.reason,
                    rule_id=pd.rule_id,
                    extra={"tool_name": tool_name, "path": rel, "category": pd.category},
                    root=root,
                )
                _output_decision(pd.decision, pd.reason, pd.rule_id)
                return 2 if pd.decision == "deny" else 0

        # 3. Secret content check on writes
        content = inp.get("content") or inp.get("new_string") or ""
        if content:
            matches = scan(content, target_path=target, tool_context="pre_tool_use")
            decision = block_decision(matches)
            if decision != "allow":
                ids = ",".join(m.pattern_id for m in matches)
                reason = (
                    f"FR-12: secret-shaped content detected in write to {target} "
                    f"(patterns: {ids}). Redacted in audit log; rotate the credential "
                    f"if real, or whitelist in policies/secret-patterns.yml if a fixture."
                )
                emit(
                    "pre_tool_use",
                    decision=decision,
                    reason=reason,
                    rule_id="FR-12",
                    extra={"tool_name": tool_name, "path": target, "pattern_ids": [m.pattern_id for m in matches]},
                    root=root,
                )
                _output_decision(decision, reason, "FR-12")
                return 2 if decision == "deny" else 0

    # Default: allow
    emit("pre_tool_use", decision="allow", reason="no rule matched", root=root, extra={"tool_name": tool_name})
    _output_decision("allow", "no rule matched", "")
    return 0


def _output_decision(decision: str, reason: str, rule_id: str) -> None:
    """Emit Claude-Code-compatible JSON on stdout, plus exit-code semantics."""
    out = {
        "decision": decision,
        "reason": reason,
        "rule_id": rule_id or None,
        # Claude Code current shape:
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny" if decision == "deny" else ("allow" if decision == "allow" else "ask"),
            "permissionDecisionReason": reason,
        },
    }
    sys.stdout.write(json.dumps(out))
    if decision != "allow":
        print(f"[fusebase-flow] {decision.upper()}: {reason}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
