# Problem: an UNDECIDED contract turns review rounds into a defect treadmill — each round fixes the last round's fix

**Slug:** `undecided-contract-drives-repeat-defects`
**Filed:** 2026-08-03
**Severity:** medium
**Status:** resolved
**Filed by:** PO per FR-15 (process lesson; operator asked for the recurrence to be prevented, not just this instance fixed)

## Symptom

`upgrade-source-integrity-and-observability` (v4.7.0) took **eight** adversarial review rounds. Rounds 2–5 were not finding *new* ground: each one's blockers were defects **introduced by the previous round's fix**. The ticket looked like it was converging (findings kept shrinking) while it was actually circling one unanswered question. Rounds 6–8 returned zero class-(b) findings and only text defects — the difference is that by then the contract had been decided.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Round N review names a repair-verification blocker | implementer patches the predicate at the site the review named |
| 2 | Round N+1 reviews the patch | new blocker, **inside the round-N patch**, same underlying question |
| 3 | Repeat rounds 2→5 | four rounds, each closing the previous round's fix; the contract question is never asked |
| 4 | Round 4 post-mortem (M13 reasoning) | the two round-4 defects are shown to be **one** ambiguity instantiated twice — `rc` dropped in one verifier, layer-skip keyed on manifest vs wrapper in another |
| 5 | Decide the contract instead of patching (M13 → M14 → refuted → M16, whose own review still returned a class-(b) threat-model blocker → M17) | rounds 6, 7 and 8 return **zero class-(b) findings**; only text/wording defects remain |

Reproduces: N/A — process observation across one ticket's git + review history, not a code defect (FR-10).

## Root cause

Nobody had **decided what "repair confirmed" means when the consumer may not carry every manifest layer.** With the contract undecided, the implementation had to invent an answer at each call site, and it invented a different one each time. A review can only fault the site in front of it, so every round produced a locally-correct patch that contradicted the next site — a patch-on-patch treadmill (FR-20's failure mode) rather than a converging ladder.

The tell that it was a treadmill, not convergence: the findings were **the same question re-surfacing at a new site**, not a new distinct mechanism. (Contrast `adversarial-review-convergence`, where each of ten rounds closed a **distinct named rung** of a finite ladder — that IS convergence.)

## Why it matters

- Four review rounds bought no net progress. Review capacity is the scarcest resource on a hardening ticket, and it was spent re-reading the implementer's own last diff.
- A locally-correct patch against an undecided contract is **indistinguishable from a fix** at review time; it passes, then fails somewhere else next round. The defect count going down is not evidence of convergence.
- Deciding is not automatically enough: M14 was decided fast **on the wrong axis** (it read bound-set membership out of the tree being repaired) and had to be refuted by M16; M16's own review then returned a class-(b) threat-model blocker, which M17 closed. Only after all three did the class-(b) findings stop. A decision ends the treadmill when its anchor is outside the artifact under repair — not merely because it was written down.

## Mitigation / workaround

1. When a review round's findings land mostly **inside the previous round's fix**, STOP implementing. Do not open the file the review named.
2. Write the contract question as one sentence ("what does X mean when Y is absent?"). If it cannot be stated in one sentence, that is the finding.
3. Take it to a **decision** (`decisions.md`, LOCKED), not a patch. Name the rejected options — the rejected ones are what stop the next site inventing them again.
4. Then do ONE implementation pass against the decided contract, then ONE review. Not iterate-until-green.
5. Verify the decision's anchor is outside the thing under repair. M14 failed because it read membership out of the tree being repaired; M16 anchors on the verified upstream tree.

## Permanent fix

| Status | Detail |
|---|---|
| Implemented — release pending | contract decided: **M13** (bind the layer set at authorization), **M16** (membership declared by the VERIFIED upstream tree — supersedes the refuted M14), **M17** (same-principal threat model) in `docs/specs/upgrade-source-integrity-and-observability/decisions.md`. Ships with v4.7.0; this row is flipped to Shipped with the deploy hash by the FR-14 docs commit |
| Process | M13 carries an explicit **process note**: "this decision exists because the previous three rounds tried to *patch* the ambiguity. One implementation pass against a decided contract, then one review." |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- **The primary trigger:** a review round whose findings are mostly located **in the previous round's fix**. One occurrence is bad luck; two consecutive is this problem.
- Two defects in one round turn out to be the same ambiguity at two call sites (asymmetric predicates: one checks `rc`, another checks a parsed verdict; one keys on artifact A, another on artifact B).
- The implementer cannot answer "what is this supposed to do when <artifact> is missing?" without reading the code to find out.
- Operator asks "is this converging or looping?" and the honest answer needs the *content* of the rounds, not their count.
- A fix is described as "narrowing the claim" or "adding a check" rather than as satisfying a written rule.

## Guardrail (the lesson)

**A review round whose findings sit inside the previous round's fix means the contract is undecided. Stop implementing and decide the contract.** Patching the site the review named is the failure mode, not the fix: each patch is locally correct and globally inconsistent, so the treadmill can run indefinitely while looking like progress. Decide it explicitly, LOCK it, record the rejected options, then do one implementation pass and one review. Also check that the decision's anchor lives **outside** the artifact under repair — an anchor read from the thing you are repairing can be removed by whoever can damage it (M14 → M16).

## Related

- `docs/specs/upgrade-source-integrity-and-observability/decisions.md` — **M13** bind-at-authorization (with its process note), **M14** refuted, **M16** anchor outside the repaired tree, **M17** same-principal threat model
- `docs/problem-catalog/security-check-fail-open-class/problem.md` — the sibling class: enumerate every carrier of a defect class rather than fixing the ones the report named. Same economy, different axis (that one is breadth across carriers; this one is depth to the decision)
- `docs/problem-catalog/adversarial-review-convergence/problem.md` — the **contrast** case: distinct named rungs on a finite ladder IS convergence; repeated findings of the same question is this problem
- `FLOW_RULES.md` FR-20 (zoom out, don't patch-myopically), FR-11 (stop and ask, don't improvise)

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-08-03 | filed; problem resolved (contract decided in M13/M16/M17), release pending | v4.7.0 release round 8 |
