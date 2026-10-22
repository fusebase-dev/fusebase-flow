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

import hashlib
import json
import os
import re
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

# TRIPWIRE (6.0.0-m8 fix, review B H1): an import that fails (PyYAML missing, a broken file) must still end in a printed
# decision; an uncaught error exits 1, which run-handler.sh treats as non-blocking, so the tool call would run ungated.
try:
    from shared.audit_logger import emit  # noqa: E402
    from shared.command_policy import (  # noqa: E402
        COMMAND_TOOL_NAMES,
        evaluate as evaluate_command,
        is_command_tool,
    )
    from shared.path_policy import (  # noqa: E402
        assert_protected_policy_loaded,
        evaluate as evaluate_path,
    )
    from shared.policy_loader import find_git_root, use_committed  # noqa: E402
    from shared.secret_scanner import scan, block_decision  # noqa: E402
    _IMPORT_ERROR: Exception | None = None
except Exception as _exc:  # noqa: BLE001
    _IMPORT_ERROR = _exc
    COMMAND_TOOL_NAMES = frozenset()


# TRIPWIRE (E6): re-export only. The authoritative set is shared.command_policy.
# COMMAND_TOOL_NAMES so this handler and permission_request.py can never diverge
# again; a tool absent from it runs commands ungated. Never re-inline a literal here,
# and route every membership test through is_command_tool() (case-insensitive).
BASH_LIKE_TOOLS = COMMAND_TOOL_NAMES
EDIT_LIKE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "ApplyDiff", "create_file"}


def cmd_sha256(command: str) -> str:
    # TRIPWIRE: post_tool_use.py's twin, the whitespace-collapsed form hooks/local/token_waste_audit/parsing.py hashes;
    # change one, change both, or a command's two audit lines stop matching.
    return hashlib.sha256(" ".join(command.split()).encode("utf-8")).hexdigest()


def audit_reason(cd) -> str:
    """The audit line's reason for a command decision: fixed text, never the command. The reason shown to the agent
    (render_approval_denial) carries the command twice, a token in a push URL included."""
    if cd.all_required_actions:
        return f"FR-12: approval required ({', '.join(cd.all_required_actions)})"
    return f"{cd.rule_id or 'FR-12'}: {cd.decision} by command-policy"


def _target(inp: dict) -> str:
    """The edited path as the tool sends it; NotebookEdit names it notebook_path."""
    return inp.get("file_path") or inp.get("path") or inp.get("filePath") or inp.get("notebook_path") or ""


def _content(inp: dict) -> str:
    return inp.get("content") or inp.get("new_string") or inp.get("new_source") or ""


def windows_spelling(target: str) -> str:
    """The file Windows opens for `target` (m7 review A #5): the `\\\\?\\` and `\\\\?\\UNC\\` prefixes and a
    `\\\\localhost\\C$` (or 127.0.0.1) share dropped, each name's trailing dots and spaces dropped, and an NTFS stream
    (`::$DATA`, `:name`) cut off its file's name."""
    path = target.replace("/", "\\")
    path = re.sub(r"^\\\\[?.]\\UNC\\", r"\\\\", path, flags=re.I)
    path = re.sub(r"^\\\\[?.]\\", "", path)
    path = re.sub(r"^\\\\(?:localhost|127\.0\.0\.1)\\([A-Za-z])\$(?=\\|$)", r"\1:", path, flags=re.I)
    drive, rest = (path[:2], path[2:]) if re.match(r"[A-Za-z]:", path) else ("", path)
    names = [n if n in (".", "..") else re.sub(r"[. ]+$", "", n.split(":", 1)[0]) for n in rest.split("\\")]
    return drive + "\\".join(names)


def repo_relative(target: str, root: Path | None, cwd: str | None) -> str:
    """The path as git and an approval's `paths` name it, `/` on every platform: the target (taken from the session's
    folder when relative) and the root both resolved before they are compared, so an 8.3 short name, another case,
    `..`, `./`, a junction or a symlink reaches the same repo-relative path (6.0.0-m7 item 1). A path that resolves
    outside the root is judged as given, as before."""
    if not root:
        return target
    path = Path(windows_spelling(target) if os.name == "nt" else target)
    if not path.is_absolute():
        path = Path(cwd or root) / path
    try:
        return path.resolve().relative_to(Path(root).resolve()).as_posix()
    except (ValueError, OSError, RuntimeError):
        return target


def approval_store(rel: str) -> bool:
    """The path is in state/approvals/ or a git folder's flow/ (the approval record), in any case: an agent's Edit or
    Write there made its own approval (review r2-26b, m7 review A #4)."""
    parts = [p.lower() for p in Path(rel).parts]
    return parts[:2] == ["state", "approvals"] or any(a == ".git" and b == "flow" for a, b in zip(parts, parts[1:]))


def _audit(event: str, **kwargs) -> None:
    """The audit line, never in the way of the decision: a failed write is said on stderr (the decision still prints)."""
    try:
        emit(event, **kwargs)
    except Exception as exc:  # noqa: BLE001
        print(f"[fusebase-flow] audit line not written: {exc!r}", file=sys.stderr)


