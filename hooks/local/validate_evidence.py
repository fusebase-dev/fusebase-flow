#!/usr/bin/env python3
"""Evidence-row validator (design section 6; handoff WP 7c; runner conventions of 2026-10-16, sections 1 to 4):
`validate_evidence.py <slice|phase> [--file F]`; exit 0 every row holds, 1 not, 2 no such slice or phase.
`--staged` (the pre-commit's evidence stage): each phase whose evidence file or state/runs/<phase>/ the commit stages,
the rows present only; a missing row or a recorded FAIL is no failure there, a PASS that does not hold is. The evidence
file, and each run log and capture a row cites, must be the bytes the commit takes: one whose working copy differs from
its staged copy is refused (review r3-83: the check read the working tree while the commit took the index).

Rows: docs/flow/evidence/<phase>.md (docs/flow/evidence.md when that is absent), exactly one per criterion of the items
the slice's (or phase's) tasks serve. Run by gate.py and by the ship step. Prints each capture's sha256 and size, and a
FLAG line when an item's risk or criterion changed since the phase's base. Constants: policies/evidence-classes.yml.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import flow_docs as fd  # noqa: E402
from evidence_rows import check_capture_row, check_test_row, table  # noqa: E402

RANK = {"unit": 0, "smoke": 1, "live": 2}
NEEDS = {"auth": "live", "data": "live", "deploy_config": "live", "ui": "smoke"}  # a touched class -> minimum evidence
RISK = {"auth": "live", "data": "live", "prod": "live"}  # the risk tag raises, never lowers


def accepted(row: dict, answers: dict) -> str:
    """The owner answer A<n> that a BLOCKED-AT-<reason> row cites (status or note) and backlog.md has, else ""."""
    cited = re.findall(r"\bA\d+\b", f"{row['status']} {row['note']}") if row["status"].startswith("BLOCKED-AT-") else []
    return next((a for a in cited if a in answers), "")


def minimum(item: str, ids: set[str], log: list, items: dict, classes: dict, match) -> str:
    """The row's minimum class: from the paths its tasks' commits touched, raised (never lowered) by the risk tag."""
    touched = [p for _, subject, paths in log if fd.task_ids(subject) in ([i] for i in ids) for p in paths]
    found = [NEEDS.get(c, "unit") for c, globs in classes.items() if any(match(p, globs) for p in touched)]
    return max([RISK.get(items.get(item, {}).get("risk", ""), "unit"), *found], key=RANK.get)


def staged_phases(root: Path) -> list[str]:
    """The phases a commit's staged evidence or run paths belong to; docs/flow/evidence.md serves every phase."""
    known, found = {s["phase"] for s in fd.phases(root).values()}, set()
    for p in fd.git(root, "diff", "--cached", "--name-only").splitlines():
        if p == "docs/flow/evidence.md":
            found |= known
        elif m := re.fullmatch(r"docs/flow/evidence/(P\d+)\.md|state/runs/(P\d+)/.+", p):
            found.add(m[1] or m[2])
    return sorted(found & known)


