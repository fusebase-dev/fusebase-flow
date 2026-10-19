#!/usr/bin/env python3
"""Evidence-row validator (design section 6; handoff WP 7c; runner conventions of 2026-10-16, sections 1 to 4):
`validate_evidence.py <slice|phase> [--file F]`; exit 0 every row holds, 1 not, 2 no such slice or phase.
`--staged` (the pre-commit's evidence stage): each phase whose evidence file or state/runs/<phase>/ the commit stages,
the rows present only; a missing row or a recorded FAIL is no failure there, a PASS that does not hold is.

Rows: docs/flow/evidence/<phase>.md (docs/flow/evidence.md when that is absent), exactly one per criterion of the items
the slice's (or phase's) tasks serve. Run by gate.py and by the ship step. Prints each capture's sha256 and size, and a
FLAG line when an item's risk or criterion changed since the phase's base. Constants: policies/evidence-classes.yml.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import flow_docs as fd  # noqa: E402

IMAGE = (".png", ".jpg", ".jpeg", ".webp", ".gif")  # capture_min_bytes.image applies; other files take .other
ADDED_SKIP = re.compile(r"^\+(?!\+\+).*\b(skip|todo)\b", re.I | re.M)
RANK = {"unit": 0, "smoke": 1, "live": 2}
NEEDS = {"auth": "live", "data": "live", "deploy_config": "live", "ui": "smoke"}  # a touched class -> minimum evidence
RISK = {"auth": "live", "data": "live", "prod": "live"}  # the risk tag raises, never lowers


def run_log(path: Path, header: str) -> dict | None:
    """{title, records: [(time, row, record)]} when the file carries the policy's run-log header, else None."""
    try:
        lines = [line.rstrip() for line in path.read_text(encoding="utf-8", errors="replace").splitlines()]
    except OSError:
        return None
    if header not in lines:
        return None
    records = []
    for line in lines[lines.index(header) + 1:]:
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) >= 3 and not re.fullmatch(r"[-: ]+", cells[0]):
            records.append((cells[0], cells[1], "|".join(cells[2:]).strip()))
    return {"title": next((line for line in lines if line.startswith("# ")), ""), "records": records}


def table(text: str) -> list[dict]:
    keys = ("status", "capture", "sha256", "bytes", "log", "note")
    found = []
    for line in text.splitlines():
        if m := re.match(r"\|\s*(B\d+)\s*\|(.*)\|\s*$", line):
            found.append({"id": m[1], **dict(zip(keys, [c.strip() for c in m[2].split("|")] + [""] * 6))})
    return found


def deploy_finished(root: Path, env: str) -> tuple[float, str] | None:
    """`finished` of the latest line in state/deploys/<env>.jsonl (runner conventions section 4)."""
    latest = None
    try:
        lines = (root / "state/deploys" / f"{env}.jsonl").read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in lines:
        try:
            value = str(json.loads(line).get("finished", ""))
        except (ValueError, AttributeError):
            continue
        if (t := fd.stamp(value)) is not None and (latest is None or t > latest[0]):
            latest = (t, value)
    return latest


def flaky(root: Path, phase: str, row: dict, header: str) -> str | None:
    """The earlier run whose log records a FAIL for this row, "" when none, None when the run is not indexed."""
    try:
        runs = [r.split("\t") for r in (root / "state/runs" / phase / "index.tsv").read_text("utf-8").splitlines()]
    except OSError:
        return None
    runs = [r for r in runs if len(r) >= 4 and fd.stamp(r[1]) is not None]
    here = (root / row["log"]).parent.resolve()
    current = next((r for r in runs if (root / r[2]).resolve() == here), None)
    if current is None:
        return None
    try:
        names = {row["id"], (root / row["capture"]).resolve().relative_to(here).parts[0]}
    except (ValueError, IndexError):
        names = {row["id"]}
    for run_id, started, folder, _ in (r[:4] for r in runs):
        if fd.stamp(started) < fd.stamp(current[1]) and (log := run_log(root / folder / "README.md", header)):
            if any(rec[1] in names and rec[2].startswith("FAIL") for rec in log["records"]):
                return run_id
    return ""


def check_test_row(root: Path, row: dict, base: str, marker: str) -> list[str]:
    """A test-id row: `ok <n> - <name>` in its TAP log, the test present at HEAD, no skip or todo added since base."""
    file, _, name = row["capture"].partition("::")
    problems = []
    try:
        tap = (root / row["log"]).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        tap = None
        problems.append(f"log {row['log']} is missing")
    if tap is not None and not any((m := re.match(marker, ln)) and ln[m.end():].strip() == name.strip() for ln in tap):
        problems.append(f"no `ok <n> - {name.strip()}` line without SKIP or TODO in {row['log']}")
    source = fd.git(root, "show", f"HEAD:{file.strip()}")
    if name.strip() not in source:
        problems.append(f"the test is absent at HEAD ({file.strip()})")
    if base and ADDED_SKIP.search(fd.git(root, "diff", base, "HEAD", "--", file.strip())):
        problems.append("a skip or todo token was added to the test file since the phase's base")
    return problems


