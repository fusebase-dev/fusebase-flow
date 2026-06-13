#!/usr/bin/env python3
"""A2 find-wasted-effort — deterministic, stdlib-only, READ-ONLY ceremony audit.

Process-per-outcome sibling of token-waste-audit.py (FR-26). Different axis:
this reads Flow ARTIFACTS ON DISK (gate/deploy reports, handoffs, approval
artifacts, git log, prevents: annotations) and reports ceremony that bought no
safety OUTCOME. token-waste-audit reads transcripts for tokens-per-rule. Shared
discipline (reused, not duplicated): the candidate/false-positive header, the
read-only-first posture, the gitignored state/audit/<date>.md output convention.
Skill: flow-skills/find-wasted-effort/SKILL.md (+ references/rule-signatures.md).

READ-ONLY (Phase 1 / D4): writes ONLY its own report under state/audit/ (gitignored).
NO edits to memory/overlays/specs; NO prune/remove recommendations; NO lane
reclassification. Findings are review CANDIDATES — the PO owns subtraction
(policies/ratchet-governance.yml prune protocol). Writes/prune ship in Phase 2.

Each rule emits one verdict: confirmed | dismissed | inconclusive — with the
contrary evidence it searched for. A clean window is never proof a control is
worthless (catastrophic-low-frequency controls are expected to sit idle).

Usage: python hooks/local/find-wasted-effort.py [--window N] [--root PATH] [--selftest]
Exit 0 on a normal run (incl. an empty repo). --selftest exits non-zero on failure.
"""

import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_WINDOW = 20          # rounds/commits to consider
DUP_BLOCK_MIN = 3            # rule 3: verbatim block in >= N artifacts
UNUSED_GATE_MIN = 3          # rule 1: N rounds, every deviation approved
FULL_SUITE_MAX = 2           # rule 2: baseline + end is the non-waste norm

# Reused from token-economy substrate (token-waste-audit.py) — do not diverge.
FALSE_POSITIVE_HEADER = (
    "Findings below are review CANDIDATES that MAY indicate outcome-neutral "
    "ceremony — not verdicts, and never remove instructions (the PO owns "
    "subtraction; policies/ratchet-governance.yml). A clean observation window "
    "is NOT proof a control is waste: a gate stop can be low-frequency / "
    "high-severity (catastrophic-low-frequency). Each finding states the "
    "contrary evidence that dismisses it; absence of contrary evidence in a "
    "short window is INCONCLUSIVE, never confirmed. Known false-positive "
    "classes per rule: flow-skills/find-wasted-effort/references/"
    "false-positive-examples.md."
)

CONFIRMED, DISMISSED, INCONCLUSIVE = "confirmed", "dismissed", "inconclusive"

# Parse regex shared with policies/ratchet-governance.yml: annotation_marker.parse_regex
# Captures the comma-separated class list; terminates at the comment close, '#',
# em-dash (pointer note), or EOL. Inline per-class parentheticals / severity tags
# are stripped per-class below (PAREN_STRIP_RE).
PREVENTS_RE = re.compile(r"prevents:\s*([a-z0-9][a-z0-9 ,\-()/]*?)\s*(?:-->|#|—|$)")
PAREN_STRIP_RE = re.compile(r"\s*\([^)]*\)\s*")


def git_root(override=None):
    if override:
        return Path(override)
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


def git_log(root, n):
    """Return [(sha, subject)] for the last n commits; [] if git unavailable."""
    try:
        out = subprocess.run(
            ["git", "log", "-n", str(n), "--pretty=%H%x00%s"],
            capture_output=True, text=True, cwd=str(root), timeout=30,
        )
        if out.returncode != 0:
            return []
        rows = []
        for line in out.stdout.splitlines():
            if "\x00" in line:
                sha, subj = line.split("\x00", 1)
                rows.append((sha.strip(), subj.strip()))
        return rows
    except Exception:
        return []


def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


# --------------------------------------------------------------------------
# Evidence collection (read-only)
# --------------------------------------------------------------------------

