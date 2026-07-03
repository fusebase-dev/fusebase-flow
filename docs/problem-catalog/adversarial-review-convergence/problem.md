# Problem: v3.30.5 took TEN adversarial-review convergence rounds — real convergence vs infinite loop

**Slug:** `adversarial-review-convergence`
**Filed:** 2026-07-03
**Severity:** medium
**Status:** resolved
**Filed by:** PO per FR-15 (process lesson; operator requested records)

## Symptom

v3.30.5 required TEN convergence rounds because each independent adversarial confirm (Codex companion + a 3-lens Opus panel) found a DEEPER reachable bypass than the last. Quality-positive but slow; the risk was mistaking a genuine finite ladder for an infinite review loop.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Review round N returns a finding | close it, re-review |
| 2 | Round N+1 returns a DISTINCT, named deeper mechanism | close it, re-review |
| 3 | Last two independent reviewers both return SHIP, zero findings, end-to-end RED→GREEN PoC | converged — ship |

Reproduces: N/A (process observation, not a code defect — see FR-10)

## Root cause

The bug class ("how does working-tree code reach the interpreter") is a finite ladder of load-points: file → patterns → policy → exceptions → startup files → env → called-modules → import path. Each round closed one rung; the next round found the next rung. This LOOKS like an infinite loop but is a converging descent because each rung is distinct and named.

## Why it matters

- Without a convergence test, a team either ships too early (a rung left open) or loops forever (chasing diminishing findings).
- The signal that it was real convergence: each round closed a DISTINCT named mechanism forming a finite ladder; the last two INDEPENDENT reviewers both returned SHIP with zero findings and end-to-end RED→GREEN PoCs.

## Mitigation / workaround

1. Run INDEPENDENT adversarial review (ideally 2+ reviewers) of the ACTUAL code before deploy.
2. Converge only when independent reviewers agree AND only out-of-model residuals remain.
3. Give the operator a transparent per-round heads-up (each round names the distinct mechanism it closed).

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | process lesson captured; applied in v3.30.5 release (`180f4a1`) · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- A security/hardening ticket where each review round surfaces a new deeper finding
- Operator asks "is this converging or looping?"
- Deploy-gate needs a stop rule for adversarial review

## Guardrail (the lesson)

Run independent adversarial review (2+ reviewers) of the ACTUAL code before deploy; converge only when independent reviewers agree and only out-of-model residuals remain; give the operator a transparent per-round heads-up. A finite ladder of distinct named mechanisms IS convergence; repeated findings of the SAME mechanism is a loop.

## Related

- `docs/problem-catalog/security-check-fail-open-class/problem.md` — the class the ladder closed
- `MEMORY.md` [adversarial-review-implementation-before-deploy] — the independent-review-before-deploy rule

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
