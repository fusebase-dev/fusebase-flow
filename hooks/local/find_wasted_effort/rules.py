"""Per-rule evaluators for find-wasted-effort. Each evaluator consumes the
evidence dict and returns a finding dict. Verdict vocabulary (every rule emits
exactly one): confirmed | dismissed | inconclusive — with the contrary evidence
it searched for. Per-rule contract: flow-skills/find-wasted-effort/references/
rule-signatures.md.

BLOCKER-1 honesty: when a rule's input is genuinely unavailable, the evidence
carries a `*_reason` string and the rule returns `inconclusive` WITH that reason
(never a hard-coded empty masquerading as a real verdict).

Read-only — none of these write, prune, or reclassify.
"""

from .constants import (
    CONFIRMED, DISMISSED, INCONCLUSIVE,
    UNUSED_GATE_MIN, FULL_SUITE_MAX,
)


def finding(rule, verdict, summary, contrary, elements=None):
    f = {"rule": rule, "verdict": verdict, "summary": summary, "contrary": contrary}
    if elements is not None:
        f["elements"] = elements
    return f


def rule1_unused_gate_stops(ev):
    """Rule 1 — unused gate stops. Needs recorded deviation/block outcomes.

    Contrary evidence is TWO-sourced: a recorded gate BLOCK in the artifacts, OR a
    deviation-gating APPROVAL artifact on disk (state/approvals/) whose kind gated
    a real deviation from a default (protected_path_edit, database_migration, …).
    Either one shows a gate stop bought a real outcome and dismisses the rule —
    routine-deploy approvals are excluded (they are the happy path, not a deviation
    the gate had to stop and authorize)."""
    blocks = ev["gate_blocks"]
    approvals = ev["gate_approvals"]
    gating = ev.get("gating_approvals", [])
    if approvals == 0 and blocks == 0 and not gating:
        return finding(1, INCONCLUSIVE,
                       "no recorded gate deviation outcomes in the window",
                       "needs >= %d rounds of recorded approve/block outcomes" % UNUSED_GATE_MIN)
    if blocks > 0:
        return finding(1, DISMISSED,
                       "a gate blocked a deviation in the window (%d block(s))" % blocks,
                       "blocked-gate counterexample present — gate stops bought an outcome")
    if gating:
        kinds = sorted({a["kind"] for a in gating})
        return finding(1, DISMISSED,
                       "a deviation-gating approval gated a real deviation in the window "
                       "(%d artifact(s): %s)" % (len(gating), kinds),
                       "approval-artifact counterexample present — a gate required an explicit "
                       "operator decision to authorize a deviation (it bought an outcome)")
    if approvals >= UNUSED_GATE_MIN and blocks == 0:
        return finding(1, CONFIRMED,
                       "gate approved every deviation across %d round(s), none blocked" % approvals,
                       "searched for a blocked-gate counterexample AND a deviation-gating approval; "
                       "none found (review candidate, NOT auto-reclassify)")
    return finding(1, INCONCLUSIVE,
                   "only %d approved deviation(s); window < %d" % (approvals, UNUSED_GATE_MIN),
                   "window too small to confirm")


