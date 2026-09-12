# Problem: v3.30.5 took TEN adversarial-review convergence rounds — real convergence vs infinite loop

**Slug:** `adversarial-review-convergence`
**Filed:** 2026-07-03
**Severity:** medium
**Status:** resolved for the case it was filed on — a finite ladder of DISTINCT PRE-EXISTING mechanisms. NOT covered until 2026-09-12: rounds whose findings were CREATED by the preceding correction, and a round bound that lives only in chat (see the second instance below).
**Filed by:** PO per FR-15 (process lesson; operator requested records)

## Symptom

v3.30.5 required TEN convergence rounds because each independent adversarial confirm (Codex companion + a 3-lens Opus panel) found a DEEPER reachable bypass than the last. Quality-positive but slow; the risk was mistaking a genuine finite ladder for an infinite review loop.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Review round N returns a finding | close it, re-review |
| 2 | Round N+1 returns a DISTINCT, named deeper mechanism | close it, re-review |
| 2b | Round N+1's finding was CREATED by round N's correction — twice running | NOT a rung; the approach is wrong. Stop patching; settle the contract across the whole affected path |
| 3 | Last two independent reviewers both return SHIP, zero findings, end-to-end RED→GREEN PoC | converged — ship |

Reproduces: N/A (process observation, not a code defect — see FR-10)

## Root cause

The bug class ("how does working-tree code reach the interpreter") is a finite ladder of load-points: file → patterns → policy → exceptions → startup files → env → called-modules → import path. Each round closed one rung; the next round found the next rung. This LOOKS like an infinite loop but is a converging descent because each rung is distinct and named.

The ladder test is blind to one thing: a defect the PRECEDING CORRECTION introduced also arrives as a distinct, named, never-seen mechanism. Discriminator, asked of every round's finding: PRE-EXISTING mechanism, or introduced by our last correction? Two consecutive "introduced" answers mean the APPROACH is wrong, not the instance — stop patching and settle the contract across the whole affected path. A correction must also PRESERVE EARLIER CLOSURES: round N+1's fix must not reopen what round N closed, however new its finding looks. Rungs your own corrections built are not descent.

## Why it matters

- Without a convergence test, a team either ships too early (a rung left open) or loops forever (chasing diminishing findings).
- The signal that it was real convergence: each round closed a DISTINCT named mechanism forming a finite ladder; the last two INDEPENDENT reviewers both returned SHIP with zero findings and end-to-end RED→GREEN PoCs.

## Second instance: T100–T108 (approval binding, this repo, 2026-09-11/12)

One contract (command-approval identity), eight review outputs. Four CORRECTIVE PASSES ON THE IDENTITY PATH across T102–T105 — allowlist, then canonicalization, then record framing, then deletion of the enumeration parsers — not four rewrites of one function. Rounds 4 and 6 fixed defects rounds 3 and 5 had INTRODUCED, and the corrective commits say so themselves: `f5ca11b` ("the last two were caused BY the previous fix"), `d1a9808` ("the last two defects were introduced by the fixes for the previous two"). Verdicts ran six DO-NOT-SHIP, then two SHIP-WITH-FIXES — six of the eight outputs were re-read in the 2026-09-12 premise review, so the full 6+2 aggregate is operator-reported and UNVERIFIED. The coordinator declared "no sixth round" IN CHAT and then authorized three more: the declared bound was not on disk and not honored, so no dispatch could check it. The finite-ladder test passed the whole way — every round named a new mechanism — while two of the rungs were self-created.

## Mitigation / workaround

1. Run INDEPENDENT adversarial review (ideally 2+ reviewers) of the ACTUAL code before deploy.
2. Converge only when independent reviewers agree AND only out-of-model residuals remain.
3. Give the operator a transparent per-round heads-up (each round names the distinct mechanism it closed).
4. Classify each finding by provenance (see Root cause) before correcting it, and keep the round bound where the next dispatch can read it. `docs/maintainer-execution.md` step 5 owns both for this repo.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | process lesson captured; applied in v3.30.5 release (`180f4a1`) · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- A security/hardening ticket where each review round surfaces a new deeper finding
- Operator asks "is this converging or looping?"
- Deploy-gate needs a stop rule for adversarial review
- A corrective commit attributes the defect it fixes to a previous fix, or a declared round cap is extended

## Guardrail (the lesson)

Run independent adversarial review (2+ reviewers) of the ACTUAL code before deploy; converge only when independent reviewers agree and only out-of-model residuals remain; give the operator a transparent per-round heads-up. A finite ladder of distinct named mechanisms IS convergence; repeated findings of the SAME mechanism is a loop; and a ladder whose rungs the corrections themselves built is neither — two consecutive self-created findings mean the approach is wrong, and a correction that reopens an earlier closure never counts as a rung.

## Related

- `docs/problem-catalog/security-check-fail-open-class/problem.md` — the class the ladder closed
- `MEMORY.md` [adversarial-review-implementation-before-deploy] — the independent-review-before-deploy rule
- `docs/specs/drift-checkpoint/spec.md` — the 2026-09-12 premise review that filed the second instance; its proposed FR-28 detector was ruled WRONG-LAYER and is not built

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
| 2026-09-12 | extended: causal-provenance discriminator, closure preservation, T100–T108 instance | premise review of the proposed FR-28 (`docs/specs/drift-checkpoint/spec.md`) |
