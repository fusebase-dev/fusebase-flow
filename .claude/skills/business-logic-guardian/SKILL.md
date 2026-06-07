---
name: business-logic-guardian
description: Use ONLY when docs/<app>/business-logic.md exists, before fixes/improvements that touch business behavior. Treats the documented business logic as a guard layer — the fix must not silently break documented behavior. Pairs with FR-20 zoom-out. If no business-logic doc exists, this skill does nothing (silent no-op) — do NOT auto-create. Not for net-new features with no documented logic.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.5
risk_level: low
invocation: automatic
expected_outputs:
  - a business-logic impact check for the change in progress
  - a flag when a fix would break documented behavior
related_workflows:
  - eight-phase-flow.md
  - verification-gate.md
hook_dependencies:
  - none
---

# Business Logic Guardian

> **Style:** Mode-B-lite. **Artifact-gated** — inert unless a business-logic doc exists (`docs/<app>/business-logic-index.md` AI-default, or `docs/<app>/business-logic.md` human narrative).

## Purpose

Protect documented business logic during fixes and improvements. The business-logic doc is a fast navigation/verify layer: confirm a change does not silently break documented behavior before committing. Complements FR-20 (zoom-out) and FR-10 (reproduce-before-fix).

> Consumes whichever business-logic doc exists. Per FR-23 (`flow-skills/documentation-budget/SKILL.md`), the AI-default authoring format is the retrieval index `templates/business-logic-index.md` (tables + source paths); the narrative `templates/business-logic.md` is the explicit human-readable option. This skill reads either as the guard layer.

## When to invoke

- `docs/<app>/business-logic-index.md` (AI-default retrieval index) **or** `docs/<app>/business-logic.md` (human narrative) exists AND a fix/improvement touches business behavior. If both exist, the index is the primary guard layer; the narrative is supplementary.
- Operator says "don't break the business logic", "does this change behavior".
- During Implement / post-gate fixes on an app that has documented logic.

## Do not invoke when

- **Neither `docs/<app>/business-logic-index.md` nor `docs/<app>/business-logic.md` exists** → silent no-op; do not create either (use `app-business-docs`, or the FR-23 `business-logic-index` template, to author one deliberately).
- Net-new feature with no documented logic yet.
- Pure cosmetic edits.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Business logic doc | `docs/<app>/business-logic.md` | **STOP — no-op.** Author via `app-business-docs` if wanted. |
| The change in progress | current diff/plan | nothing to check; exit |

## Procedure

1. **Existence gate (FIRST STEP).** No `docs/<app>/business-logic.md` → exit silently. Do not create it.
2. **Read** the documented business logic / main flows / edge cases.
3. **Impact-check** the change: does it alter, remove, or contradict any documented behavior or edge case?
4. **Verify against code** — the doc is the navigation layer; confirm the actual code path matches before trusting the doc (code is source of truth).
5. **Flag** any documented behavior the change would break; recommend preserving it or, if the change is intentional, updating the doc (via `app-business-docs`) in the same change.
6. **Ambiguity → ask** operator (FR-19).

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Business-logic impact check | chat / gate note | Mode A / Mode-B-lite |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact absent | step 1 | silent no-op (correct) |
| Change breaks documented behavior | step 3 | flag; preserve or update-doc-in-same-change |
| Doc disagrees with code | step 4 | trust code; note the doc is stale; suggest refresh |

## Escalation path

- Intentional behavior change → update `docs/<app>/business-logic.md` via `app-business-docs`.
- Conflict with a locked decision → ask operator (FR-11/FR-19).

## Anti-patterns

- Do not activate/create the doc when absent.
- Do not trust the doc over the code (verify).
- Do not silently change documented behavior without flagging it.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
