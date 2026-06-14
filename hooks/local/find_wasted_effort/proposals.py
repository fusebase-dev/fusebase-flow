"""Phase 2A proposal output (read-only-safe) for find-wasted-effort.

Turns audit FINDINGS into PROPOSALS — changes a HUMAN could apply, never ones the
audit applies. The analyzer stays read-only to the project (D4 / Phase 2A): these
proposals are rendered into the contained state/audit/ report and an optional
gitignored sibling JSON, and NOWHERE else. The actual write-apply is Phase 2B
(DEFERRED, consumer-repo, AC2b).

Emission contract (T24):
  - a `confirmed` finding (rules 1,2,3,5,7) -> exactly one proposal recording the
    recommendation (lane reclassification review, baseline+end suite policy, ...);
  - a rule-6 per-element REVIEW CANDIDATE -> a `prune_review_candidate` proposal
    (NEVER an auto-prune / recorded-prune decision — PO owns subtraction);
  - `inconclusive` / `dismissed` findings -> NO proposal.

Self-output quarantine (Codex #5): every raw_evidence_refs entry points at a RAW
on-disk artifact (a gate/deploy report, handoff, approval, the ratchet-governance
coverage map, a git round). It NEVER points at a prior audit report/proposal — the
evidence collectors do not read state/audit/, so the audit cannot cite itself.

stdlib-only. No writes (the CLI orchestrator owns the contained state/audit/ write).
"""

import hashlib

from .constants import (
    CONFIRMED,
    PROPOSAL_SOURCE,
    PRUNE_REVIEW_CANDIDATE,
)


def _proposal_id(rule, verdict_kind, target_path, evidence_refs):
    """Stable id: rule + verdict-kind + a short hash of (target + sorted evidence).
    Deterministic so golden fixtures can assert it; collision-resistant enough to
    disambiguate two proposals of the same rule/verdict against different targets."""
    basis = "%s|%s" % (target_path or "", "|".join(sorted(evidence_refs or [])))
    short = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:8]
    return "%s-%s-%s" % (rule, verdict_kind, short)


def _proposal(rule, verdict, target_kind, target_path, exact_patch, evidence_refs,
              verdict_kind=None):
    """Construct one proposal dict in the defined schema. operator_confirmation_required
    is ALWAYS True and source is ALWAYS 'audit' (the read-only-safe invariants)."""
    vk = verdict_kind or verdict
    refs = sorted(set(evidence_refs or []))
    return {
        "proposal_id": _proposal_id(rule, vk, target_path, refs),
        "rule": rule,
        "verdict": verdict,
        "raw_evidence_refs": refs,
        "target_kind": target_kind,
        "target_path": target_path,
        "exact_patch": exact_patch,
        "operator_confirmation_required": True,
        "source": PROPOSAL_SOURCE,
    }


# --------------------------------------------------------------------------
# raw-evidence reference assembly (self-output quarantine, Codex #5)
#
# Each rule's proposal cites the RAW on-disk artifacts the finding rested on. We
# pull those from the evidence dict (collected from disk, never from state/audit/).
# --------------------------------------------------------------------------

def _recorded_report_refs(ev):
    """Relpaths of the recorded gate/deploy reports the outcome collectors scanned
    (rule 1 / rule 6 firing evidence basis). Raw artifacts only."""
    from .evidence import artifact_kind, RECORDED_REPORT_KINDS
    return [rel for rel, text in ev.get("artifacts", [])
            if artifact_kind(rel, text) in RECORDED_REPORT_KINDS]


def _round_artifact_refs(ev, round_id):
    """Relpaths of the raw artifacts whose slug matches a given round id (rule 2 /
    rule 5 basis). Raw artifacts only — never an audit report."""
    from .evidence import artifact_slug
    return [rel for rel, _ in ev.get("artifacts", []) if artifact_slug(rel) == round_id]


def _governance_ref():
    return ["policies/ratchet-governance.yml"]


# --------------------------------------------------------------------------
# per-rule proposal builders (only fired on a CONFIRMED finding, except rule 6)
# --------------------------------------------------------------------------

def _from_rule1(ev, f):
    refs = _recorded_report_refs(ev) or ["state/approvals/"]
    return _proposal(
        1, CONFIRMED,
        target_kind="lane-eligibility-review",
        target_path="(operator decision — never auto-reclassify)",
        exact_patch=("Review gate-class for Middle-lane eligibility: %s. "
                     "Suggestion is eligibility-for-review only; the PO classifies "
                     "the lane (FR-21). No file is edited by the audit." % f["summary"]),
        evidence_refs=refs)


