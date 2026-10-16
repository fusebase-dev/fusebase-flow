# gate-countable-facts-tally

**Status:** superseded by `evidence-row-validator` (6.0.0 WP 7c, 2026-10-16). **Filed:** 2026-10-15 (consumer handoff 2026-10-14 §5 B3; `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** medium (consumer skeptics refuted 16 of 26 gate claims). **Surface:** `policies/gate-contracts.yml` (FR-07), `hooks/local/verify-gate.sh`, `templates/{gate-report,verification-gate}.md`, `workflows/verification-gate.md`.

## Observed

v5.11 O7/O8 make gate rows PASS/FAIL claims with evidence and keep the verdict on the PO side; `verify-gate.sh` validates values but stays advisory. Open question: does a shipped stdlib tally catch refutations O7 misses? Most consumer refutations were semantic (a capture still "Loading", byte-identical captures, PASS with a 401), which a presence tally also passes.

## Shape

`gate-tally` computes countable row facts only: capture present at the cited path, deploy id equals the final deploy, capture mtime after the deploy timestamp, non-trivial size, finding flags from a reviewer-written ledger. The per-criterion reading stays judged and recorded by a non-implementer (ROADMAP.md:47 — no regex gate on semantics).

## Gate

Build only if the consumer's own tally (applied 2026-10-14), at the first phase gate it closes, reports at least one countable-class refutation that passed O7's row rule.

## Acceptance

Verdict = tally + typed non-implementer readings = PO recount at that close; a report whose verdict differs fails; the tally never passes a row without a capture. New FF tag classified in `docs/maintainer-testing.md`. Contract-changing (verdict authority) → premise review.
