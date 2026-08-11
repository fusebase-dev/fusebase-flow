# Problem: PO decision latency, not gates or reviews, dominated elapsed time

**Slug:** `po-latency-dominates-elapsed-time`
**Filed:** 2026-08-05 · **Severity:** high · **Status:** mitigated (protocol below)
**Filed by:** PO after an adversarial retrospective (Codex xhigh) of the v4.7.0/v4.7.1 cycle

## Symptom

A source-integrity ticket took **117h12m** wall-clock (`a278878..cbda87e`) for ~42h of active work. The PO believed the cost was gates and review rounds. It was not.

## Measurement

| | |
|---|---|
| Total elapsed | 117h12m |
| Three stop-to-next-action gaps (waiting on a PO ruling) | **77h27m** |
| All gaps > 2h | **89h06m — 76% of elapsed** |
| One pause (M14→M16) | **52h32m** — longer than the realistic target for the whole ticket |
| Review *thinking* | ~2h20m total across 14 rounds |

Work sat finished, waiting to be ruled on.

## Root causes (ranked by measured cost, not plausibility)

1. **PO serialized as a decision bottleneck.** One ruling per cycle, each cycle costing a full gate. The PO originally ranked this 4th of 6.
2. **Contracts locked half-specified**, so the implementer faithfully built the gap. M14 refuted, M18 factually false, M21 incomplete. Rounds 2-5 each fixed defects introduced by the round before. Dominant *rework* multiplier.
3. **The expensive step ran before the informative one.** Full two-platform gate → adversarial review → any review-driven edit invalidates both. Backwards for statically-detectable defects.
4. **Full-lane ceremony applied to text-only residuals.** Wording corrections got the same 45-minute two-platform gate as a 400-line boundary rewrite.
5. **Documentation ceremony was material.** Docs + generated artifacts were **38.5% of churn — more than production code**. Handoffs re-stated rules the agent reads anyway.
6. **Scope creep into unrequested work.** A consumer wrote *"this is not a request to change your default… we claim only that the consequence is now observed."* The PO built a surfacing feature instead: 3 rounds, 3 green gates, 3 NO-SHIPs, parked unshipped.

## What was NOT the cause

Adversarial review. It found **100% of real defects**; three consecutive green suites found **zero**. Two claims the PO made in its own defence were refuted: reviews *did* run before code (`a44962c`, 17 findings), and agent quality *was* a factor — the first implementation review found a manifest fail-open, symlink escape, non-atomic repair, mutable-source trust and widened destructive authority.

## Guardrail — the execution protocol

1. **Answer decisions in batch, not per cycle.** When an agent stops on a contract question, rule on it **and** pre-authorize the likely next two branches. One ruling per cycle is the 76%.
2. **Contract matrix before locking — 45 min max.** Any decision saying *"behave like X"* must enumerate every X first. `command_policy` supplies `repo_id`+`command_digest`; `path_policy` supplies neither; health deferrals aren't in `require_approval` at all. That table would have collapsed three rounds into one.
3. **Review before the expensive gate.** Targeted review → fix → gate. Not gate → review → invalidate both.
4. **Tier the gate.** Scoped phases (~8 min) for intermediate rounds; one full unscoped two-platform gate before release only. Intermediate scoped runs are explicitly **not** release proof.
5. **Lightweight-lane text-only residuals.** Comment deletions and assertion renames are not Full-lane.
6. **Build only what was asked.** A consumer reporting an observation wants it recorded. Confirm scope before designing a feature.
7. **Thin handoffs.** Do not re-state rules the sub-agent already reads.

## Recurrence triggers

- A review round whose findings sit inside the previous round's fix → **stop implementing, decide the contract** (see `undecided-contract-drives-repeat-defects`).
- An agent halted awaiting a ruling for more than a few hours.
- A full gate running for a delta that changes no code.
- Designing a feature in response to a report that asked only for a record.

## Related

- `docs/problem-catalog/undecided-contract-drives-repeat-defects/problem.md` — the rework half of this
- `docs/backlog/gate-bounds-lack-headroom/` · `docs/backlog/compat-approval-surfacing/`
- Full retrospective: `c:/tmp/ffretro/r.md` (2026-08-05, Codex xhigh)
