#!/usr/bin/env python3
"""A2 find-wasted-effort — deterministic, stdlib-only, READ-ONLY ceremony audit.

Process-per-outcome sibling of token-waste-audit.py (FR-26). Different axis:
this reads Flow ARTIFACTS ON DISK (gate/deploy reports, handoffs, approval
artifacts, git log + diffstat, prevents: annotations) and reports ceremony that
bought no safety OUTCOME. token-waste-audit reads transcripts for tokens-per-rule.
Shared discipline (reused, not duplicated): the candidate/false-positive header,
the read-only-first posture, the gitignored state/audit/<date>.md output convention.
Skill: flow-skills/find-wasted-effort/SKILL.md (+ references/rule-signatures.md).

This file is the thin CLI orchestrator: arg parsing, path containment, evidence
assembly, report rendering, write. The load-bearing logic (evidence collectors,
per-rule evaluators, self-test) lives in the hooks/local/find_wasted_effort/
package — extracted along the per-rule seam to stay single-pass readable under
the FR-25 800-line module ceiling (not a mechanical split).

READ-ONLY (Phase 1 / D4): writes ONLY its own report under state/audit/ (gitignored),
and ONLY after asserting that path is inside the repo's state/audit/ (symlink-safe).
NO edits to memory/overlays/specs; NO prune/remove recommendations; NO lane
reclassification. Findings are review CANDIDATES — the PO owns subtraction
(policies/ratchet-governance.yml prune protocol). Writes/prune ship in Phase 2.

Each rule emits one verdict: confirmed | dismissed | inconclusive — with the
contrary evidence it searched for, and an honest reason when an input is genuinely
unavailable. A clean window is never proof a control is worthless
(catastrophic-low-frequency controls are expected to sit idle).

Usage: python hooks/local/find-wasted-effort.py [--window N] [--selftest]
Exit 0 on a normal run (incl. an empty repo). --selftest exits non-zero on failure.
"""

import argparse
import datetime
import subprocess
import sys
from pathlib import Path

# Make the sibling package importable regardless of CWD (FR: absolute paths).
sys.path.insert(0, str(Path(__file__).resolve().parent))

from find_wasted_effort.constants import (   # noqa: E402
    CONFIRMED, DISMISSED, INCONCLUSIVE, DEFAULT_WINDOW, FALSE_POSITIVE_HEADER,
)
from find_wasted_effort import evidence as ev_mod   # noqa: E402
from find_wasted_effort.rules import RULE_EVALUATORS, RULE_TITLES   # noqa: E402


# --------------------------------------------------------------------------
# Repo-root resolution + write-path containment (HIGH finding)
# --------------------------------------------------------------------------

class RootError(Exception):
    """Raised when the resolved root is not a valid git/Flow root, or when the
    report path would escape the repo's state/audit/ directory."""


def resolve_root(override=None):
    """Resolve the repo root. Default: git toplevel. A resolved (symlink-collapsed)
    path is REQUIRED so a crafted/symlinked root cannot escape later containment.

    A valid root must be a git toplevel OR carry a Flow marker (FLOW_RULES.md /
    AGENTS.md / VERSION). Raises RootError otherwise."""
    if override is not None:
        root = Path(override).resolve()
        if not root.is_dir():
            raise RootError("root is not a directory: %s" % root)
    else:
        try:
            out = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, timeout=10,
            )
            if out.returncode == 0 and out.stdout.strip():
                root = Path(out.stdout.strip()).resolve()
            else:
                root = Path.cwd().resolve()
        except Exception:
            root = Path.cwd().resolve()
    if not _is_flow_root(root):
        raise RootError(
            "%s is not a git/Flow root (need .git or FLOW_RULES.md/AGENTS.md/VERSION)" % root)
    return root


def _is_flow_root(root):
    if (root / ".git").exists():
        return True
    return any((root / marker).exists()
               for marker in ("FLOW_RULES.md", "AGENTS.md", "VERSION"))