def validate(root: Path, target: str, file: str | None = None, present: bool = False) -> tuple[int, list[str], list[str]]:
    chosen = [s for sid, s in fd.phases(root).items() if target in (sid, s["phase"])]
    if not chosen:
        return 2, [f"evidence {target}: no such slice or phase in {fd.PHASES}"], []
    phase, base, pol = chosen[0]["phase"], chosen[0]["base"] or "", fd.policy(root)
    base = base if fd.SHA.fullmatch(base) and fd.git(root, "rev-parse", "--verify", "-q", f"{base}^{{commit}}") else ""
    rel = file or next((r for r in (f"docs/flow/evidence/{phase}.md",) if (root / r).is_file()), "docs/flow/evidence.md")
    items, answers = fd.backlog(fd.read(root / fd.BACKLOG))
    tasks = [t for s in chosen for t in s["tasks"] if re.fullmatch(r"B\d+", t["item"])]
    wanted, log, match = list(dict.fromkeys(t["item"] for t in tasks)), fd.commits(root, base) if base else [], fd.globber()
    classes = {k: v or [] for k, v in (pol.get("classes") or {}).items()}
    out = [f"evidence {target}: {rel}, {len(wanted)} criteria"]
    if not any(classes.values()):
        out.append("  classes: no globs declared in policies/evidence-classes.yml; the risk tag alone sets the class")
    rows, result, digests, blocked, written = table(fd.read(root / rel)), {}, {}, {}, {}
    unstaged = set(fd.git(root, "diff", "--name-only", "--no-renames", "-z").split("\0")) - {""} if present else set()
    if rel in unstaged:
        return 1, out + [f"EVIDENCE: FAIL ({rel}: its working copy differs from the staged one, and the commit takes the "
                         "staged one; stage it, or set the working change aside, then commit)"], []
    for item in wanted:
        mine = [r for r in rows if r["id"] == item]
        if present and not mine:
            continue
        need = minimum(item, {t["id"] for t in tasks if t["item"] == item}, log, items, classes, match)
        problems, actual, detail = [], "unit" if len(mine) == 1 else "-", []
        if len(mine) != 1:
            problems.append(f"{len(mine)} rows; exactly one is needed")
        elif changed := sorted({mine[0]["log"], mine[0]["capture"].partition("::")[0].strip()} & unstaged):
            problems.append(f"{', '.join(changed)}: the working copy differs from the staged one; stage it, or set the "
                            "working change aside")
        elif not re.fullmatch(str(pol.get("row_status", "^PASS$")), mine[0]["status"]):
            problems.append(f"status `{mine[0]['status']}` does not match row_status")
        elif mine[0]["status"] != "PASS" and (cited := accepted(mine[0], answers)):  # never PASS, never a failure
            blocked[item], actual = (mine[0]["status"].split()[0], cited), "-"
        elif mine[0]["status"] != "PASS" and present:  # --staged: a recorded FAIL or BLOCKED row is no failure, never PASS
            written[item], actual = mine[0]["status"], "-"
        elif mine[0]["status"] != "PASS":
            problems.append(f"the row says {mine[0]['status']}")
        elif "::" in mine[0]["capture"]:
            problems += check_test_row(root, mine[0], base, str(pol.get("test_pass_marker", "^ok [0-9]+ - ")))
        else:
            found, digest, actual = check_capture_row(root, mine[0], pol, phase, detail)
            problems += found
            if digest:
                digests.setdefault(digest, []).append(item)
        if len(mine) == 1 and mine[0]["status"] == "PASS" and RANK[actual] < RANK[need]:
            problems.append(f"{actual} evidence, under the minimum {need} for the paths and risk of {item}")
        result[item] = (problems, actual, need, detail)
    for digest, owners in digests.items():
        if len(owners) > 1 and not all("shared capture" in items.get(i, {}).get("criterion", "") for i in owners):
            for i in owners:
                result[i][0].append(f"shares capture {digest[:12]} with {', '.join(o for o in owners if o != i)}")
    for item, (problems, actual, need, detail) in result.items():
        state = ("FAIL: " + "; ".join(problems) if problems else
                 f"{blocked[item][0]}: accepted by owner answer {blocked[item][1]}, not PASS" if item in blocked else
                 f"{written[item]} (holds as written: no failure of this commit, not PASS)" if item in written else "PASS")
        out.append(f"  {item} {state} (class {actual}, minimum {need})")
        out += detail
    then, _ = fd.backlog(fd.git(root, "show", f"{base}:{fd.BACKLOG}")) if base else ({}, {})
    flags = [f"FLAG item-edit {i}: {k} changed since the phase's base" for i in wanted if i in then and i in items
             for k in ("risk", "criterion", "test") if then[i].get(k) != items[i].get(k)]
    bad = sum(bool(r[0]) for r in result.values())
    held = f"; {len(blocked)} blocked, accepted by an owner answer: " + ", ".join(f"{i} ({a})" for i, (_, a) in
                                                                                blocked.items()) if blocked else ""
    held += f"; {len(written)} as written, not PASS: {', '.join(written)}" if written else ""
    verdict = "FAIL" if bad else "BLOCKED" if blocked else "AS WRITTEN" if written else "PASS"
    out += [f"  {f}" for f in flags] + [f"EVIDENCE: {verdict} ({bad} of {len(result)} "
                                        f"{'rows' if present else 'criteria'} fail{held})"]
    return int(bool(bad)), out, flags


def main(argv: list[str]) -> int:
    fd.utf8_output()
    ap = argparse.ArgumentParser(prog="validate_evidence.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("target", nargs="?", help="a slice (P1-S1) or a phase (P1)")
    ap.add_argument("--file", help="the evidence file, relative to the root")
    ap.add_argument("--staged", action="store_true", help="the phases and rows the commit stages (pre-commit)")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    root = args.root.resolve()
    if args.staged == bool(args.target):
        ap.error("a slice or phase, or --staged")
    if args.staged:
        runs = [validate(root, phase, None, True) for phase in staged_phases(root)]
    else:
        runs = [validate(root, args.target, args.file)]
    print("\n".join(line for _, lines, _ in runs for line in lines) or "evidence --staged: no phase of phases.md staged")
    return max((rc for rc, _, _ in runs), default=0)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