def collect_prevents_annotations(root):
    """Map relative file -> set(incident-classes) from prevents: markers on disk."""
    found = {}
    scan_dirs = ["templates", "workflows"]
    for d in scan_dirs:
        base = root / d
        if not base.is_dir():
            continue
        for f in sorted(base.rglob("*.md")):
            classes = set()
            for line in read_text(f).splitlines():
                m = PREVENTS_RE.search(line)
                if m:
                    for c in m.group(1).split(","):
                        # strip inline parentheticals / severity tags, e.g.
                        # "(catastrophic-low-frequency)" or "(one task scope)"
                        c = PAREN_STRIP_RE.sub(" ", c).strip()
                        if c:
                            classes.add(c)
            if classes:
                found[str(f.relative_to(root))] = classes
    return found


def load_ratchet_governance(root):
    """Return (coverage_elements, parsed_ok). Minimal stdlib YAML-ish read of the
    coverage map; we only need element/file/severity lines, so a tolerant scan
    avoids a yaml dependency (stdlib-only constraint)."""
    path = root / "policies" / "ratchet-governance.yml"
    text = read_text(path)
    if not text:
        return [], False
    elements = []
    cur = {}
    in_annotated = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("annotated_elements:"):
            in_annotated = True
            continue
        if in_annotated and stripped.startswith("not_in_scope_phase1:"):
            break
        if not in_annotated:
            continue
        if stripped.startswith("- file:"):
            if cur:
                elements.append(cur)
            cur = {"file": stripped.split("file:", 1)[1].strip()}
        elif stripped.startswith("element:"):
            cur["element"] = stripped.split("element:", 1)[1].strip().strip('"')
        elif stripped.startswith("prevents:"):
            cur["prevents"] = stripped.split("prevents:", 1)[1].strip()
        elif stripped.startswith("severity:"):
            cur["severity"] = stripped.split("severity:", 1)[1].strip()
    if cur:
        elements.append(cur)
    return elements, True


def collect_artifacts(root):
    """Round artifacts to scan for duplication / lane signals: handoffs, gate &
    deploy reports, change-notes. Returns [(relpath, text)]."""
    out = []
    globs = [
        "docs/tmp/handoff/*.md",
        "docs/handoff/*.md",
        "docs/changes/*.md",
        "docs/specs/*/verification-gate.md",
    ]
    for g in globs:
        for f in sorted(root.glob(g)):
            if f.is_file():
                out.append((str(f.relative_to(root)), read_text(f)))
    return out


# --------------------------------------------------------------------------
# Per-rule evaluators — each returns a finding dict (extraction seam, FR-25)
# --------------------------------------------------------------------------

def finding(rule, verdict, summary, contrary):
    return {"rule": rule, "verdict": verdict, "summary": summary, "contrary": contrary}


def rule1_unused_gate_stops(ev):
    """Need recorded deviation/block outcomes to evaluate; absent => inconclusive."""
    blocks = ev["gate_blocks"]
    approvals = ev["gate_approvals"]
    if approvals == 0 and blocks == 0:
        return finding(1, INCONCLUSIVE,
                       "no recorded gate deviations in the window",
                       "needs >= %d rounds of recorded deviation outcomes" % UNUSED_GATE_MIN)
    if blocks > 0:
        return finding(1, DISMISSED,
                       "a gate blocked a deviation in the window (%d block(s))" % blocks,
                       "blocked-gate counterexample present — gate stops bought an outcome")
    if approvals >= UNUSED_GATE_MIN and blocks == 0:
        return finding(1, CONFIRMED,
                       "gate approved every deviation across %d round(s), none blocked" % approvals,
                       "searched for a blocked-gate counterexample; none found (review candidate, NOT auto-reclassify)")
    return finding(1, INCONCLUSIVE,
                   "only %d approved deviation(s); window < %d" % (approvals, UNUSED_GATE_MIN),
                   "window too small to confirm")


