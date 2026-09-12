# Drift checkpoint (proposed FR-28) — WRONG-LAYER; reduced to two existing-owner edits

**Status:** SUPERSEDED 2026-09-12. Adversarial premise review (GPT-6 Astra, xhigh) returned **WRONG-LAYER** before any code was written. Review: `/c/tmp/prem-drift-out.md` from line 2989. The original plan below the line is retained for the record only; nothing in it is to be built.
**Source:** consumer proposal `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-09-11-drift-checkpoint-for-long-tasks.md`.

## What the review established

| Claim in the plan | Finding |
|---|---|
| Nothing in Flow fires on trajectory | **False.** FR-20 `zoom-out` triggers on "the same area has been patched before" (`flow-skills/zoom-out/SKILL.md:3`); `adversarial-review-convergence` already evaluates distinct mechanisms, finite ladder, independent closure |
| S4 (declared cap exceeded) is grep-computable | **No.** The T100–T108 cap lived in chat; no standard on-disk input exists |
| "Endpoint function rewritten four times" | Overstated: four corrective passes on the identity path (T102–T105), not four replacements of one function |
| Stale handoff is S8 evidence for T100–T108 | **Wrong episode.** Retired by `4824d6a` at 12:11; T100 began at 14:07 |
| A Tier 1 review at round 4 would have saved ~4 reviews | **Hindsight.** Round 4 could not contain the NUL+LF defect round 5 introduced |
| "Silent for Lightweight" | Not established: S8 and S3 fire on ordinary work; no exemption was specified |
| The plan applied to itself | Fails P1 (wrong shape), P2 (machinery needing machinery), P3 (40–180K tokens per 30-commit task, benefit unmeasured) |

**The real gap, in the reviewer's words:** *recognizing self-created regressions during convergence, and honoring declared bounds before dispatch.* Not an absence of trajectory discipline.

## What is built instead (the review's YES calls)

| Edit | Owner | Content |
|---|---|---|
| Catalog | `docs/problem-catalog/adversarial-review-convergence/problem.md` | Add the discriminator the convergence test lacks: *is this finding a pre-existing mechanism, or a defect introduced by the preceding correction?* Require that a correction preserve earlier closures. File the T100–T108 instance with the corrected facts above |
| Correction review | `docs/maintainer-execution.md` step 5 (existing owner) | Two fixed questions before dispatching a further round: (1) *pre-existing, or introduced by the previous correction?* (2) *does the correction preserve the contract across the whole affected path?* Plus: a declared round bound is checked **before** launching the next round; exhaustion returns the work for a scope/cost decision, never a labelled continuation |
| Cost question | Premise review, only when scope is contested | *minimal plan at observed cadence; what to cut first* |
| Coordinator | Orchestrator memory, not the repo | The coordinator declared caps in chat and extended them three times. The fix is behavioral and belongs to the agent that failed |

## Explicitly NOT built

FR-28 row · FR-20/FR-18 rewording (obligations already exist) · `drift-signals.sh` · `policies/drift.yml` · `drift-checkpoint` skill · Tier 1 prompt · `/drift-check` · handoff Tier 0 checklist · `lightweight-lane` catalog grep (a keyword hit must not escalate an ordinary change).

## Conditions under which a build could be reconsidered

From the review, §J: a corrected evidence ledger separating confirmed facts from testimony and counterfactuals; a prospective maintainer trial of the smaller intervention measuring changed decisions, cost and missed defects; per-signal input contracts with unknown distinct from zero, tested on an ordinary Lightweight consumer; historical **prefix** replay (trigger before the decision, without retrospectively planted markers); negative cases for healthy convergence; defined cap ownership and root-human behavior; protection against the detector reading its own audit quotations.

---

## Original plan (superseded, retained for the record)

The plan proposed FR-28 with eight grep-computed signals (S1–S8), three tiers (self-check at handoff; adversarial drift review by a second model family; operator decision), a verdict vocabulary with `ROLL BACK`, a cap rule with escalation-up, reset conditions, `hooks/local/drift-signals.sh`, `policies/drift.yml`, a `drift-checkpoint` skill, `/drift-check`, and two "similar problems" lines in existing steps. Precedents cited: Shape Up circuit breaker, Erlang restart intensity, SRE error budgets, OpenHands StuckDetector, Keras patience, resilience4j HALF_OPEN, LangChain/AutoGen iteration caps, `actions/stale`, rustc-perf triage. The precedents remain valid references for the class; the plan's error was universalizing them into consumer defaults on unverified inputs.