def rule2_per_commit_full_suite(ev):
    """Rule 2 — per-commit full-suite habit. Input wired to suite-run traces parsed
    from gate/deploy reports + handoffs (collect_suite_runs).

    A CONFIRM requires real fail-set evidence: runs > baseline+end AND fail-sets
    recorded for every run AND those fail-sets identical (HIGH finding /
    rule-signatures.md:20-25). Run counts present but fail-sets NOT recorded ->
    inconclusive, never confirmed."""
    runs = ev["full_suite_runs_per_round"]
    if not runs:
        reason = ev.get("full_suite_reason") or "full-suite run counts not recorded in artifacts"
        return finding(2, INCONCLUSIVE,
                       "full-suite run pattern not derivable: %s" % reason,
                       "needs per-round suite-run counts + fail-sets in reports")
    # Confirm ONLY when fail-sets were completely recorded AND identical.
    waste_rounds = [r for r, (n, identical, complete) in runs.items()
                    if n > FULL_SUITE_MAX and identical and complete]
    # A real mid-round regression (fail-set differed) dismisses — but only when the
    # fail-set evidence is actually present to show the difference.
    info_rounds = [r for r, (n, identical, complete) in runs.items()
                   if complete and not identical]
    # Run counts above the norm but with missing/partial fail-sets: the suite-run
    # pattern is suspicious but unproven -> honest inconclusive (no false confirm).
    unrecorded_rounds = [r for r, (n, identical, complete) in runs.items()
                         if n > FULL_SUITE_MAX and not complete]
    if waste_rounds:
        return finding(2, CONFIRMED,
                       "rounds %s ran >%d identical full suites" % (sorted(waste_rounds), FULL_SUITE_MAX),
                       "no round in this set had a differing fail-set (suite caught nothing new); "
                       "every run had a recorded fail-set")
    if info_rounds:
        return finding(2, DISMISSED,
                       "full-suite fail-sets DIFFERED in rounds %s" % sorted(info_rounds),
                       "the suite caught a real mid-round regression — runs bought information")
    if unrecorded_rounds:
        return finding(2, INCONCLUSIVE,
                       "rounds %s ran >%d full suites but fail-sets were not fully recorded"
                       % (sorted(unrecorded_rounds), FULL_SUITE_MAX),
                       "run counts present, fail-sets missing/partial — cannot prove identical "
                       "fail-sets (rule-signatures.md:20-25); needs a recorded fail-set per run")
    return finding(2, INCONCLUSIVE, "suite-run pattern within baseline+end norm",
                   "no excess identical runs")


def rule3_artifact_duplication(ev):
    """Rule 3 — verbatim artifact duplication across >= DUP_BLOCK_MIN artifacts."""
    dups = ev["duplicate_blocks"]
    from .constants import DUP_BLOCK_MIN
    if not dups:
        return finding(3, INCONCLUSIVE,
                       "no verbatim block reached the >=%d-artifact threshold" % DUP_BLOCK_MIN,
                       "no substantive block duplicated across >=%d artifacts" % DUP_BLOCK_MIN)
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
    return finding(3, INCONCLUSIVE, "near-duplicate blocks only (not verbatim)",
                   "not verbatim across >=%d" % DUP_BLOCK_MIN)


def rule5_lane_misclassification(ev):
    """Rule 5 — lane misclassification. Input wired to per-round diff size (git
    numstat) paired with decision presence + lane signal (collect_lane_candidates)."""
    cand = ev["lane_candidates"]
    if not cand:
        reason = ev.get("lane_reason") or "no qualifying round found"
        return finding(5, INCONCLUSIVE,
                       "lane misclassification not derivable: %s" % reason,
                       "needs diff size + decision presence + lane tag paired per round")
    return finding(5, CONFIRMED if cand["clear"] else INCONCLUSIVE,
                   "round %s: %d file(s)/%d net line(s), zero design decisions, Full ceremony"
                   % (cand["round"], cand.get("files", 0), cand.get("lines", 0)),
                   "searched for a surfaced decision/risk; %s (review candidate, NEVER auto-reclassify)" %
                   ("none found" if cand["clear"] else "ambiguous size/risk -> inconclusive"))