def rule2_per_commit_full_suite(ev):
    runs = ev["full_suite_runs_per_round"]
    if not runs:
        return finding(2, INCONCLUSIVE,
                       "full-suite run counts not recorded in artifacts",
                       "needs per-round suite-run counts + fail-sets")
    waste_rounds = [r for r, (n, identical) in runs.items() if n > FULL_SUITE_MAX and identical]
    info_rounds = [r for r, (n, identical) in runs.items() if not identical]
    if waste_rounds:
        return finding(2, CONFIRMED,
                       "rounds %s ran >%d identical full suites" % (sorted(waste_rounds), FULL_SUITE_MAX),
                       "no round in this set had a differing fail-set (suite caught nothing new)")
    if info_rounds:
        return finding(2, DISMISSED,
                       "full-suite fail-sets DIFFERED in rounds %s" % sorted(info_rounds),
                       "the suite caught a real mid-round regression — runs bought information")
    return finding(2, INCONCLUSIVE, "suite-run pattern within baseline+end norm", "no excess identical runs")


def rule3_artifact_duplication(ev):
    dups = ev["duplicate_blocks"]
    if not dups:
        return finding(3, INCONCLUSIVE, "no verbatim block reached the >=%d-artifact threshold" % DUP_BLOCK_MIN,
                       "no substantive block duplicated across >=%d artifacts" % DUP_BLOCK_MIN)
    # self-bootstrapping (role prelude / FP header / template scaffold) is dismissed
    real = [d for d in dups if not d["bootstrapping"]]
    boot = [d for d in dups if d["bootstrapping"]]
    if real:
        d = real[0]
        return finding(3, CONFIRMED,
                       "block duplicated verbatim across %d artifacts: %s" % (d["count"], d["files"]),
                       "searched for intentional self-bootstrapping; this block is substantive, not scaffold")
    if boot:
        return finding(3, DISMISSED,
                       "duplication is intentional self-bootstrapping (role-prelude / FP header / scaffold)",
                       "self-bootstrapping blocks are meant to be repeated so each artifact stands alone")
    return finding(3, INCONCLUSIVE, "near-duplicate blocks only (not verbatim)", "not verbatim across >=%d" % DUP_BLOCK_MIN)


def rule5_lane_misclassification(ev):
    cand = ev["lane_candidates"]
    if not cand:
        return finding(5, INCONCLUSIVE, "no small-diff + zero-decision + Full-ceremony round found",
                       "needs diff size + decision presence + lane tag per round")
    return finding(5, CONFIRMED if cand["clear"] else INCONCLUSIVE,
                   "round %s: small diff + zero design decisions but Full ceremony" % cand["round"],
                   "searched for a surfaced decision/risk; %s (review candidate, NEVER auto-reclassify)" %
                   ("none found" if cand["clear"] else "ambiguous size/risk -> inconclusive"))


def rule6_ratchet_inventory(ev):
    annotated = ev["annotated_files"]
    governance_ok = ev["governance_ok"]
    if not governance_ok:
        return finding(6, INCONCLUSIVE, "policies/ratchet-governance.yml absent or unparseable",
                       "A3 taxonomy/coverage map is the input for this rule")
    # In the read-only Phase-1 scope we report coverage health, not auto-removal.
    n_annotated = len(annotated)
    if n_annotated == 0:
        return finding(6, CONFIRMED, "no prevents: annotations found on disk",
                       "searched templates/ + workflows/ for prevents: markers; none present (review candidate)")
    return finding(6, DISMISSED,
                   "%d file(s) carry prevents: annotations governed by ratchet-governance.yml" % n_annotated,
                   "annotated controls are governed — not waste candidates; coverage stated in the report")


def rule7_watch_vs_read(ev):
    """Cross-session ceremony layer only. We can only flag re-derivation when a
    durable record exists; absent records are an observability gap (dismissed),
    NOT waste. Execution-layer polling is FR-26's axis — explicitly out of scope."""
    sig = ev["cross_session_rederivation"]
    if sig is None:
        return finding(7, INCONCLUSIVE,
                       "no cross-session re-derivation signal in the artifact window",
                       "scope: cross-session ceremony only; execution-layer polling is FR-26's axis (out of scope)")
    if sig["record_present"]:
        return finding(7, CONFIRMED,
                       "later session re-derived durable record %s" % sig["record"],
                       "the durable record existed and was re-derived anyway — point at the record")
    return finding(7, DISMISSED,
                   "re-derivation occurred but no durable record existed",
                   "absent record = a real observability gap, not waste")


