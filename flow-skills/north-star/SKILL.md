---
name: north-star
description: Use ONLY when docs/north-star.md exists (the project has been onboarded) OR the operator explicitly asks to check/apply the North Star. When present, steers every task, decision, and fix toward the project's locked vision and flags drift away from it. If docs/north-star.md is absent, this skill does nothing (silent no-op) — do NOT activate, do NOT create the file. Not for projects that have not been onboarded.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.30.8
risk_level: low
invocation: automatic
expected_outputs:
  - a north-star alignment check (on-vision vs drift) for the current work
  - a drift flag + recommended correction when work diverges from the vision
related_workflows:
  - eight-phase-flow.md
  - verification-gate.md
hook_dependencies:
  - none
---

# North Star

> **Style:** Mode-B-lite. **Artifact-gated** skill — inert unless `docs/north-star.md` exists.

## Purpose

Keep all work aligned to the project's vision. When a project has been onboarded (`docs/north-star.md` exists), this skill reads it and checks that tasks, decisions, and fixes serve that vision — catching drift before it compounds. **It is the canonical example of the artifact-gated pattern: ship complete, stay dormant until fed.**

## When to invoke

- `docs/north-star.md` exists AND a task / decision / fix is in progress.
- Operator says "check the north star", "is this on-vision", "does this drift".
- During Specify / Plan / Decisions / Tasks / a non-trivial fix (alongside FR-20 zoom-out).

## Do not invoke when

- **`docs/north-star.md` does NOT exist** → silent no-op. Do not activate, do not prompt repeatedly, do not create the file. (Project simply hasn't been onboarded; that's fine.)
- Trivial mechanical edits.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Project North Star | `docs/north-star.md` | **STOP — skill is a no-op.** Do not create it. (Onboarding via `project-onboarding` / `/onboard` creates it.) |
| Current work | spec / decision / task / fix in progress | nothing to check; exit |

## Procedure

1. **Existence gate (MANDATORY FIRST STEP).** If `docs/north-star.md` does not exist → this skill contributes no check: skip steps 2-5. Default is silent no-op; the ONLY sanctioned output on the absence path is the one-time D5 offer (step 6). Do NOT create the file. Do NOT nag.
2. **Read** `docs/north-star.md` (vision, audience, in/out scope, success, constraints).
3. **Align-check** the current work: does it serve the vision; is it in-scope; does it fit the audience (internal vs client); does it respect the constraints?
4. **Flag drift — via the Required output block below.** If the work diverges (out-of-scope, wrong audience, against a constraint), say so plainly and recommend the on-vision alternative.
5. **Ambiguity → ask** the operator in chat (FR-19); do not silently reinterpret the vision.
6. **Offer-once (D5) — sole absence-path output.** Applies only when step 1 found no `docs/north-star.md` AND the operator is clearly doing project work AND no prior offer was made (if unsure whether one was, do not offer). Offer once: "No North Star is set — want to capture one (`/onboard`)? Or continue without." Silence or decline → permanent silent no-op for the rest of the project.

## Required output — alignment verdict (3 lines)

Every activation that reaches step 3 MUST emit this block — in chat (Mode A context) and verbatim into the gate/ticket note when one is written. A north-star claim without the block is unverifiable and does not count as a check.

```
North-star: <On-vision | Drift | Blocked (locked-decision conflict, FR-11)>
Dimension:  <vision | scope | audience | constraint | success-metric> — <which line of docs/north-star.md, one clause>
Recommendation: <proceed | on-vision alternative in one line | question for operator (FR-19)>
```

`On-vision` still emits the block (Dimension: the strongest match; Recommendation: proceed) — silence is indistinguishable from a skipped check.

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Alignment verdict block (3 lines, above) / drift flag | chat (Mode A) or ticket note | Mode A / Mode-B-lite |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact absent | step 1 | silent no-op (correct behavior, not an error) |
| Work contradicts vision | step 3 | flag; recommend on-vision path; escalate to operator if locked-decision conflict (FR-11) |
| Vision itself is stale | operator says vision changed | route to `project-onboarding` to update `docs/north-star.md` |

## Escalation path

- Drift vs a locked decision → stop and ask operator (FR-11/FR-19).
- Vision needs updating → `project-onboarding` ("update my North Star").

## Anti-patterns

- Do not activate or create the file when `docs/north-star.md` is absent.
- Do not nag every turn when unset (offer at most once — D5).
- Do not reinterpret/rewrite the vision on the operator's behalf.
- Do not block trivial work that doesn't touch the vision.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
