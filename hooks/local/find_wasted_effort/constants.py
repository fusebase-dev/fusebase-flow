"""Shared constants + the prevents:-marker parse regex (single source of truth
for the find-wasted-effort analyzer). The regex is kept byte-identical to
policies/ratchet-governance.yml: annotation_marker.parse_regex so the analyzer
and the policy describe the same grammar (FR-22: the WHY lives in the taxonomy,
the marker is the retrieval pointer)."""

import re

DEFAULT_WINDOW = 20          # rounds/commits to consider
DUP_BLOCK_MIN = 3            # rule 3: verbatim block in >= N artifacts
UNUSED_GATE_MIN = 3          # rule 1: N rounds, every deviation approved
FULL_SUITE_MAX = 2           # rule 2: baseline + end is the non-waste norm

# Rule 1 contrary-evidence: approval KINDS that gate a real DEVIATION from a
# default (the operator had to make an explicit call to authorize stepping around
# a rule). One on disk in the window is a counterexample that dismisses rule 1 — a
# gate bought a real outcome.
#
# Derivation (LOW fix): every member MUST be a real `require_approval` kind in
# policies/approval-policy.yml. `direct_to_main` is a workflow MODE (workflow_mode:
# direct_to_main | branch_pr), NOT an approval kind — it was a false member that
# could falsely dismiss rule 1, so it is REMOVED. The routine-deploy kinds
# (production_deploy, lightweight_deploy, middle_deploy) ARE require_approval kinds
# but are the happy path itself, NOT a deviation a gate had to stop and authorize,
# so they are EXCLUDED here. What remains = the deviation-gating require_approval
# kinds. ROUTINE_DEPLOY_KINDS documents the deliberate exclusions.
ROUTINE_DEPLOY_KINDS = frozenset({
    "production_deploy",
    "lightweight_deploy",
    "middle_deploy",
})
DEVIATION_GATING_APPROVALS = frozenset({
    "protected_path_edit",
    "database_migration",
    "auth_or_permission_change",
    "secret_file_write",
    "destructive_file_delete",
    "external_customer_visible_message",
    "session_key_or_cookie_use",
})

CONFIRMED, DISMISSED, INCONCLUSIVE = "confirmed", "dismissed", "inconclusive"

# --------------------------------------------------------------------------
# Phase 2A proposal schema (read-only-safe — OUTPUT only, no write-apply)
# --------------------------------------------------------------------------
# A proposal is a change a HUMAN could apply — never one the audit applies. The
# analyzer stays read-only to the project (Phase 2A / D4): proposals are emitted
# only into the contained state/audit/ report + an optional gitignored sibling
# JSON. The actual write-apply is Phase 2B (DEFERRED, consumer-repo, AC2b).
# Fields (the defined schema — T24):
#   proposal_id   stable id: "<rule>-<verdict-kind>-<short-hash-of-target+evidence>"
#   rule          source rule number (1,2,3,5,6,7)
#   verdict       the source finding's verdict (always "confirmed" — or rule-6
#                 "prune_review_candidate"; inconclusive/dismissed emit none)
#   raw_evidence_refs  pointers to RAW on-disk artifacts that justify it — NEVER a
#                 prior audit report/proposal (self-output quarantine, Codex #5)
#   target_kind   what a human would change (policy/lane/memory/template/...)
#   target_path   the on-disk file a human could edit (or "(operator decision)")
#   exact_patch   the concrete change text a human COULD apply (description, not an
#                 applied diff — Phase 2A emits, never applies)
#   operator_confirmation_required  ALWAYS True (PO owns subtraction)
#   source        ALWAYS "audit"
PROPOSAL_SOURCE = "audit"
# Rule-6 review-candidate proposals carry this verdict label (NEVER an auto-prune
# or a recorded prune decision — PO owns subtraction; policies/ratchet-governance.yml).
PRUNE_REVIEW_CANDIDATE = "prune_review_candidate"
# The only verdict that yields a proposal from a NON-rule-6 finding. rule 6 yields
# proposals from its per-element review candidates (see proposals.py).
PROPOSAL_FROM_VERDICT = CONFIRMED

# Reused from the token-economy substrate (token-waste-audit.py) — do not diverge.
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

# Parse regex shared with policies/ratchet-governance.yml: annotation_marker.parse_regex
# Captures the comma-separated class list; terminates at the comment close, '#',
# em-dash (pointer note), or EOL. Inline per-class parentheticals / severity tags
# are stripped per-class by PAREN_STRIP_RE.
PREVENTS_RE = re.compile(r"prevents:\s*([a-z0-9][a-z0-9 ,\-()/]*?)\s*(?:-->|#|—|$)")
PAREN_STRIP_RE = re.compile(r"\s*\([^)]*\)\s*")


def parse_prevents_classes(line):
    """Return the set of incident-classes named by a `prevents:` marker on `line`
    (empty set if none). Per-class parentheticals / severity tags are stripped."""
    out = set()
    m = PREVENTS_RE.search(line)
    if m:
        for c in m.group(1).split(","):
            c = PAREN_STRIP_RE.sub(" ", c).strip()
            if c:
                out.add(c)
    return out