def contained_report_path(root, today):
    """Resolve the report path and ASSERT it stays inside root/state/audit/, even
    through symlinks. Raises RootError on any escape (path traversal / absolute /
    symlinked state-audit). This is the only path the analyzer ever writes."""
    audit_dir = (root / "state" / "audit")
    # Resolve the audit dir's real location (collapsing any symlink) and require
    # it to live under the resolved root — a symlinked state/audit pointing
    # outside the repo is rejected here.
    resolved_audit = audit_dir.resolve()
    resolved_root = root.resolve()
    if not _is_relative_to(resolved_audit, resolved_root):
        raise RootError("state/audit resolves outside the repo root (symlink escape): %s"
                        % resolved_audit)
    report = resolved_audit / ("find-wasted-effort-%s.md" % today)
    if not _is_relative_to(report.resolve() if report.exists() else report, resolved_audit):
        raise RootError("report path escapes state/audit: %s" % report)
    return report


def _is_relative_to(path, base):
    """Path.is_relative_to back-compat (py<3.9) — present on 3.9+ but defensive."""
    try:
        return path.is_relative_to(base)
    except AttributeError:
        try:
            path.relative_to(base)
            return True
        except ValueError:
            return False


# --------------------------------------------------------------------------
# Evidence assembly from a live repo (read-only)
# --------------------------------------------------------------------------

