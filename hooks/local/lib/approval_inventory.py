#!/usr/bin/env python3
"""Fusebase Flow — approval inventory (AC12): what is on disk, and what strict rejects.

Backs `bash hooks/local/approve-local.sh --inventory`. The point (decision K7) is that a
consumer can see, BEFORE the strict default flips, exactly which of their artifacts a
strict cutover will reject — so the flip is a scheduled reissue rather than a breakage.

Reads through hooks/shared/approval_artifact.py, never a second parser: an inventory that
disagreed with the gate would be worse than none.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parents[2]      # <root>/hooks
sys.path.insert(0, str(_HERE))

from shared.approval_artifact import (  # noqa: E402
    Verdict, binding_state, compute_repo_id, evaluate_artifact, expiry_state,
    filename_action, load,
)

UNCHECKED = "UNCHECKED (command-bound)"

_COLUMNS = ("file", "action", "schema", "expiry-state", "binding-state", "verdict(strict)")


def _git_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip()).resolve()
    except Exception:
        return Path.cwd().resolve()


def _row(path: Path, root: Path) -> tuple[str, str, str, str, str, str]:
    """One inventory row. TRIPWIRE (K17 / AC27): the verdict column must never claim
    ACCEPT for something the gate rejects. `repo_id` IS checkable here (against this
    inventory's own root) and is checked; only `command_digest` is genuinely unknowable
    without the command, and that reports UNCHECKED — never ACCEPT."""
    action = filename_action(path)
    art = load(path)
    data = art.data if art else None
    verdict = evaluate_artifact(data, expected_action=action, repo_id=compute_repo_id(root))
    command_bound = isinstance((data or {}).get("command_digest"), str) and         bool((data or {}).get("command_digest", "").strip())
    if verdict is Verdict.BINDING_MISMATCH and command_bound:
        # Re-judge with ONLY the command digest removed: if everything else (including
        # repo binding) is sound, the artifact is unverifiable here, not rejected.
        without_command = {k: v for k, v in (data or {}).items() if k != "command_digest"}
        residual = evaluate_artifact(without_command, expected_action=action,
                                     repo_id=compute_repo_id(root))
        column = (UNCHECKED if residual is Verdict.VALID
                  else f"REJECT ({residual.value})")
    elif verdict is Verdict.VALID and command_bound:
        column = UNCHECKED
    else:
        column = "ACCEPT" if verdict is Verdict.VALID else f"REJECT ({verdict.value})"
    schema = (data or {}).get("schema_version")
    return (
        path.name,
        action or "-",
        f"v{schema}" if isinstance(schema, int) else "legacy",
        expiry_state(data),
        binding_state(data),
        column,
    )


def inventory(root: Path) -> int:
    approvals = root / "state" / "approvals"
    files = sorted(p for p in approvals.glob("*.json")) if approvals.is_dir() else []
    if not files:
        print(f"[approve-local] inventory: no artifacts under {approvals}")
        return 0

    rows = [_row(p, root) for p in files]
    widths = [max(len(str(r[i])) for r in (list(rows) + [_COLUMNS])) for i in range(len(_COLUMNS))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    print(fmt.format(*_COLUMNS))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(fmt.format(*r))

    rejected = sum(1 for r in rows if r[5].startswith("REJECT"))
    unchecked = sum(1 for r in rows if r[5] == UNCHECKED)
    print()
    print(f"[approve-local] {len(rows)} artifact(s); {rejected} would be REJECTED under "
          f"strict_approvals: true.")
    if unchecked:
        print(f"[approve-local] {unchecked} command-bound artifact(s) are neither accept nor "
              f"reject here — their digest can only be judged against the command being run.")
    if rejected:
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
