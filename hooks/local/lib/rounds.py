"""The gate's round accounting (gate.py; split out of it in 6.0.0-m6, its 120-line ceiling): the verdict and the
review records the ledger holds for a slice or phase, and gate_rounds, the limit each counts against."""
from __future__ import annotations

import re
from pathlib import Path

import yaml

import flow_docs as fd


def rounds(root: Path) -> int:
    """gate_rounds from HEAD, lowered (never raised) by policies/approval-policy.local.yml."""
    limit = fd.policy(root, "approval-policy").get("gate_rounds")
    limit = limit if isinstance(limit, int) and limit > 0 else 2
    try:
        lower = yaml.safe_load((root / "policies/approval-policy.local.yml").read_text(encoding="utf-8"))["gate_rounds"]
    except (OSError, yaml.YAMLError, TypeError, KeyError):
        return limit
    return min(limit, lower) if isinstance(lower, int) and lower > 0 else limit


def records(root: Path, target: str) -> dict[str, list[tuple[str, str]]]:
    """(result, note) of each `verdict <target>` and each `review <target>` record in the ledger, in order, by kind.
    A record starts with its UTC time (templates/ledger.md); a `## Next` or `## Handoff` bullet that says "review P1-S1"
    is no round (m6 review B #2)."""
    found: dict[str, list[tuple[str, str]]] = {"verdict": [], "review": []}
    for line in fd.read(root / fd.LEDGER).splitlines():
        if m := re.match(rf"\s*\d{{4}}-\d\d-\d\dT\S+\s+(verdict|review)\s+{re.escape(target)}\s+(.*)$", line):
            result = re.search(r"result=(\S+)", m[2])
            found[m[1]].append((result[1] if result else "?", m[2].partition(" -- ")[2].strip()))
    return found