def assemble_evidence(root, window):
    """Collect every promised input as first-class evidence (MED finding):
    git log + diffstat -> rounds, approvals, gate/deploy reports, handoffs,
    change-notes, suite-run traces, lane candidates, cross-session re-derivation,
    prevents: markers, ratchet-governance coverage map + firing evidence.

    When a rule's input is genuinely unavailable, the matching *_reason field is
    set so the rule emits an honest inconclusive (BLOCKER 1)."""
    commits = ev_mod.git_log(root, window)
    numstat = ev_mod.git_numstat(root, window)
    rounds = ev_mod.build_rounds(commits, numstat)
    artifacts = ev_mod.collect_artifacts(root)
    approvals = ev_mod.collect_approvals(root)
    gating_approvals = ev_mod.deviation_gating_approvals(approvals)

    gate_approvals, gate_blocks = ev_mod.collect_gate_outcomes(artifacts)
    suite_runs, suite_reason = ev_mod.collect_suite_runs(artifacts, rounds)
    lane_cand, lane_reason = ev_mod.collect_lane_candidates(rounds, artifacts)
    cross_sig, cross_reason = ev_mod.collect_cross_session_rederivation(artifacts)
    annotations, ann_lines = ev_mod.collect_prevents_annotations(root)
    gov_elements, gov_ok, severity_tag = ev_mod.load_ratchet_governance(root)
    fired_classes = ev_mod.collect_firing_evidence(artifacts)
    dups = ev_mod.detect_duplicate_blocks(artifacts, FALSE_POSITIVE_HEADER)

    return {
        # rule 1
        "gate_blocks": gate_blocks,
        "gate_approvals": gate_approvals,
        "gating_approvals": gating_approvals,
        # rule 2
        "full_suite_runs_per_round": suite_runs,
        "full_suite_reason": suite_reason,
        # rule 3
        "duplicate_blocks": dups,
        # rule 5
        "lane_candidates": lane_cand,
        "lane_reason": lane_reason,
        # rule 6
        "annotated_files": annotations,
        "annotated_lines": ann_lines,
        "governance_ok": gov_ok,
        "governance_elements": gov_elements,
        "fired_classes": fired_classes,
        "severity_tag": severity_tag,
        # rule 7
        "cross_session_rederivation": cross_sig,
        "cross_session_reason": cross_reason,
        # context
        "approvals": approvals,
        "rounds": rounds,
        "commits": commits,
        "artifacts": artifacts,
        "window": window,
    }


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def build_report(ev, root, today):
    counts = {CONFIRMED: 0, DISMISSED: 0, INCONCLUSIVE: 0}
    findings = []
    for fn in RULE_EVALUATORS:
        f = fn(ev)
        counts[f["verdict"]] += 1
        findings.append(f)
    lines = [
        "# Find-wasted-effort audit — %s" % today, "",
        "Scope: %d artifact(s), %d round(s), %d approval(s), window %d commit(s), git root `%s`." % (
            len(ev["artifacts"]), len(ev["rounds"]), len(ev["approvals"]), ev["window"], root),
        "Read-only (Phase 1 / D4): no writes/prune/reclassify; this report is the only output "
        "(contained under state/audit/, symlink-checked).",
        "", FALSE_POSITIVE_HEADER, "",
        "## Per-rule findings", "",
        "| Rule | Title | Verdict | Summary | Contrary evidence searched |",
        "|---|---|---|---|---|",
    ]
    for f in findings:
        lines.append("| %d | %s | **%s** | %s | %s |" % (
            f["rule"], RULE_TITLES[f["rule"]], f["verdict"], f["summary"], f["contrary"]))
    lines += ["", "Rule 4 (context-rebuild overhead) is CUT — see /token-waste-audit's "
              "cross-session aggregate (v3.21.0); not re-implemented here.", ""]

    # Rule 6 per-element breakdown (BLOCKER 2 — per-element verdicts, never "remove")
    r6 = next((f for f in findings if f["rule"] == 6), None)
    if r6 and r6.get("elements"):
        lines += ["## Rule 6 — per-element ratchet inventory (review candidates, never 'remove')", "",
                  "| File | Element | prevents | catastrophic | Verdict | Why |",
                  "|---|---|---|---|---|---|"]
        for el in r6["elements"]:
            lines.append("| %s | %s | %s | %s | **%s** | %s |" % (
                el["file"], el["element"], ", ".join(el["prevents"]) or "—",
                "yes" if el["catastrophic"] else "no", el["verdict"], el["why"]))
        lines.append("")

    # Coverage section (mandatory — silence is not safety, D5)
    lines += ["## Coverage (D5 — silence is not safety)", ""]
    if ev["governance_ok"]:
        lines.append("ratchet-governance.yml parsed: %d annotated control(s) in the coverage map; "
                     "prevents: markers found on disk in %d file(s)." % (
                         len(ev["governance_elements"]), len(ev["annotated_files"])))
        lines.append("")
        lines.append("On-disk prevents:-marked files: %s" % (
            ", ".join(sorted(ev["annotated_files"])) or "none"))
        lines.append("")
        lines.append("Firing evidence in window (controls that bought an outcome): %s" % (
            ", ".join(sorted(ev["fired_classes"])) or "none observed"))
    else:
        lines.append("policies/ratchet-governance.yml absent/unparseable — coverage cannot be stated "
                     "(rule 6 inconclusive). This is a coverage GAP, not a safety verdict.")
    lines += ["", "## Inputs collected (read-only)", "",
              "| Input | Count / status |", "|---|---|",
              "| Rounds (git log + diffstat) | %d |" % len(ev["rounds"]),
              "| Round artifacts (handoffs/gate/deploy/change-notes) | %d |" % len(ev["artifacts"]),
              "| Approval artifacts (state/approvals/) | %d |" % len(ev["approvals"]),
              "| Deviation-gating approvals (rule-1 contrary evidence) | %s |" % (
                  ", ".join(sorted({a["kind"] for a in ev.get("gating_approvals", [])}))
                  or "none"),
              "| Gate deviation outcomes (approve / block) | %d / %d |" % (
                  ev["gate_approvals"], ev["gate_blocks"]),
              "| Suite-run traces | %s |" % (
                  "%d round(s)" % len(ev["full_suite_runs_per_round"])
                  if ev["full_suite_runs_per_round"] else "none (inconclusive: %s)" % ev["full_suite_reason"]),
              "| Lane candidate | %s |" % (
                  ev["lane_candidates"]["round"] if ev["lane_candidates"]
                  else "none (inconclusive: %s)" % ev["lane_reason"]),
              "| Cross-session re-derivation | %s |" % (
                  ev["cross_session_rederivation"]["record"] if ev["cross_session_rederivation"]
                  else "none (inconclusive: %s)" % ev["cross_session_reason"]),
              ""]
    lines += ["## Totals", "",
              "confirmed %d · dismissed %d · inconclusive %d" % (
                  counts[CONFIRMED], counts[DISMISSED], counts[INCONCLUSIVE]),
              "", "Findings are review candidates. The PO owns subtraction "
              "(policies/ratchet-governance.yml prune protocol); writes/prune ship in Phase 2.", ""]
    return "\n".join(lines), counts, findings


