#!/usr/bin/env python3
"""The gate (design section 6 "Who runs what"; handoff WP 7d; adversarial C2-07): `gate.py <slice|phase>` runs the
DONE check, the checks and the evidence-row validator and writes state/gate/<target>.txt, three blocks that open the
verdict brief. Exit 0 ready for the verdict, 1 a check failed (no round spent), 2 no such slice or phase, 3
BLOCKED-AT-gate-budget: the verdicts recorded in the ledger for the target reached gate_rounds
(policies/approval-policy.yml at HEAD; a local override may lower it, never raise it), and the gate prints a numbered
carry-over list for the operator, security, privacy, data-loss and owner-answer contradictions first.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

import yaml

# The script's own folder too: PYTHONSAFEPATH=1 leaves it off sys.path, and a sibling script is imported below.
sys.path[:0] = [str(Path(__file__).resolve().parent / "lib"), str(Path(__file__).resolve().parent)]
import flow_docs as fd  # noqa: E402
import checks  # noqa: E402
import done  # noqa: E402
import validate_evidence  # noqa: E402

FIRST = (("security", r"secur|\bauth|secret|credential|token|permission"), ("privacy", r"privacy|personal|\bpii\b|consent"),
         ("data-loss", r"risk data|data.loss|lose data|delet|overwrit|migration"),
         ("owner-answer", r"contradict|owner.answer|\bA\d+\b"))


def rounds(root: Path) -> int:
    """gate_rounds from HEAD, lowered (never raised) by policies/approval-policy.local.yml."""
    limit = fd.policy(root, "approval-policy").get("gate_rounds")
    limit = limit if isinstance(limit, int) and limit > 0 else 2
    try:
        lower = yaml.safe_load((root / "policies/approval-policy.local.yml").read_text(encoding="utf-8"))["gate_rounds"]
    except (OSError, yaml.YAMLError, TypeError, KeyError):
        return limit
    return min(limit, lower) if isinstance(lower, int) and lower > 0 else limit


def verdicts(root: Path, target: str) -> list[tuple[str, str]]:
    """(result, note) of each `verdict <target>` record in the ledger, in order."""
    found = []
    for line in fd.read(root / fd.LEDGER).splitlines():
        if m := re.match(rf"\s*\S+\s+verdict\s+{re.escape(target)}\s+(.*)$", line):
            result = re.search(r"result=(\S+)", m[1])
            found.append((result[1] if result else "?", m[1].partition(" -- ")[2].strip()))
    return found


def carry_over(root: Path, target: str, lines: list[str], past: list[tuple[str, str]]) -> list[str]:
    items = [ln.strip() for ln in lines if re.search(r" OPEN: |^\s+returns: |^\s+B\d+ FAIL: |^\s+FLAG ", ln)
             and not ln.endswith("[rejected]")]
    items += [f"verdict {i + 1} {res}: {note}" for i, (res, note) in enumerate(past) if note and res != "PASS"]
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


def gate(root: Path, target: str) -> tuple[int, list[str]]:
    slices = {sid: s for sid, s in fd.phases(root).items() if target in (sid, s["phase"])}
    if not slices:
        return 2, [f"gate {target}: no such slice or phase in {fd.PHASES}"]
    blocks, failed = [], False
    for title, runs in (("DONE", [done.check(root, sid)[:2] for sid in slices]),
                        ("Checks", [checks.run(root, sid) for sid in slices]),
                        ("Evidence", [validate_evidence.validate(root, target)[:2]])):
        blocks += [f"## {title}"] + [ln for _, out in runs for ln in out]
        failed = failed or (title != "Checks" and any(rc for rc, _ in runs))
    past, limit = verdicts(root, target), rounds(root)
    head = f"# Gate {target} {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}: {len(past)} of {limit} rounds used"
    if len(past) >= limit:
        rc, tail = 3, [f"BLOCKED-AT-gate-budget: {len(past)} verdicts recorded for {target}, gate_rounds {limit}. "
                       "Carry-over for the operator:", *carry_over(root, target, blocks, past)]
    elif failed:
        rc, tail = 1, [f"GATE: FAIL: send {target} back to build with the lines above; no round is spent"]
    else:
        rc, tail = 0, [f"GATE: PASS: dispatch the verdict (python hooks/local/slice.py {target} --brief verdict)"]
    out = [head, *blocks, *tail]
    path = root / "state/gate" / f"{target}.txt"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    return rc, out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="gate.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("target", help="a slice (P1-S1) or a phase (P1)")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    rc, out = gate(args.root.resolve(), args.target)
    print("\n".join(out))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
