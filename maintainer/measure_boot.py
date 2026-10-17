#!/usr/bin/env python3
"""Bytes of Flow text each role reads at boot. Last line: the builder total alone. Exit 1 at or over the limit."""
from __future__ import annotations

import re
import sys
from pathlib import Path

CORE = Path(__file__).resolve().parent.parent
BUILDER_LIMIT = 6000
PLANNER_LIMIT = 8192
OVERLAY = "maintainer/overlay/CLAUDE.block.md"
# Representative, not measured: no reader writes state/status.line in 6.0.0-m1 (WP 6 projection estimate).
STATUS_LINE = ("2026-10-16T19:59:28Z running; last activity 2026-10-16T19:58:10Z P7-S3 builder; hooks: claude wired, "
               "codex unenforced; git hooks: flow; alerts: P7-S2 silent 31 min; reader last seen: 2026-10-16T19:59:28Z\n")


def size(rel: str) -> int:
    return len((CORE / rel).read_bytes())


def push_block() -> int:
    text = (CORE / "flow-skills/build/SKILL.md").read_text(encoding="utf-8")
    m = re.search(r"^## Builder push block\n\n```text\n(.*?)^```", text, re.S | re.M)
    if not m:
        sys.exit("measure_boot: no fenced push block under '## Builder push block' in flow-skills/build/SKILL.md")
    return len(m.group(1).encode("utf-8"))


def first_line(rel: str) -> int:
    return len((CORE / rel).read_bytes().split(b"\n", 1)[0]) + 1


def show(title: str, rows: list[tuple[int, str]], limit: int) -> int:
    total = sum(n for n, _ in rows)
    print(title)
    for n, label in rows:
        print(f"  {n:>6,}  {label}")
    print(f"  {total:>6,}  total (limit {limit:,}: {'under' if total < limit else 'OVER'})")
    return total


def main() -> int:
    overlay = (size(OVERLAY), f"overlay Flow block as a Claude Code sub-agent sees it ({OVERLAY}, merged into CLAUDE.md)")
    rules = (size("FLOW_RULES.md"), "FLOW_RULES.md (whole file; reads stop at its last heading)")
    builder = show("builder boot (Flow text in an ordinary slice):", [
        overlay, rules,
        (size("agents/builder/AGENT.md"), "agents/builder/AGENT.md"),
        (push_block(), "flow-skills/build/SKILL.md, Builder push block (fenced body, inlined in the slice)"),
        (size("flow-skills/writing-card/SKILL.md"), "flow-skills/writing-card/SKILL.md (whole file, inlined in the slice)"),
    ], BUILDER_LIMIT)
    show("planner boot:", [
        overlay, rules,
        (size("agents/planner/AGENT.md"), "agents/planner/AGENT.md"),
        (size("workflows/lifecycle.md"), "workflows/lifecycle.md (the planner card reads it at boot)"),
        (first_line("templates/ledger.md"), "docs/flow/ledger.md line 1 (templates/ledger.md)"),
        (len(STATUS_LINE.encode("utf-8")), "state/status.line (representative; no reader in 6.0.0-m1)"),
    ], PLANNER_LIMIT)
    print(builder)
    return 0 if builder < BUILDER_LIMIT else 1


if __name__ == "__main__":
    sys.exit(main())