def write_report(root, report_path, report):
    """Write the report to report_path AFTER re-asserting containment immediately
    before the write (TOCTOU hardening, LOW finding). Create/resolve the audit dir,
    then re-run the containment check against the now-on-disk dir, then reject a
    symlinked report path via lstat before writing. Raises RootError on any escape;
    writes only inside root/state/audit/."""
    audit_dir = report_path.parent
    audit_dir.mkdir(parents=True, exist_ok=True)
    # Re-resolve the (now-created) audit dir and re-assert it lives under the repo
    # root — a symlink swapped in between contained_report_path() and here is caught.
    resolved_audit = audit_dir.resolve()
    if not _is_relative_to(resolved_audit, root.resolve()):
        raise RootError("state/audit resolves outside the repo root (symlink escape): %s"
                        % resolved_audit)
    if not _is_relative_to(report_path.resolve() if report_path.exists() else report_path,
                           resolved_audit):
        raise RootError("report path escapes state/audit: %s" % report_path)
    # Reject a symlinked report target outright (lstat does not follow the link),
    # so we never write THROUGH a symlink planted at the report path.
    if report_path.is_symlink():
        raise RootError("report path is a symlink — refusing to write through it: %s" % report_path)
    try:
        report_path.write_text(report, encoding="utf-8", newline="\n")
        return str(report_path)
    except OSError as exc:
        return "(write failed: %s)" % exc


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="A2 find-wasted-effort — read-only ceremony audit (deterministic, stdlib-only)")
    ap.add_argument("--window", type=int, default=DEFAULT_WINDOW, metavar="N",
                    help="commit/round window to consider (default %d)" % DEFAULT_WINDOW)
    ap.add_argument("--selftest", action="store_true",
                    help="run synthetic + end-to-end fixtures and exit (no repo report write)")
    # --root is an INTERNAL test hook only (the selftest's path-escape fixtures
    # need it). It is intentionally NOT advertised on the public command surface
    # (.claude/commands/find-wasted-effort.md). Suppressed from --help; still
    # subjected to resolve_root() + contained_report_path() containment.
    ap.add_argument("--root", default=None, help=argparse.SUPPRESS)
    args = ap.parse_args()

    if args.selftest:
        from find_wasted_effort.selftest import run_selftest
        return run_selftest()

    try:
        root = resolve_root(args.root)
    except RootError as exc:
        print("[find-wasted-effort] ERROR: %s" % exc, file=sys.stderr)
        return 2
    today = datetime.date.today().isoformat()
    ev = assemble_evidence(root, args.window)
    report, counts, _ = build_report(ev, root, today)
    try:
        report_path = contained_report_path(root, today)
        wrote = write_report(root, report_path, report)
    except RootError as exc:
        print("[find-wasted-effort] ERROR: refusing to write — %s" % exc, file=sys.stderr)
        return 2

    print("[find-wasted-effort] artifacts: %d | rounds: %d | window: %d | report: %s" % (
        len(ev["artifacts"]), len(ev["rounds"]), args.window, wrote))
    print("[find-wasted-effort] confirmed %d · dismissed %d · inconclusive %d "
          "(candidates, not verdicts — see report header)" % (
              counts[CONFIRMED], counts[DISMISSED], counts[INCONCLUSIVE]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
