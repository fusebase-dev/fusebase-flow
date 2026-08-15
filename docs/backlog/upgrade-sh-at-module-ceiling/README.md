# Backlog — upgrade-sh-at-module-ceiling

**Status:** open — **a debt with a named payer, not an amnesty**
**Filed:** 2026-08-15 (during `n5-upgrade-silent-no-op`)
**Owner:** the next ticket that touches `hooks/local/upgrade.sh`
**Lane guess:** Full — it decomposes the engine that strands consumers if it is wrong

## THE PREREQUISITE

**The next change touching `hooks/local/upgrade.sh` must decompose it FIRST.** The extraction is a *prerequisite of that ticket*, not optional cleanup to be deferred again. If you are reading this because a module-size block stopped you, you are the payer.

## The finding

`upgrade.sh` was **794 of the 800-line ceiling BEFORE `n5-upgrade-silent-no-op` began**. It is at its ceiling as a **standing condition**, not as a consequence of N5 — six lines of headroom means *any* feature added to this file triggers the same decision. N5 merely happened to be the change that arrived first.

That distinction matters for whoever reads the block next: the natural reading is "this ticket bloated the file", and that reading is wrong. N5 added **27 lines of call sites**; both of its new concerns were extracted into libs before the block was even reported (`lib/synthesize-base.sh`, `lib/upgrade-delivery-guard.sh`).

## What was adopted, and why that is not a dodge

The baseline was re-keyed for **`hooks/local/upgrade.sh` at 821, targeted to that one path** (`--write-baseline <path>`, no global amnesty), **for N5 only**.

It was taken **to keep an urgent consumer fix separable — not because the file is fine.** N5 is HIGH and live: consumers on the F1/N1 path cannot receive v4.10.1's content today. Refactoring a critical engine in the same release as an urgent correctness fix makes both harder to review and, decisively, harder to **revert**: a field rollback must be "the N5 guard", not "the N5 guard plus an engine reshuffle".

Supporting evidence for that caution, all from 2026-08-14/15: three separate "small, safe" changes to this codebase had surprising failure modes visible only on a fresh checkout — the `--local` clone dying cross-volume, the CRLF manifest describing bytes that never ship, and the annotated-tag concatenation that deadlocked every release. Each looked local and none was. `upgrade.sh` is the one file where being wrong strands a consumer with a half-installed tree.

**Adopting a baseline resets the ratchet's reference point, which is exactly the creep FR-25 exists to prevent.** That is why this entry exists and why the prerequisite above is written as a blocker rather than a suggestion. The debt is recorded with a due date, not waved through.

## The identified seam — inherit this analysis, do not re-derive it

**`print_recovery_hint` + `ffhc_run_step`** — one coherent responsibility: *bounded step execution and recovery messaging*. It is already lib-adjacent (both wrap `hooks/local/lib/run-with-timeout.sh`), which is what makes it a genuine responsibility seam rather than a mechanical `utilsN` split. Roughly 60 lines, enough to restore real headroom rather than shaving under the number.

Two constraints for whoever does it:

- `hooks/tests/test-recovery-hint-honesty.sh` asserts on `print_recovery_hint`'s printed text (four recovery-command anchors, the run-your-own-gate line, and the absence of specific continuity phrasings). Extraction must preserve those strings verbatim; the test drives the function, so it will catch a drop.
- `ffhc_run_step` participates in the `FF_*` bounded-run contract. Moving it must not change which globals it reads or when it clears them.

## Acceptance criteria

- **AC1** — `upgrade.sh` is back **under 800 without a baseline entry**, and its row is removed from `policies/module-size-baseline.txt` (shrinking out of the baseline, not re-keying to a smaller number).
- **AC2** — extraction is along the named seam, not a mechanical split; `test-recovery-hint-honesty.sh` passes unchanged.
- **AC3** — the heavy upgrade phases (`upgrade-classify`, `upgrade-boundary`, `preboundary-consumed`, `upgrade-repair`) pass, because those are the phases that actually exercise this engine.

## Notes

Related: `docs/specs/n5-upgrade-silent-no-op/` (the ticket that surfaced it) · `flow-skills/module-size-discipline/SKILL.md` (FR-25) · `docs/problem-catalog/fr25-upgrade-adoption-collision/problem.md` (the prior FR-25/FR-07 interaction).