RULE_EVALUATORS = [
    rule1_unused_gate_stops,
    rule2_per_commit_full_suite,
    rule3_artifact_duplication,
    rule5_lane_misclassification,
    rule6_ratchet_inventory,
    rule7_watch_vs_read,
]
RULE_TITLES = {
    1: "Unused gate stops",
    2: "Per-commit full-suite habit",
    3: "Artifact duplication",
    5: "Lane misclassification",
    6: "Ratchet inventory",
    7: "Watch-vs-read waste (cross-session ceremony layer only)",
}


# --------------------------------------------------------------------------
# Evidence assembly from a live repo (best-effort, read-only)
# --------------------------------------------------------------------------

def detect_duplicate_blocks(artifacts):
    """Verbatim multi-line blocks appearing in >= DUP_BLOCK_MIN artifacts.
    Block = a paragraph (>=120 chars) separated by blank lines. Self-bootstrapping
    markers downgrade a block to dismissed."""
    boot_markers = ("Role bootstrap", "Self-attest", FALSE_POSITIVE_HEADER[:40],
                    "Operating as", "Mode B (full)")
    para_files = {}
    for rel, text in artifacts:
        for para in re.split(r"\n\s*\n", text):
            p = para.strip()
            if len(p) >= 120:
                para_files.setdefault(p, set()).add(rel)
    dups = []
    for para, files in para_files.items():
        if len(files) >= DUP_BLOCK_MIN:
            bootstrapping = any(m in para for m in boot_markers)
            dups.append({"count": len(files), "files": sorted(files)[:5], "bootstrapping": bootstrapping})
    dups.sort(key=lambda d: -d["count"])
    return dups


