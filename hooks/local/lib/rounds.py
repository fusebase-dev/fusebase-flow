"""The gate's round accounting (gate.py; split out of it in 6.0.0-m6, and its carry-over list in 6.0.0-m8, its
120-line ceiling): the verdict and the review records the ledger holds for a slice or phase, gate_rounds, the limit each
counts against, and the carry-over list the gate prints when the rounds are spent."""
from __future__ import annotations

import json
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
    is no round (m6 review B #2), and neither is a verdict carried from Flow 5.x (`carried=` among its fields, or a note
    that starts with "carried"; field item 7.8)."""
    found: dict[str, list[tuple[str, str]]] = {"verdict": [], "review": []}
    for line in fd.read(root / fd.LEDGER).splitlines():
        if m := re.match(rf"\s*\d{{4}}-\d\d-\d\dT\S+\s+(verdict|review)\s+{re.escape(target)}\s+(.*)$", line):
            if re.search(r"(^|\s)carried=", m[2].partition(" -- ")[0]) or m[2].partition(" -- ")[2].lower().startswith(
                    "carried"):
                continue
            result = re.search(r"result=(\S+)", m[2])
            found[m[1]].append((result[1] if result else "?", m[2].partition(" -- ")[2].strip()))
    return found


FIRST = (("security", r"secur|\bauth|secret|credential|token|permission"), ("privacy", r"privacy|personal|\bpii\b|consent"),
         ("data-loss", r"risk data|data.loss|lose data|delet|overwrit|migration"),
         ("owner-answer", r"contradict|owner.answer|\bA\d+\b"))


def carry_over(root: Path, target: str, lines: list[str], past: dict[str, list[tuple[str, str]]]) -> list[str]:
    # the evidence validator's `FLAG item-edit B<n>` line has its ruled row among the checks' flags (field item 7.5)
    items = [ln.strip() for ln in lines if re.search(r" OPEN: |^\s+returns: |^\s+B\d+ FAIL: |^\s+FLAG ", ln)
             and not ln.endswith("[rejected]") and not re.match(r"\s+FLAG item-edit B\d+", ln)]
    items += [f"{k} {i + 1} {r}: {n}" for k, rows in past.items() for i, (r, n) in enumerate(rows) if n and r != "PASS"]
    for f in sorted((root / "state/returns").glob(f"{target}-*.json")):  # the readers' typed returns (verify briefs)
        try:
            doc = json.loads(f.read_text(encoding="utf-8"))
            found = [*doc.get("findings", []), *doc.get("other_findings", []),
                     *(r for r in doc.get("rows", []) if r.get("holds") == "no" or r.get("status") == "FAIL")]
        except (OSError, ValueError, AttributeError):
            continue
        items += [f"{f.stem}: " + ("; ".join(f"{k}={v}" for k, v in x.items()) if isinstance(x, dict) else str(x))
                  for x in found]
    risk = {i: d.get("risk", "") for i, d in fd.backlog(fd.read(root / fd.BACKLOG))[0].items()}
    items = [re.sub(r"^(B\d+) FAIL:", lambda m: f"{m[1]} (risk {risk.get(m[1], '?')}) FAIL:", i) for i in items]

    def rank(text: str) -> int:
        return next((n for n, (_, rx) in enumerate(FIRST) if re.search(rx, text, re.I)), len(FIRST))
    ordered = sorted(items, key=rank)
    return [f"{n}. [{FIRST[rank(t)][0] if rank(t) < len(FIRST) else 'other'}] {t}" for n, t in enumerate(ordered, 1)]
