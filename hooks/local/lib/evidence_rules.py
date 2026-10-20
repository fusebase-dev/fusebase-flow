"""The evidence validator's run-log rules (validate_evidence.py; split out of it in 6.0.0-m6, its 250-line ceiling):
the run log as the runner writes it, the FINDING marker behind a PASS, and the FLAKY rule (a FAIL in an earlier run
of the same phase). Constants: policies/evidence-classes.yml (run_log_header, finding_marker)."""
from __future__ import annotations

import re
from pathlib import Path

import flow_docs as fd


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


def flaky(root: Path, phase: str, row: dict, header: str) -> str | None:
    """An earlier run in this run's folder (its phase's) logging a FAIL for this row; "" when none, None if unindexed."""
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
    for run_id, started, folder, _ in (r[:4] for r in runs if (root / r[2]).resolve().parent == here.parent):
        if fd.stamp(started) < fd.stamp(current[1]) and (log := run_log(root / folder / "README.md", header)):
            if any(rec[1] in names and rec[2].startswith("FAIL") for rec in log["records"]):
                return run_id
    return ""


def finding_problems(log: dict, pol: dict) -> list[str]:
    """The FINDING marker: a run log that records a finding has no PASS behind it."""
    if any(re.match(str(pol.get("finding_marker", "^FINDING ")), rec[2]) for rec in log["records"]):
        return ["the run log records a FINDING behind this PASS"]
    return []


def flaky_problems(root: Path, phase: str, row: dict, pol: dict, out: list[str]) -> list[str]:
    """FLAKY: an earlier run of the phase recorded a FAIL for the row, and the row's note gives no reproduction."""
    earlier = flaky(root, phase, row, str(pol.get("run_log_header", "")))
    if earlier is None:
        out.append(f"    history unresolved: the run is not in state/runs/{phase}/index.tsv")
    elif earlier and "repro" not in row["note"].lower():
        return [f"FLAKY: run {earlier} recorded a FAIL for it and the row has no reproduction note"]
    return []
