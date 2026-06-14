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
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# Make the sibling package importable regardless of CWD (FR: absolute paths).
sys.path.insert(0, str(Path(__file__).resolve().parent))

from find_wasted_effort.constants import (   # noqa: E402
    CONFIRMED, DISMISSED, INCONCLUSIVE, DEFAULT_WINDOW, FALSE_POSITIVE_HEADER,
)
from find_wasted_effort import evidence as ev_mod   # noqa: E402
from find_wasted_effort.rules import RULE_EVALUATORS, RULE_TITLES   # noqa: E402
from find_wasted_effort.proposals import build_proposals   # noqa: E402


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


def contained_audit_path(root, basename):
    """Resolve an output path UNDER root/state/audit/ and ASSERT it stays inside,
    even through symlinks. Raises RootError on any escape (path traversal / absolute
    / symlinked state-audit). state/audit/ is the ONLY directory the analyzer ever
    writes — both the .md report and the optional .json proposals file go through
    here (Phase 2A keeps the analyzer read-only to the rest of the project).
    Threat model (at-rest aliases defended; active mid-run FS races out of scope):
    see write_audit_file()."""
    # Reject a basename that is absolute or carries a parent-ref / path separator
    # BEFORE composing the target — a "../evil.md" or "/etc/x" basename must never
    # reach the join. Both real callers pass a fixed flat basename, so this is a
    # no-op for them; it closes internal-misuse traversal at the boundary.
    if (os.path.isabs(basename) or ".." in Path(basename).parts
            or "/" in basename or "\\" in basename):
        raise RootError("audit basename must be a flat name, not a path/traversal: %r"
                        % basename)
    audit_dir = (root / "state" / "audit")
    # Resolve the audit dir's real location (collapsing any symlink) and require
    # it to live under the resolved root — a symlinked state/audit pointing
    # outside the repo is rejected here.
    resolved_audit = audit_dir.resolve()
    resolved_root = root.resolve()
    if not _is_relative_to(resolved_audit, resolved_root):
        raise RootError("state/audit resolves outside the repo root (symlink escape): %s"
                        % resolved_audit)
    # Resolve the composed target FIRST, then assert it stays under state/audit —
    # a resolved target that escapes (symlink/traversal) is rejected here.
    target = resolved_audit / basename
    resolved_target = target.resolve() if target.exists() else (resolved_audit / basename).resolve(strict=False)
    if not _is_relative_to(resolved_target, resolved_audit):
        raise RootError("audit output path escapes state/audit: %s" % target)
    return target


def contained_report_path(root, today):
    """The contained .md report path (Phase 1 surface, retained name)."""
    return contained_audit_path(root, "find-wasted-effort-%s.md" % today)


def contained_proposals_path(root, today):
    """The contained, gitignored .json proposals path (Phase 2A optional sibling)."""
    return contained_audit_path(root, "find-wasted-effort-proposals-%s.json" % today)


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
    # Phase 2A — Proposed memory entries (read-only-safe OUTPUT; nothing applied).
    proposals = build_proposals(ev, findings)
    lines += _render_proposals_section(proposals)

    lines += ["## Totals", "",
              "confirmed %d · dismissed %d · inconclusive %d · proposals %d" % (
                  counts[CONFIRMED], counts[DISMISSED], counts[INCONCLUSIVE], len(proposals)),
              "", "Findings are review candidates. The PO owns subtraction "
              "(policies/ratchet-governance.yml prune protocol); the write-apply is "
              "Phase 2B (DEFERRED, consumer-repo, AC2b). This audit only PROPOSES.", ""]
    return "\n".join(lines), counts, findings, proposals


def _render_proposals_section(proposals):
    """Render the 'Proposed memory entries' report section (Phase 2A).

    Proposals are changes a HUMAN could apply — the audit emits them, never applies
    them (read-only to the project; the only on-disk output is the contained
    state/audit/ report + optional sibling JSON). Each cites RAW on-disk evidence
    (never a prior audit report — self-output quarantine). rule-6 entries are
    `prune_review_candidate`, never an auto-prune."""
    out = ["## Proposed memory entries (Phase 2A — read-only-safe; nothing applied)", ""]
    if not proposals:
        out += ["No proposals: no `confirmed` finding and no rule-6 review candidate "
                "in this window (inconclusive/dismissed findings emit none).", "",
                "Phase 2A emits proposals ONLY into this report (and an optional "
                "gitignored state/audit/ JSON). It applies nothing — the write-apply "
                "is Phase 2B (DEFERRED, AC2b); the PO owns subtraction.", ""]
        return out
    out += ["Each proposal is a change a HUMAN could apply (operator_confirmation_required: "
            "true; source: audit). The audit applies NOTHING — Phase 2A is output-only; "
            "the write-apply is Phase 2B (DEFERRED, consumer-repo, AC2b). Evidence cites "
            "RAW on-disk artifacts, never a prior audit report (self-output quarantine).", "",
            "| Proposal id | Rule | Verdict | Target kind | Target path | Raw evidence |",
            "|---|---|---|---|---|---|"]
    for p in proposals:
        refs = ", ".join("`%s`" % r for r in p["raw_evidence_refs"]) or "—"
        out.append("| `%s` | %d | **%s** | %s | %s | %s |" % (
            p["proposal_id"], p["rule"], p["verdict"], p["target_kind"],
            p["target_path"], refs))
    out.append("")
    out += ["### Proposal detail (the exact change a human COULD apply)", ""]
    for p in proposals:
        out += ["- **%s** (rule %d · %s): %s" % (
            p["proposal_id"], p["rule"], p["verdict"], p["exact_patch"])]
    out.append("")
    return out