def rule6_ratchet_inventory(ev):
    """Rule 6 — ratchet inventory, PER-ELEMENT (BLOCKER 2).

    Contract (references/rule-signatures.md:52 + ratchet-governance.yml prune guard):
    for EACH coverage.annotated_elements entry, compare its declared `prevents:`
    against the actual on-disk marker for that file, scan firing evidence, honor
    `catastrophic-low-frequency`, and emit a per-element verdict. NEVER 'remove' —
    only a review candidate. The roll-up verdict is the worst per-element verdict
    (any confirmed -> confirmed; else any inconclusive -> inconclusive; else dismissed).
    """
    governance_ok = ev["governance_ok"]
    if not governance_ok:
        return finding(6, INCONCLUSIVE,
                       "policies/ratchet-governance.yml absent or unparseable",
                       "A3 taxonomy/coverage map is the input for this rule",
                       elements=[])
    gov_elements = ev["governance_elements"]
    annotated_classes = ev["annotated_files"]      # relpath -> set(classes)
    fired = ev.get("fired_classes", set())
    severity_tag = ev.get("severity_tag", "catastrophic-low-frequency")

    per_element = []
    for el in gov_elements:
        fpath = el.get("file", "?")
        ename = el.get("element", "?")
        declared = [c for c in el.get("prevents", []) if c]
        on_disk = annotated_classes.get(fpath, set())
        sev = (el.get("severity") or "").strip()
        is_catastrophic = (sev == severity_tag) or any(
            "catastrophic" in (c or "") for c in declared)
        declared_set = set(declared)
        # does the on-disk marker actually carry this element's declared classes?
        marker_present = bool(declared_set & on_disk) if declared_set else False
        class_fired = bool(declared_set & fired)

        if class_fired:
            verdict = DISMISSED
            why = "control fired in the window (class %s) — bought a real outcome" % \
                  sorted(declared_set & fired)
        elif not declared_set:
            # an element in the coverage map with NO declared prevents == review candidate
            verdict = CONFIRMED
            why = "no prevents: class declared and no firing in the window — review candidate (NOT remove)"
        elif not marker_present:
            # declared in the map but the on-disk marker is missing/divergent: a
            # coverage GAP, reported as inconclusive (not a safety verdict).
            verdict = INCONCLUSIVE
            why = ("declared prevents: %s but no matching on-disk marker in %s — coverage GAP, "
                   "not a waste verdict" % (sorted(declared_set), fpath))
        elif is_catastrophic:
            verdict = INCONCLUSIVE
            why = "catastrophic-low-frequency control on a clean window (expected idle) — never confirmed"
        else:
            verdict = DISMISSED
            why = "carries prevents: %s (governed) — not a waste candidate" % sorted(declared_set)

        per_element.append({"file": fpath, "element": ename, "verdict": verdict,
                            "prevents": sorted(declared_set), "why": why,
                            "catastrophic": is_catastrophic})

    # coverage gaps: on-disk prevents-marked files NOT in the coverage map at all
    covered_files = {el.get("file") for el in gov_elements}
    for relpath in sorted(annotated_classes):
        if relpath not in covered_files:
            per_element.append({"file": relpath, "element": "(on-disk marker outside coverage map)",
                                "verdict": INCONCLUSIVE, "prevents": sorted(annotated_classes[relpath]),
                                "why": "marked on disk but not in ratchet-governance.yml coverage map — coverage GAP",
                                "catastrophic": False})

    if not per_element:
        return finding(6, INCONCLUSIVE,
                       "ratchet-governance.yml parsed but no annotated_elements in the coverage map",
                       "coverage map is empty — nothing to inventory", elements=[])

    verdicts = [e["verdict"] for e in per_element]
    n_conf = verdicts.count(CONFIRMED)
    n_inc = verdicts.count(INCONCLUSIVE)
    n_dis = verdicts.count(DISMISSED)
    if n_conf:
        roll = CONFIRMED
        summary = ("%d element(s) un-annotated + non-firing — review candidate(s), NOT remove "
                   "(%d governed/fired, %d coverage-gap/idle)" % (n_conf, n_dis, n_inc))
    elif n_inc:
        roll = INCONCLUSIVE
        summary = ("%d element(s) inconclusive (catastrophic-low-frequency idle or coverage gap); "
                   "%d governed/fired, 0 confirmed waste" % (n_inc, n_dis))
    else:
        roll = DISMISSED
        summary = "all %d coverage element(s) governed or fired — none a waste candidate" % n_dis
    contrary = ("per-element: a prevents: marker present OR a firing in the window dismisses; "
                "a catastrophic-low-frequency idle control is inconclusive, never confirmed; "
                "output is a review candidate, never 'remove'")
    return finding(6, roll, summary, contrary, elements=per_element)


def rule7_watch_vs_read(ev):
    """Rule 7 — watch-vs-read waste, CROSS-SESSION ceremony layer ONLY. Input wired
    to cross-session deploy-hash re-derivation (collect_cross_session_rederivation).
    Execution-layer polling is FR-26's axis and is explicitly out of scope here."""
    sig = ev["cross_session_rederivation"]
    if sig is None:
        reason = ev.get("cross_session_reason") or \
            "no cross-session re-derivation signal in the artifact window"
        return finding(7, INCONCLUSIVE,
                       "cross-session re-derivation not derivable: %s" % reason,
                       "scope: cross-session ceremony only; execution-layer polling is FR-26's axis (out of scope)")
    if sig["record_present"]:
        return finding(7, CONFIRMED,
                       "later artifact(s) re-derived durable %s across %s"
                       % (sig["record"], sig.get("sessions", "?")),
                       "the durable record existed and was re-stated anyway — point at the record")
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
