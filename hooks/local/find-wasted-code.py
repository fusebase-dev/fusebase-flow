#!/usr/bin/env python3
"""find-wasted-code — static friction-footgun audit for Fusebase Flow.

The active, static inverse of a papercuts log: instead of waiting for an agent to
notice friction and file it, this SCANS the repo for the same north-star footguns
— dead-end tool calls, broken links, missing helpers, footgun configs, silent
push-through — and writes a tracked report to docs/wasted-code/report.md.

MANUAL-TRIGGER ONLY. This runs when the operator invokes `/find-wasted-code`
(or the find-wasted-code skill), never automatically: the skill carries
`disable-model-invocation: true` and no hook wires it. See
flow-skills/find-wasted-code/SKILL.md.

Conservative by construction (stdlib-only, deterministic): a finding is
`broken`/`confirmed` ONLY when provable from repository state; everything
ambiguous is Coverage, not a defect — the audit never blocks or annoys the
operator with a false positive.

Read-only except the single report write, which is containment-checked,
symlink/hardlink-refusing, atomic, and sentinel-guarded.

Usage: python hooks/local/find-wasted-code.py [--root PATH] [--date YYYY-MM-DD]
                                               [--print] [--selftest]
Exit 0 on a normal run (incl. clean repo / findings present); NONZERO on
root/containment/inventory/write failure or any --selftest fixture failure.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from find_wasted_code import engine, report  # noqa: E402
from find_wasted_code import inventory as inv_mod  # noqa: E402
from find_wasted_code.writer import write_report, WriteError  # noqa: E402


class RootError(Exception):
    pass


def _is_flow_root(root: Path) -> bool:
    if (root / ".git").exists():
        return True
    return any((root / m).exists() for m in ("FLOW_RULES.md", "AGENTS.md", "VERSION"))


def resolve_root(override=None) -> Path:
    if override is not None:
        root = Path(override).resolve()
        if not root.is_dir():
            raise RootError("root is not a directory: %s" % root)
    else:
        try:
            out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                                 capture_output=True, text=True, encoding="utf-8",
                                 errors="replace", timeout=10)
            root = Path(out.stdout.strip()).resolve() if out.returncode == 0 and out.stdout.strip() \
                else Path.cwd().resolve()
        except Exception:
            root = Path.cwd().resolve()
    if not _is_flow_root(root):
        raise RootError("%s is not a git/Flow root (need .git or FLOW_RULES.md/AGENTS.md/VERSION)" % root)
    return root


def run_audit(root: Path, date_str: str, do_write: bool):
    inv = inv_mod.build(root)
    findings, cov = engine.run(inv)
    index_id = engine.index_identity(inv)
    content = report.render(findings, cov, date_str, index_id)
    written = None
    if do_write:
        written = write_report(root, content)
    return findings, cov, content, written


def _summary_line(findings, cov, written):
    from find_wasted_code.constants import SEV_BLOCKER, SEV_MAJOR
    blk = sum(1 for f in findings if f.severity == SEV_BLOCKER)
    maj = sum(1 for f in findings if f.severity == SEV_MAJOR)
    loc = str(written) if written else "(not written)"
    return ("find-wasted-code: %d findings (%d blocker, %d major), "
            "%d unresolved, W5 baseline %dpy/%dsh, %d files scanned -> %s"
            % (len(findings), blk, maj, len(cov.unresolved),
               len(cov.w5_py), len(cov.w5_sh), cov.scanned, loc))


def main(argv=None) -> int:
    # Windows consoles default to cp1252; force UTF-8 so summary/report text with
    # non-ASCII (e.g. the redaction marker) never crashes on stdout.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description="find-wasted-code static friction audit")
    ap.add_argument("--root", default=None)
    ap.add_argument("--date", default=None, help="in-report date YYYY-MM-DD (determinism/selftest)")
    ap.add_argument("--print", dest="print_only", action="store_true",
                    help="print summary, do not write the report")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        from find_wasted_code import selftest
        return selftest.run()

    if args.date:
        from find_wasted_code.constants import valid_date
        if not valid_date(args.date):
            print("find-wasted-code: FAILED — --date must be YYYY-MM-DD", file=sys.stderr)
            return 2
        date_str = args.date
    else:
        # single time input; kept out of the deterministic core.
        import datetime
        date_str = datetime.date.today().isoformat()

    try:
        root = resolve_root(args.root)
        findings, cov, content, written = run_audit(root, date_str, do_write=not args.print_only)
    except (RootError, WriteError, inv_mod.InventoryError) as e:
        print("find-wasted-code: FAILED — %s" % e, file=sys.stderr)
        return 2
    print(_summary_line(findings, cov, written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