def write_audit_file(root, target_path, content):
    """Write `content` to target_path via an atomic temp-then-os.replace() INSIDE
    the contained state/audit/ dir, AFTER re-asserting containment immediately
    before the write (TOCTOU hardening, LOW findings). Create/resolve the audit dir,
    re-run the containment check against the now-on-disk dir, then reject a target
    that is a symlink OR a hardlink (lstat: st_nlink > 1) so we never write THROUGH
    a planted alias. os.replace() swaps in a NEW inode for the directory entry, so
    even a pre-planted hardlink/alias at the target is BROKEN by the replace and no
    file OUTSIDE state/audit/ is ever modified (the containment invariant is
    absolute — read-only-safety is Phase 2A's whole safety case). Raises RootError
    on any escape; writes only inside root/state/audit/. Shared by the .md report
    AND the .json proposals sibling — both stay inside the single contained dir.

    THREAT MODEL: containment defends pre-planted symlink/hardlink/traversal targets
    AT REST. Active concurrent FS races mid-run (e.g. renaming state/audit between
    temp-create and replace) are OUT OF SCOPE — local single-operator read-only tool."""
    audit_dir = target_path.parent
    audit_dir.mkdir(parents=True, exist_ok=True)
    # Re-resolve the (now-created) audit dir and re-assert it lives under the repo
    # root — a symlink swapped in between contained_audit_path() and here is caught.
    resolved_audit = audit_dir.resolve()
    if not _is_relative_to(resolved_audit, root.resolve()):
        raise RootError("state/audit resolves outside the repo root (symlink escape): %s"
                        % resolved_audit)
    if not _is_relative_to(target_path.resolve() if target_path.exists() else target_path,
                           resolved_audit):
        raise RootError("audit output path escapes state/audit: %s" % target_path)
    # Reject a symlinked target outright (lstat does not follow the link), so we
    # never write THROUGH a symlink planted at the output path.
    if target_path.is_symlink():
        raise RootError("audit output path is a symlink — refusing to write through it: %s"
                        % target_path)
    # Reject a HARDLINKED target (st_nlink > 1) — a pre-planted hardlink aliases an
    # OUTSIDE inode, so writing through it would modify a file outside state/audit/.
    # lstat does not follow links; the os.replace() below also breaks the alias, but
    # we refuse up front so the invariant violation is loud, not silent.
    if target_path.exists() and target_path.lstat().st_nlink > 1:
        raise RootError("audit output path is a hardlink alias (st_nlink>1) — "
                        "refusing to write through it: %s" % target_path)
    # Atomic write: a fresh temp file INSIDE the resolved audit dir, then os.replace()
    # onto the target. The replace rebinds the directory entry to a NEW inode, so any
    # pre-planted hardlink/alias at the target is severed (the old inode — and the
    # outside file it aliased — is left untouched). The temp lives in the contained
    # dir so the rename is same-filesystem (atomic) and never escapes containment.
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=".find-wasted-effort-", suffix=".tmp", dir=str(resolved_audit))
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(content)
            os.replace(str(tmp_path), str(target_path))
        except BaseException:
            # never leave a temp turd behind on any failure path
            try:
                tmp_path.unlink()
            except OSError:
                pass
            raise
        return str(target_path)
    except OSError as exc:
        return "(write failed: %s)" % exc


def write_report(root, report_path, report):
    """Write the .md report (Phase 1 surface, retained name) via write_audit_file."""
    return write_audit_file(root, report_path, report)


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
    ap.add_argument("--no-proposals-json", action="store_true",
                    help="skip the optional gitignored state/audit/ proposals JSON "
                         "sibling (the report section is always written)")
    # --root is an INTERNAL test hook only (the selftest's path-escape fixtures
    # need it). It is intentionally NOT advertised on the public command surface
    # (.claude/commands/find-wasted-effort.md). Suppressed from --help; still
    # subjected to resolve_root() + contained_audit_path() containment.
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
    report, counts, _, proposals = build_report(ev, root, today)
    try:
        report_path = contained_report_path(root, today)
        wrote = write_report(root, report_path, report)
        wrote_json = "(skipped)"
        if not args.no_proposals_json:
            # Optional gitignored JSON sibling — Phase 2A read-only-safe OUTPUT only.
            # Written through the SAME containment as the report (state/audit/ only).
            payload = json.dumps(
                {"date": today, "source": "find-wasted-effort",
                 "phase": "2A", "proposals": proposals},
                indent=2, sort_keys=True) + "\n"
            json_path = contained_proposals_path(root, today)
            wrote_json = write_audit_file(root, json_path, payload)
    except RootError as exc:
        print("[find-wasted-effort] ERROR: refusing to write — %s" % exc, file=sys.stderr)
        return 2

    print("[find-wasted-effort] artifacts: %d | rounds: %d | window: %d | report: %s" % (
        len(ev["artifacts"]), len(ev["rounds"]), args.window, wrote))
    print("[find-wasted-effort] confirmed %d · dismissed %d · inconclusive %d · proposals %d "
          "(candidates, not verdicts — see report header)" % (
              counts[CONFIRMED], counts[DISMISSED], counts[INCONCLUSIVE], len(proposals)))
    print("[find-wasted-effort] proposals JSON: %s" % wrote_json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
