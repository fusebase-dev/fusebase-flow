# find-wasted-effort — false-positive examples (per rule)

> The contrary-evidence catalog. A finding is `confirmed` only after the analyzer
> searched for — and did not find — its rule's false positives below. These also
> seed the per-rule FP fixtures behind Phase 2A proposal output (T24): a proposal
> is emitted only from a `confirmed` finding (or a rule-6 review candidate), so no
> proposal is produced until the rule has dismissed its FPs. Phase 2A PROPOSES
> only (read-only-safe; output under state/audit/); the write-apply is Phase 2B
> (DEFERRED, consumer-repo, AC2b).

## Rule 1 — Unused gate stops — false positives

- A gate that BLOCKED a deviation earlier in the window (the stop did its job — clean recent rounds don't erase it).
- A `catastrophic-low-frequency` gate class (rare-but-severe; a clean window is expected, not waste).
- Too short a window (N rounds not yet reached) — `inconclusive`, not `confirmed`.

## Rule 2 — Per-commit full-suite habit — false positives

- A round where one full run's fail-set DIFFERED — the suite caught a real regression mid-round (the runs bought information).
- FR-10 3/3 reproduction runs (deliberate repetition, not redundant ceremony).
- Test reruns immediately after a real fix (expected, not a habit signature).

## Rule 3 — Artifact duplication — false positives

- Intentional self-bootstrapping: the handoff role-prelude, template scaffolding, the FP header itself — meant to be repeated so each artifact is standalone.
- Near-duplicates that diverge on substantive content (different SHAs, different probe results).

## Rule 5 — Lane misclassification — false positives

- A small diff that still surfaced a design decision or a risk (Full was correct).
- A change that touched a security surface / migration / irreversible step (Full mandatory regardless of diff size).
- Ambiguous size or risk — `inconclusive`, never an auto-reclassify.

## Rule 6 — Ratchet inventory — false positives

- An element that DOES carry a `prevents:` annotation (it's governed — not a candidate).
- An element that FIRED in the window (it bought a real outcome).
- A `catastrophic-low-frequency` element on a clean window (expected idle — `inconclusive`).
- An element outside the `ratchet-governance.yml` coverage map (report as coverage gap, not as confirmed waste).

## Rule 7 — Watch-vs-read waste — false positives

- The durable record was ABSENT — the later session had to re-derive because nothing recorded it (a real observability-gap finding, not waste).
- The later read genuinely added information not in the earlier record.
- Execution-layer polling/record-then-read patterns — out of scope here (FR-26 / `token-economy` / `smoke-testing` own them); not this rule's false positive, simply not this rule.
