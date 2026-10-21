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


# The order the carry-over lists, by what an entry DECLARES (field item 7.9: matching words anywhere filed a wording
# fix as [security]): a finding's `class`, a note that starts `<class>:`, a FAIL row's item risk (auth, data), or a
# contradiction of an owner answer A<n>; anything else is [other], ordered by its severity.
FIRST = ("security", "privacy", "data-loss", "owner-answer")
RISK_CLASS = {"auth": "security", "prod": "security", "data": "data-loss"}
SEVERITY = ("BLOCKER", "HIGH", "MEDIUM", "LOW")


def carry_over(root: Path, target: str, lines: list[str], past: dict[str, list[tuple[str, str]]]) -> list[str]:
    # the evidence validator's `FLAG item-edit B<n>` line has its ruled row among the checks' flags (field item 7.5)
    items = [ln.strip() for ln in lines if re.search(r" OPEN: |^\s+returns: |^\s+B\d+ FAIL: |^\s+FLAG ", ln)
             and not ln.endswith("[rejected]") and not re.match(r"\s+FLAG item-edit B\d+", ln)]
    items += [f"{k} {i + 1} {r}: {n}" for k, rows in past.items() for i, (r, n) in enumerate(rows) if n and r != "PASS"]
    for f in latest_returns(root, target):  # the readers' typed returns (verify briefs), the last round of each
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

    def kind(text: str) -> str:
        declared = re.search(r"(?:^|:\s|;\s)class=([a-z-]+)", text) or re.match(r"(?:verdict|review) \d+ \S+: ([a-z-]+):",
                                                                                    text)
        risky = re.match(r"B\d+ \(risk (\w+)\) FAIL", text)
        if declared and declared[1] in FIRST:
            return declared[1]
        if risky and risky[1] in RISK_CLASS:
            return RISK_CLASS[risky[1]]
        return "owner-answer" if re.search(r"contradict\w*\b.*\bA\d+\b", text, re.I) else "other"

    def rank(text: str) -> tuple[int, int]:
        sev = re.search(r"severity=(\w+)", text)
        return ((FIRST + ("other",)).index(kind(text)),
                SEVERITY.index(sev[1].upper()) if sev and sev[1].upper() in SEVERITY else len(SEVERITY))
    ordered = sorted(items, key=rank)
    return [f"{n}. [{kind(t)}] {t}" for n, t in enumerate(ordered, 1)]


def latest_returns(root: Path, target: str) -> list[Path]:
    """The last round of each reader's return for `target`: <target>-review.json is round 1, -review-2.json round 2
    (field item 7.9: round 1's fixed findings were listed again)."""
    best: dict[str, tuple[int, Path]] = {}
    for f in (root / "state/returns").glob(f"{target}-*.json"):
        m = re.fullmatch(r"(.*?)-?(\d*)", f.stem[len(target) + 1:])
        key, n = m[1], int(m[2] or 1)
        if key not in best or n > best[key][0]:
            best[key] = (n, f)
    return sorted(f for _, f in best.values())