def _from_rule2(ev, f):
    # rule 2 summary names the wasteful rounds; cite their raw round artifacts.
    refs = []
    runs = ev.get("full_suite_runs_per_round", {}) or {}
    for rid in runs:
        refs += _round_artifact_refs(ev, rid)
    return _proposal(
        2, CONFIRMED,
        target_kind="suite-run-policy",
        target_path="(round-file / workflow guidance — operator decision)",
        exact_patch=("Adopt a baseline+end full-suite policy for the affected "
                     "round(s): %s. Scoped per-commit gates instead of a full suite "
                     "every commit. No file is edited by the audit." % f["summary"]),
        evidence_refs=refs)


def _from_rule3(ev, f):
    refs = sorted({rel for rel, _ in ev.get("artifacts", [])})
    return _proposal(
        3, CONFIRMED,
        target_kind="artifact-dedup",
        target_path="(operator decision — pointer-ize the duplicated block)",
        exact_patch=("Replace the verbatim-duplicated block with a pointer + a "
                     "round-file shape: %s. No file is edited by the audit." % f["summary"]),
        evidence_refs=refs)


def _from_rule5(ev, f):
    cand = ev.get("lane_candidates") or {}
    rid = cand.get("round")
    refs = _round_artifact_refs(ev, rid) if rid else []
    return _proposal(
        5, CONFIRMED,
        target_kind="lane-reclassification-review",
        target_path="(operator decision — NEVER auto-reclassify)",
        exact_patch=("Review this round for Lightweight/Middle classification: %s. "
                     "The PO owns lane classification (FR-21); the audit never "
                     "reclassifies. No file is edited by the audit." % f["summary"]),
        evidence_refs=refs)


def _from_rule7(ev, f):
    sig = ev.get("cross_session_rederivation") or {}
    refs = sorted(set(sig.get("sessions", []) or []))
    return _proposal(
        7, CONFIRMED,
        target_kind="cross-session-pointer",
        target_path="(operator decision — point later artifacts at the record)",
        exact_patch=("Point the later artifact(s) at the existing durable record "
                     "instead of re-deriving it: %s. No file is edited by the "
                     "audit." % f["summary"]),
        evidence_refs=refs)


_CONFIRMED_BUILDERS = {
    1: _from_rule1,
    2: _from_rule2,
    3: _from_rule3,
    5: _from_rule5,
    7: _from_rule7,
}


def _from_rule6(ev, f):
    """Rule 6 -> one prune_review_candidate proposal PER per-element review
    candidate. ONLY elements whose per-element verdict is CONFIRMED (un-annotated +
    non-firing) become a candidate. Catastrophic-idle / coverage-gap (inconclusive)
    and governed/fired (dismissed) elements emit NOTHING.

    NEVER an auto-prune or a recorded prune decision — the verdict label is
    `prune_review_candidate` and operator_confirmation_required stays True. PO owns
    subtraction (policies/ratchet-governance.yml prune protocol)."""
    out = []
    for el in f.get("elements", []) or []:
        if el.get("verdict") != CONFIRMED:
            continue
        target_path = el.get("file") or "(coverage map)"
        evidence_refs = _governance_ref() + ([target_path] if el.get("file") else [])
        out.append(_proposal(
            6, PRUNE_REVIEW_CANDIDATE,
            target_kind="ratchet-prune-review",
            target_path="(PO subtraction decision — never auto-prune)",
            exact_patch=("REVIEW CANDIDATE (not a prune): element '%s' in %s carries "
                         "no prevents: class and did not fire in the window. Removal "
                         "needs a named incident-class, severity, window, negative "
                         "examples, and operator confirmation per "
                         "policies/ratchet-governance.yml. The audit proposes review "
                         "ONLY; it never prunes." % (el.get("element", "?"), target_path)),
            evidence_refs=evidence_refs,
            verdict_kind=PRUNE_REVIEW_CANDIDATE))
    return out


def build_proposals(ev, findings):
    """Derive the proposal list from the audit findings.

    confirmed (rules 1,2,3,5,7) -> one proposal each; rule 6 -> one
    prune_review_candidate per per-element review candidate; inconclusive/dismissed
    -> none. Deterministic order: by rule number, then proposal_id."""
    proposals = []
    for f in findings:
        rule = f.get("rule")
        if rule == 6:
            proposals.extend(_from_rule6(ev, f))
            continue
        if f.get("verdict") != CONFIRMED:
            continue
        builder = _CONFIRMED_BUILDERS.get(rule)
        if builder:
            proposals.append(builder(ev, f))
    proposals.sort(key=lambda p: (p["rule"], p["proposal_id"]))
    return proposals
