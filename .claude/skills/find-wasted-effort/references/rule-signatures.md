# find-wasted-effort — per-rule signatures (analyzer contract)

> Loaded on demand by the skill and implemented by `hooks/local/find-wasted-effort.py`.
> Each rule: INPUT (what the analyzer reads), SIGNATURE (what triggers a candidate),
> VERDICT LOGIC (confirmed / dismissed / inconclusive), OUTPUT (what the finding says).
> Read-only in Phase 1 — none of these write, prune, or reclassify.

## Rule 1 — Unused gate stops

- **Input:** gate reports + deploy reports + deviations sections across the round window.
- **Signature:** ≥ N rounds (default N=3) where every recorded gate deviation was approved and none was blocked.
- **Verdict:**
  - `dismissed` if ANY blocked gate / rejected deviation appears in the window.
  - `inconclusive` if window < N rounds or the gate-class is `catastrophic-low-frequency`.
  - `confirmed` only with ≥ N rounds, zero blocks, and the contrary-evidence search stated.
- **Output:** "gate-class <X> approved every deviation across <N> rounds — review candidate for Middle eligibility (NOT auto-reclassify)."

## Rule 2 — Per-commit full-suite habit

- **Input:** git log per round (commit count) + recorded test-run counts/fail-sets per round.
- **Signature:** full-suite executions per round ≫ 2 (baseline+end) with identical fail-sets each run.
- **Verdict:**
  - `dismissed` for a round whose fail-set DIFFERED across runs (suite caught a real mid-round regression).
  - `inconclusive` if run counts/fail-sets are not recorded.
  - `confirmed` when runs ≫ 2 and fail-sets identical.
- **Output:** "recommend baseline+end suite policy for round <id> (N redundant full runs, identical fail-set)."

## Rule 3 — Artifact duplication

- **Input:** round artifacts (handoffs, gate reports, deploy reports, change-notes).
- **Signature:** the same rule/evidence block appears verbatim in ≥ 3 round artifacts.
- **Verdict:**
  - `dismissed` if the duplication is intentional self-bootstrapping (role-prelude, template scaffold).
  - `inconclusive` if near-duplicate but not verbatim.
  - `confirmed` for ≥ 3 verbatim copies of substantive content.
- **Output:** "recommend pointers + round-file shape; <block> duplicated across <files>."

## Rule 4 — CUT

Context-rebuild overhead is already covered by `/token-waste-audit`'s v3.21.0 cross-session aggregate. This skill POINTS at that report and does not implement the signature.

## Rule 5 — Lane misclassification

- **Input:** diff size (git), decisions presence, lane tag (spec/change-note), ceremony actually run.
- **Signature:** small diff + zero design decisions but Full-lane ceremony was run.
- **Verdict:**
  - `dismissed` if any design decision or risk was surfaced in the round.
  - `inconclusive` on ambiguous size/risk.
  - `confirmed` only on clearly-small + zero-decision + Full ceremony.
- **Output:** "round <id> looks Lightweight/Middle-eligible — review candidate; NEVER auto-reclassify."

## Rule 6 — Ratchet inventory

- **Input:** `policies/ratchet-governance.yml` coverage map + `prevents:` markers in annotated files + firing evidence in the window.
- **Signature:** a ceremony element with NO `prevents:` annotation AND no firing in the window.
- **Verdict:**
  - `dismissed` if a `prevents:` annotation is present OR the element fired in the window.
  - `inconclusive` for a `catastrophic-low-frequency` element on a clean window (expected idle).
  - `confirmed` for an un-annotated, non-firing, non-catastrophic element.
- **Output:** "review candidate (NOT remove): element <X> has no prevents: and did not fire in <window>." Plus a coverage-gap note for elements outside the coverage map.

## Rule 7 — Watch-vs-read waste (cross-session ceremony layer ONLY)

- **Input:** cross-session round artifacts where a later session re-derived/re-watched what an earlier session recorded durably.
- **Signature:** a later session repeats observation/derivation already present in an earlier durable record.
- **Verdict:**
  - `dismissed` if the durable record was absent (a real observability gap, not waste).
  - `inconclusive` if it's unclear whether the later read added information.
  - `confirmed` when the durable record existed and was re-derived anyway.
- **Scope guard:** cross-session ceremony layer ONLY. Do NOT duplicate FR-26's execution-layer record-then-read / polling signature — `token-economy` and `smoke-testing § Verification cost discipline` own that axis.
- **Output:** "cross-session re-derivation of durable record <X> in session <Y> — point at the record."