def main() -> int:
    """The decision, printed on every path: an error on the way to it denies the call (exit 2), never exit 1."""
    try:
        if _IMPORT_ERROR is not None:
            raise _IMPORT_ERROR
        return _main()
    except Exception as exc:  # noqa: BLE001 — TRIPWIRE (6.0.0-m8 fix, review B H1)
        reason = (f"Fusebase Flow's tool hook failed before it could decide ({type(exc).__name__}: {exc}); the tool call "
                  "is refused (fail closed). Fix the error, then retry; run hooks/handlers/pre_tool_use.py with the "
                  "call's JSON on stdin to see it.")
        _output_decision("deny", reason, "FR-12")
        return 2


def _main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except (FileNotFoundError, OSError, ValueError):
        # TRIPWIRE (6.0.0-m8 fix): a call from outside any git work tree (`cd <your-project>` from the folder above it)
        # is judged by the rules of the project this handler belongs to; a failed lookup denied every such call.
        try:
            root = find_git_root(_HERE)
        except (FileNotFoundError, OSError, ValueError):
            root = None

    tool_name = event.get("tool_name", "")
    if root is not None:  # the shipped policies as committed, never a working-tree edit of them (m7 review B #1)
        use_committed(root)

    # 1. Command-policy check (Bash-like)
    if is_command_tool(tool_name):
        command = (event.get("tool_input") or {}).get("command") or ""
        # A PowerShell line is not bash: it is matched on its raw text, without the bash allowlist (command_rules).
        shell = "powershell" if str(tool_name).strip().lower() in ("powershell", "pwsh") else "bash"
        cd = evaluate_command(command, root=root, shell=shell)
        if cd.decision != "allow":
            _audit(
                "pre_tool_use",
                decision=cd.decision,
                # The audit line names the tool and the command's hash, never its text; cd.reason goes to the
                # agent only (_output_decision).
                reason=audit_reason(cd),
                rule_id=cd.rule_id,
                # approval_verdict / required_actions are the GROUND-TRUTH tokens smoke
                # S1/S2/S5 assert on — stdout prose may be reworded, these may not.
                extra={
                    "tool_name": tool_name,
                    "cmd_sha256": cmd_sha256(str(command)),
                    "matched_pattern": cd.matched_pattern,
                    "approval_action": cd.approval_action,
                    "approval_verdict": cd.approval_verdict,
                    "required_actions": cd.required_actions,
                    "all_required_actions": cd.all_required_actions,
                    "action_verdicts": cd.action_verdicts,
                },
                root=root,
            )
            _output_decision(cd.decision, cd.reason, cd.rule_id)
            return 2 if cd.decision == "deny" else 0

    # 2. Path-policy check (Edit-like)
    if tool_name in EDIT_LIKE_TOOLS:
        inp = event.get("tool_input") or {}
        target = _target(inp)
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
                _audit(
                    "pre_tool_use",
                    decision="deny",
                    reason=reason,
                    rule_id="FR-07",
                    extra={"tool_name": tool_name, "path": target, "fail_closed": True},
                    root=root,
                )
                _output_decision("deny", reason, "FR-07")
                return 2
            # TRIPWIRE (6.0.0-m7 item 1): never compare the raw spelling. relative_to() raised on an 8.3 short name
            # (the Windows runner's RUNNER~1), `..` or a symlink, left the path absolute, and the edit was ALLOWED.
            rel = repo_relative(target, root, event.get("cwd"))
            if approval_store(rel):
                reason = ("FR-07: state/approvals/ and .git/flow/ hold the approvals and the approval record; only Flow's "
                          "scripts write them (the two mints, range_check.py --record-commit), on the operator's go-ahead "
                          "in chat (6.0.0-m8, M6-6).")
                _audit("pre_tool_use", decision="deny", reason=reason, rule_id="FR-07",
                     extra={"tool_name": tool_name, "path": rel}, root=root)
                _output_decision("deny", reason, "FR-07")
                return 2
            pd = evaluate_path(rel, root=root)
            if pd.decision != "allow":
                _audit(
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
        content = _content(inp)
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
                _audit(
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
    extra = {"tool_name": tool_name}
    if is_command_tool(tool_name):
        extra["cmd_sha256"] = cmd_sha256(str((event.get("tool_input") or {}).get("command") or ""))
    _audit("pre_tool_use", decision="allow", reason="no rule matched", root=root, extra=extra)
    _output_decision("allow", "no rule matched", "")
    return 0


def _output_decision(decision: str, reason: str, rule_id: str) -> None:
    # TRIPWIRE (security): never emit permissionDecision "allow" — the host then skips the
    # permission prompt, so every unmatched tool call would be auto-approved. A top-level
    # `decision` other than "block" fails host validation; Flow's verdict is `flow_decision`.
    out = {"flow_decision": decision, "reason": reason, "rule_id": rule_id or None}
    line = f"[fusebase-flow] {decision.upper()}: {reason}"
    if decision in ("deny", "ask"):
        out["hookSpecificOutput"] = {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": line,
        }
    elif decision != "allow":
        out["hookSpecificOutput"] = {"hookEventName": "PreToolUse", "additionalContext": line}
        out["systemMessage"] = line
    sys.stdout.write(json.dumps(out))
    if decision != "allow":
        print(line, file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