def check_capture_row(root: Path, row: dict, pol: dict, phase: str, out: list[str]) -> tuple[list[str], str, str]:
    """A capture row: (problems, sha256, evidence class of its run log)."""
    path, problems = (root / row["capture"]).resolve(), []
    if not path.is_file() or not path.is_relative_to(root):
        return [f"capture {row['capture']} is missing"], "", "unit"
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    floor = int((pol.get("capture_min_bytes") or {}).get("image" if path.suffix.lower() in IMAGE else "other", 1))
    out.append(f"    capture {row['capture']} sha256={digest} bytes={len(data)}")
    if len(data) < floor:
        problems.append(f"capture is {len(data)} bytes, under the floor of {floor}")
    if row["sha256"] != digest or row["bytes"].replace(",", "") != str(len(data)):
        problems.append("the row's sha256 or Bytes differ from the file")
    log = run_log(root / row["log"], str(pol.get("run_log_header", "")))
    if log is None:
        return problems + [f"unrecognised run log {row['log']} (no `{pol.get('run_log_header')}` header)"], digest, "unit"
    if any(re.match(str(pol.get("finding_marker", "^FINDING ")), rec[2]) for rec in log["records"]):
        problems.append("the run log records a FINDING behind this PASS")
    env = re.search(r"\(([^()]+)\)\s*$", log["title"])
    deployed = deploy_finished(root, env[1]) if env else None
    started = fd.stamp(log["records"][0][0]) if log["records"] else None
    if deployed and (started is None or started < deployed[0]):
        problems.append(f"the run started {log['records'][0][0] if log['records'] else '?'}, before the "
                        f"{env[1]} deploy finished {deployed[1]}")
    earlier = flaky(root, phase, row, str(pol.get("run_log_header", "")))
    if earlier is None:
        out.append(f"    history unresolved: the run is not in state/runs/{phase}/index.tsv")
    elif earlier and "repro" not in row["note"].lower():
        problems.append(f"FLAKY: run {earlier} recorded a FAIL for it and the row has no reproduction note")
    return problems, digest, ("live" if log["title"].startswith("# Live run") else "smoke")


def minimum(item: str, ids: set[str], log: list, items: dict, classes: dict, match) -> str:
    """The row's minimum class: from the paths its tasks' commits touched, raised (never lowered) by the risk tag."""
    touched = [p for _, subject, paths in log if fd.TASK.findall(subject) in ([i] for i in ids) for p in paths]
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
    items, _ = fd.backlog(fd.read(root / fd.BACKLOG))
    tasks = [t for s in chosen for t in s["tasks"] if re.fullmatch(r"B\d+", t["item"])]
    wanted, log, match = list(dict.fromkeys(t["item"] for t in tasks)), fd.commits(root, base) if base else [], fd.globber()
    classes = {k: v or [] for k, v in (pol.get("classes") or {}).items()}
    out = [f"evidence {target}: {rel}, {len(wanted)} criteria"]
    if not any(classes.values()):
        out.append("  classes: no globs declared in policies/evidence-classes.yml; the risk tag alone sets the class")
    rows, result, digests = table(fd.read(root / rel)), {}, {}
    for item in wanted:
        mine = [r for r in rows if r["id"] == item]
        if present and not mine:
            continue
        need = minimum(item, {t["id"] for t in tasks if t["item"] == item}, log, items, classes, match)
        problems, actual, detail = [], "unit" if len(mine) == 1 else "-", []
        if len(mine) != 1:
            problems.append(f"{len(mine)} rows; exactly one is needed")
        elif not re.fullmatch(str(pol.get("row_status", "^PASS$")), mine[0]["status"]):
            problems.append(f"status `{mine[0]['status']}` does not match row_status")
        elif mine[0]["status"] != "PASS":
            problems += [] if present else [f"the row says {mine[0]['status']}"]
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
        out.append(f"  {item} {'FAIL: ' + '; '.join(problems) if problems else 'PASS'} (class {actual}, minimum {need})")
        out += detail
    then, _ = fd.backlog(fd.git(root, "show", f"{base}:{fd.BACKLOG}")) if base else ({}, {})
    flags = [f"FLAG item-edit {i}: {k} changed since the phase's base" for i in wanted if i in then and i in items
             for k in ("risk", "criterion", "test") if then[i].get(k) != items[i].get(k)]
    bad = sum(bool(r[0]) for r in result.values())
    out += [f"  {f}" for f in flags] + [f"EVIDENCE: {'FAIL' if bad else 'PASS'} ({bad} of {len(result)} "
                                        f"{'rows' if present else 'criteria'} fail)"]
    return int(bool(bad)), out, flags


def main(argv: list[str]) -> int:
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