def assemble_evidence(root, window):
    artifacts = collect_artifacts(root)
    annotations = collect_prevents_annotations(root)
    gov_elements, gov_ok = load_ratchet_governance(root)
    # Live repos rarely record gate deviation outcomes in a machine field; we
    # count only what is unambiguously present (so we degrade to inconclusive,
    # never to a false confirmed). Heuristic counts are conservative.
    gate_blocks = sum(t.lower().count("gate blocked") + t.lower().count("deviation rejected")
                      for _, t in artifacts)
    gate_approvals = sum(t.lower().count("approved per operator") for _, t in artifacts)
    return {
        "gate_blocks": gate_blocks,
        "gate_approvals": gate_approvals,
        "full_suite_runs_per_round": {},        # not machine-recorded on disk -> inconclusive
        "duplicate_blocks": detect_duplicate_blocks(artifacts),
        "lane_candidates": None,                # needs per-round diff+decision pairing -> inconclusive
        "annotated_files": annotations,
        "governance_ok": gov_ok,
        "governance_elements": gov_elements,
        "cross_session_rederivation": None,     # conservative -> inconclusive
        "artifacts": artifacts,
        "window": window,
    }


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def build_report(ev, root, today, commits):
    counts = {CONFIRMED: 0, DISMISSED: 0, INCONCLUSIVE: 0}
    findings = []
    for fn in RULE_EVALUATORS:
        f = fn(ev)
        counts[f["verdict"]] += 1
        findings.append(f)
    lines = [
        "# Find-wasted-effort audit — %s" % today, "",
        "Scope: %d artifact(s), window %d commit(s), git root `%s`." % (
            len(ev["artifacts"]), ev["window"], root),
        "Read-only (Phase 1 / D4): no writes/prune/reclassify; this report is the only output.",
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
    # Coverage section (mandatory — silence is not safety, D5)
    lines += ["## Coverage (D5 — silence is not safety)", ""]
    if ev["governance_ok"]:
        lines.append("ratchet-governance.yml parsed: %d annotated control(s) in the coverage map." %
                     len(ev["governance_elements"]))
        lines.append("")
        lines.append("| File | Element | prevents | severity |")
        lines.append("|---|---|---|---|")
        for el in ev["governance_elements"]:
            lines.append("| %s | %s | %s | %s |" % (
                el.get("file", "?"), el.get("element", "?"),
                el.get("prevents", "?"), el.get("severity", "—")))
        lines.append("")
        lines.append("prevents: markers found on disk in %d file(s): %s" % (
            len(ev["annotated_files"]), ", ".join(sorted(ev["annotated_files"])) or "none"))
    else:
        lines.append("policies/ratchet-governance.yml absent/unparseable — coverage cannot be stated "
                     "(rule 6 inconclusive). This is a coverage GAP, not a safety verdict.")
    lines += ["", "## Totals", "",
              "confirmed %d · dismissed %d · inconclusive %d" % (
                  counts[CONFIRMED], counts[DISMISSED], counts[INCONCLUSIVE]),
              "", "Findings are review candidates. The PO owns subtraction "
              "(policies/ratchet-governance.yml prune protocol); writes/prune ship in Phase 2.", ""]
    return "\n".join(lines), counts, findings


def write_report(root, today, report):
    report_path = root / "state" / "audit" / ("find-wasted-effort-%s.md" % today)
    try:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(report, encoding="utf-8", newline="\n")
        return str(report_path)
    except OSError as exc:
        return "(write failed: %s)" % exc


# --------------------------------------------------------------------------
# Self-test (gate analyzer-unit row) — synthetic inputs -> expected verdicts
# --------------------------------------------------------------------------

def _base_ev():
    return {
        "gate_blocks": 0, "gate_approvals": 0,
        "full_suite_runs_per_round": {}, "duplicate_blocks": [],
        "lane_candidates": None, "annotated_files": {}, "governance_ok": True,
        "governance_elements": [], "cross_session_rederivation": None,
        "artifacts": [], "window": DEFAULT_WINDOW,
    }


def selftest():
    cases = []

    def check(name, fn, ev, want):
        got = fn(ev)["verdict"]
        ok = got == want
        cases.append((ok, name, want, got))

    # Rule 1
    ev = _base_ev(); ev["gate_approvals"] = 4
    check("r1 confirmed (4 approvals, 0 blocks)", rule1_unused_gate_stops, ev, CONFIRMED)
    ev = _base_ev(); ev["gate_approvals"] = 4; ev["gate_blocks"] = 1
    check("r1 dismissed (a block present)", rule1_unused_gate_stops, ev, DISMISSED)
    ev = _base_ev(); ev["gate_approvals"] = 1
    check("r1 inconclusive (window < min)", rule1_unused_gate_stops, ev, INCONCLUSIVE)

    # Rule 2
    ev = _base_ev(); ev["full_suite_runs_per_round"] = {"R1": (5, True)}
    check("r2 confirmed (5 identical runs)", rule2_per_commit_full_suite, ev, CONFIRMED)
    ev = _base_ev(); ev["full_suite_runs_per_round"] = {"R1": (5, False)}
    check("r2 dismissed (fail-set differed)", rule2_per_commit_full_suite, ev, DISMISSED)
    ev = _base_ev()
    check("r2 inconclusive (no counts)", rule2_per_commit_full_suite, ev, INCONCLUSIVE)

    # Rule 3
    ev = _base_ev(); ev["duplicate_blocks"] = [{"count": 4, "files": ["a", "b", "c", "d"], "bootstrapping": False}]
    check("r3 confirmed (substantive dup)", rule3_artifact_duplication, ev, CONFIRMED)
    ev = _base_ev(); ev["duplicate_blocks"] = [{"count": 4, "files": ["a", "b", "c", "d"], "bootstrapping": True}]
    check("r3 dismissed (self-bootstrapping)", rule3_artifact_duplication, ev, DISMISSED)
    ev = _base_ev()
    check("r3 inconclusive (no dup)", rule3_artifact_duplication, ev, INCONCLUSIVE)

    # Rule 5
    ev = _base_ev(); ev["lane_candidates"] = {"round": "R7", "clear": True}
    check("r5 confirmed (small+0-decision+Full)", rule5_lane_misclassification, ev, CONFIRMED)
    ev = _base_ev(); ev["lane_candidates"] = {"round": "R7", "clear": False}
    check("r5 inconclusive (ambiguous)", rule5_lane_misclassification, ev, INCONCLUSIVE)
    ev = _base_ev()
    check("r5 inconclusive (no candidate)", rule5_lane_misclassification, ev, INCONCLUSIVE)

    # Rule 6
    ev = _base_ev(); ev["annotated_files"] = {"templates/handoff-deploy.md": {"unattended-prod-cutover"}}
    check("r6 dismissed (annotations present)", rule6_ratchet_inventory, ev, DISMISSED)
    ev = _base_ev(); ev["annotated_files"] = {}
    check("r6 confirmed (no annotations)", rule6_ratchet_inventory, ev, CONFIRMED)
    ev = _base_ev(); ev["governance_ok"] = False
    check("r6 inconclusive (no governance file)", rule6_ratchet_inventory, ev, INCONCLUSIVE)

    # Rule 7
    ev = _base_ev(); ev["cross_session_rederivation"] = {"record_present": True, "record": "deploy-hash"}
    check("r7 confirmed (re-derived present record)", rule7_watch_vs_read, ev, CONFIRMED)
    ev = _base_ev(); ev["cross_session_rederivation"] = {"record_present": False, "record": "x"}
    check("r7 dismissed (observability gap)", rule7_watch_vs_read, ev, DISMISSED)
    ev = _base_ev()
    check("r7 inconclusive (no signal)", rule7_watch_vs_read, ev, INCONCLUSIVE)

    # prevents: parser fixtures (the annotation forms used on disk)
    def parse_line(line):
        out = set()
        m = PREVENTS_RE.search(line)
        if m:
            for c in m.group(1).split(","):
                c = PAREN_STRIP_RE.sub(" ", c).strip()
                if c:
                    out.add(c)
        return out

    parse_cases = [
        ("single + severity tag",
         "<!-- prevents: unattended-prod-cutover (catastrophic-low-frequency) -->",
         {"unattended-prod-cutover"}),
        ("single + em-dash pointer",
         "STOP. <!-- prevents: silent-protected-path-drift — taxonomy: x -->",
         {"silent-protected-path-drift"}),
        ("multi-class",
         "<!-- prevents: false-green-deploy, unauthorized-deploy — taxonomy: x (A3) -->",
         {"false-green-deploy", "unauthorized-deploy"}),
        ("multi-class with inline parentheticals",
         "<!-- prevents: broken-main (lint/typecheck), regression-attribution-loss (one task scope), "
         "silent-protected-path-drift (worker-undisturbed) — taxonomy: x -->",
         {"broken-main", "regression-attribution-loss", "silent-protected-path-drift"}),
        ("no marker", "## Rollback procedure", set()),
    ]
    for name, line, want in parse_cases:
        got = parse_line(line)
        cases.append((got == want, "parse: " + name, sorted(want), sorted(got)))

    failures = [c for c in cases if not c[0]]
    for ok, name, want, got in cases:
        print("  %s %s (want=%s got=%s)" % ("PASS" if ok else "FAIL", name, want, got))
    print("[find-wasted-effort --selftest] %d/%d passed" % (len(cases) - len(failures), len(cases)))
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser(
        description="A2 find-wasted-effort — read-only ceremony audit (deterministic, stdlib-only)")
    ap.add_argument("--window", type=int, default=DEFAULT_WINDOW, metavar="N",
                    help="commit/round window to consider (default %d)" % DEFAULT_WINDOW)
    ap.add_argument("--root", default=None, metavar="PATH",
                    help="repo root override (default: git toplevel)")
    ap.add_argument("--selftest", action="store_true",
                    help="run synthetic per-rule fixtures and exit (no repo read, no report write)")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    root = git_root(args.root)
    today = datetime.date.today().isoformat()
    commits = git_log(root, args.window)
    ev = assemble_evidence(root, args.window)
    report, counts, _ = build_report(ev, root, today, commits)
    wrote = write_report(root, today, report)

    print("[find-wasted-effort] artifacts: %d | window: %d | report: %s" % (
        len(ev["artifacts"]), args.window, wrote))
    print("[find-wasted-effort] confirmed %d · dismissed %d · inconclusive %d "
          "(candidates, not verdicts — see report header)" % (
              counts[CONFIRMED], counts[DISMISSED], counts[INCONCLUSIVE]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
