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
    Verdict, binding_state, evaluate_artifact, expiry_state, filename_action, load,
)

_COLUMNS = ("file", "action", "schema", "expiry-state", "binding-state", "verdict(strict)")


def _git_root() -> Path:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip()).resolve()
    except Exception:
        return Path.cwd().resolve()


def _row(path: Path) -> tuple[str, str, str, str, str, str]:
    action = filename_action(path)
    art = load(path)
    data = art.data if art else None
    verdict = evaluate_artifact(data, expected_action=action)
    # An artifact carrying binding fields cannot be judged without the command it was
    # minted for, so the inventory reports its BINDING state and judges the rest. It
    # never claims a bound artifact is unusable just because no command is in hand.
    if verdict is Verdict.BINDING_MISMATCH:
        verdict = evaluate_artifact(
            {k: v for k, v in (data or {}).items() if k not in ("command_digest", "repo_id")},
            expected_action=action,
        )
    schema = (data or {}).get("schema_version")
    return (
        path.name,
        action or "-",
        f"v{schema}" if isinstance(schema, int) else "legacy",
        expiry_state(data),
        binding_state(data),
        "ACCEPT" if verdict is Verdict.VALID else f"REJECT ({verdict.value})",
    )


def inventory(root: Path) -> int:
    approvals = root / "state" / "approvals"
    files = sorted(p for p in approvals.glob("*.json")) if approvals.is_dir() else []
    if not files:
        print(f"[approve-local] inventory: no artifacts under {approvals}")
        return 0

    rows = [_row(p) for p in files]
    widths = [max(len(str(r[i])) for r in (list(rows) + [_COLUMNS])) for i in range(len(_COLUMNS))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    print(fmt.format(*_COLUMNS))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(fmt.format(*r))

    rejected = sum(1 for r in rows if r[5].startswith("REJECT"))
    print()
    print(f"[approve-local] {len(rows)} artifact(s); {rejected} would be REJECTED under "
          f"strict_approvals: true.")
    if rejected:
        print("[approve-local] Reissue each with: "
              "bash hooks/local/approve-local.sh <action> <slug> '<reason>'")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="approval_inventory.py")
    parser.add_argument("--root", default=None)
    args = parser.parse_args(argv)
    return inventory(Path(args.root).resolve() if args.root else _git_root())


if __name__ == "__main__":
    raise SystemExit(main())
