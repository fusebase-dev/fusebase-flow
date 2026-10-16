#!/usr/bin/env python3
"""Fusebase Flow — approval inventory (AC12): what is on disk, and what authorizes.

Backs `bash hooks/local/approve-local.sh --inventory`. Two contracts, judged the way their
gates judge them: COMMAND approvals (every action a command-policy rule gates) under schema 3
— VALID-only in every mode, so a pre-cutover file is named with the reason it no longer
authorizes — and protected-path/deferral artifacts under the strict K7 verdict.

Reads through hooks/shared/approval_artifact.py, never a second parser: an inventory that
disagreed with the gate would be worse than none. READ-ONLY: it never edits, moves or
deletes an artifact (files are preserved for audit; nothing is reconstructed).
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parents[2]      # <root>/hooks
sys.path.insert(0, str(_HERE))

from shared.approval_artifact import (  # noqa: E402
    NON_COMMAND_ACTIONS, NOT_OBSERVED, PROFILE_GIT_PUSH, Verdict, binding_state, command_contract_problems,
    compute_repo_id, evaluate_artifact, evaluate_command_approval, expiry_state,
    filename_action, load, now_utc, parse_expiry,
)

UNCHECKED = "UNCHECKED (command-bound)"

_COLUMNS = ("file", "action", "schema", "expiry-state", "age", "binding-state", "verdict(strict)")
# Index, never a literal: the reject/unchecked tallies below read the verdict column, and a
# later column insertion must not silently start counting a different column.
_VERDICT_COL = _COLUMNS.index("verdict(strict)")


def _age(data: object) -> str:
    """Age from `created_at` (M9), or "unknown" for an artifact written before that field.

    parse_expiry is the repo's ONE ISO-8601 parser (K1) — reused here so age and expiry are
    never read under different rules. Age is REPORTING only; it rejects nothing.
    """
    created = parse_expiry(data.get("created_at")) if isinstance(data, dict) else None
    return "unknown" if created is None else f"{(now_utc() - created).days}d"


def _git(root: Path, *args: str) -> str:
    try:
        out = subprocess.run(["git", *args], capture_output=True, text=True, check=True,
                             cwd=str(root), timeout=30)
        return out.stdout.strip()
    except Exception:
        return ""


def _git_root() -> Path:
    found = _git(Path.cwd(), "rev-parse", "--show-toplevel")
    return Path(found).resolve() if found else Path.cwd().resolve()


def _policy_facts(root: Path) -> tuple[set[str] | None, list[str], str]:
    """(command-gated actions, active git_push_v1 destinations, error) from the merged policy."""
    try:
        from shared.command_policy import command_gated_actions, rule_profile
        from shared.policy_loader import get_policy
        gated = command_gated_actions(root)
        cmd = get_policy("command-policy", root=root)
        mode = get_policy("approval-policy", root=root).get("workflow_mode", "direct_to_main")
    except BaseException as e:                        # noqa: BLE001 — report, never raise
        return None, [], f"policy did not load ({e!r})"
    dests: list[str] = []
    for rule in (cmd.get("require_approval") if isinstance(cmd, dict) else None) or []:
        if not isinstance(rule, dict):
            continue
        profile, rule_dests, _err = rule_profile(rule)
        only = (rule.get("only_when") or {}).get("workflow_mode")
        if profile == PROFILE_GIT_PUSH and (not only or only == mode):
            dests += [d for d in rule_dests if d not in dests]
    return gated, dests, ""


def _command_row(data: object, action: str, root: Path) -> tuple[str, str]:
    """(verdict column, why) under the schema-3 command contract."""
    verdict = evaluate_command_approval(
        data, expected_action=action, required_profile=NOT_OBSERVED,
        command_digest=NOT_OBSERVED, repo_id=compute_repo_id(root), updates=NOT_OBSERVED)
    if verdict is Verdict.VALID:
        return UNCHECKED, ""
    _structural, why = command_contract_problems(data)
    if verdict is Verdict.EXPIRED:
        why = [f"expired at {data.get('expires_at')}"]          # type: ignore[union-attr]
    elif verdict is Verdict.BINDING_MISMATCH:
        why = ["bound to a different repository (repo_id)"]
    elif verdict is Verdict.ACTION_MISMATCH:
        why = ["body action differs from the filename action"]
    return f"REJECT ({verdict.value})", "; ".join(why)


def _row(path: Path, root: Path, command_actions: set[str] | None) -> tuple[tuple[str, ...], str, bool]:
    """(row, why-it-does-not-authorize, is-command-approval).

    TRIPWIRE (K17 / AC27): the verdict column must never claim ACCEPT for something the gate
    rejects. For command approvals the digest and ref updates are judged only against the
    command being run, so a structurally sound one reports UNCHECKED — never ACCEPT.
    """
    action = filename_action(path)
    art = load(path)
    data = art.data if art else None
    if command_actions is None:                 # command-policy unreadable: the gate denies
        is_command = action not in NON_COMMAND_ACTIONS
    else:
        is_command = action in command_actions
    if is_command and command_actions is None:
        column, why = "REJECT (policy did not load)", "command-policy could not be read"
    elif is_command:
        column, why = _command_row(data, action, root)
    else:
        verdict = evaluate_artifact(data, expected_action=action, repo_id=compute_repo_id(root))
        column = "ACCEPT" if verdict is Verdict.VALID else f"REJECT ({verdict.value})"
        why = ""
    schema = (data or {}).get("schema_version")
    binding = binding_state(data)
    if is_command and isinstance(data, dict) and isinstance(data.get("binding_profile"), str):
        binding = f"{binding}+{data['binding_profile']}"
    row = (path.name, action or "-", f"v{schema}" if isinstance(schema, int) else "legacy",
           expiry_state(data), _age(data), binding, column)
    return row, why, is_command


def _pre_push_state(root: Path) -> str:
    target = _git(root, "rev-parse", "--git-path", "hooks/pre-push")
    if not target:
        return "unknown (git unavailable)"
    hook = Path(target) if Path(target).is_absolute() else root / target
    source = root / "hooks" / "git" / "pre-push"
    if not hook.is_file():
        return "absent - the boundary is NOT active; run bash hooks/local/install-git-hooks.sh"
    if source.is_file() and hook.read_bytes() == source.read_bytes():
        return "installed and current"
    if b"fusebase-flow-managed-hook:" in hook.read_bytes()[:400]:
        return "stale Flow copy - run bash hooks/local/install-git-hooks.sh"
    return "custom hook - the Flow boundary is NOT active (install-git-hooks.sh --force replaces it)"


def inventory(root: Path) -> int:
    command_actions, push_dests, policy_error = _policy_facts(root)
    if policy_error:
        print(f"[approve-local] inventory: {policy_error}; command approvals cannot be judged.")
    approvals = root / "state" / "approvals"
    files = sorted(p for p in approvals.glob("*.json")) if approvals.is_dir() else []
    if push_dests:
        print(f"[approve-local] git_push_v1 binding: pushes updating {', '.join(push_dests)} "
              f"need a ref-update-bound approval; pre-push boundary: {_pre_push_state(root)}")
    elif command_actions is not None:
        print("[approve-local] git_push_v1 binding: NO active rule - pushes are bound by "
              "command text only (check policies/command-policy*.yml)")
    if not files:
        print(f"[approve-local] inventory: no artifacts under {approvals}")
        return 0

    results = [_row(p, root, command_actions) for p in files]
    rows = [r for r, _w, _c in results]
    widths = [max(len(str(r[i])) for r in (list(rows) + [_COLUMNS])) for i in range(len(_COLUMNS))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    print(fmt.format(*_COLUMNS))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(fmt.format(*r))

    rejected = sum(1 for r in rows if r[_VERDICT_COL].startswith("REJECT"))
    unchecked = sum(1 for r in rows if r[_VERDICT_COL] == UNCHECKED)
    dead = [(r[0], r[_VERDICT_COL], w) for r, w, c in results
            if c and r[_VERDICT_COL].startswith("REJECT")]
    print()
    print(f"[approve-local] {len(rows)} artifact(s); {rejected} authorize nothing "
          f"(command approvals: schema 3 in every mode; others: strict_approvals: true).")
    if unchecked:
        print(f"[approve-local] {unchecked} command approval(s) are structurally sound; their "
              "command digest (and ref updates) can only be judged against the command run.")
    if dead:
        print(f"[approve-local] {len(dead)} command approval artifact(s) no longer authorize "
              "any command:")
        for name, column, why in dead:
            print(f"  {name}: {column[len('REJECT ('):-1]} - {why}")
        print("[approve-local] Files are preserved and were not modified; no approval is "
              "reconstructed from them. Reissue only for an operation still intended:")
        print("  bash hooks/local/approve-local.sh <action> <slug> '<reason>' "
              "--command '<exact command>'")
    elif rejected:
        print("[approve-local] Reissue each with: "
              "bash hooks/local/approve-local.sh <action> <slug> '<reason>' "
              "--command '<exact command>'")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="approval_inventory.py")
    parser.add_argument("--root", default=None)
    args = parser.parse_args(argv)
    return inventory(Path(args.root).resolve() if args.root else _git_root())


if __name__ == "__main__":
    raise SystemExit(main())
