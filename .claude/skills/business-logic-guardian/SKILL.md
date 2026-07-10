---
name: business-logic-guardian
description: Use ONLY when a business-logic doc exists — docs/<app>/business-logic-index.md (AI-default retrieval index), docs/<app>/business-logic.md (human narrative), or docs/en/business-logic.md (the app-business-docs canonical for Fusebase CLI teams) — before fixes/improvements that touch business behavior. Treats the documented business logic as a guard layer — the fix must not silently break documented behavior. Pairs with FR-20 zoom-out. If none of these docs exist, this skill does nothing (silent no-op) — do NOT auto-create any of them. Not for net-new features with no documented logic.
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

> **Style:** Mode-B-lite. **Artifact-gated** — inert unless a business-logic doc exists at ANY path in § Doc-path resolution.

## Purpose

Protect documented business logic during fixes and improvements. The business-logic doc is a fast navigation/verify layer: confirm a change does not silently break documented behavior before committing. Complements FR-20 (zoom-out) and FR-10 (reproduce-before-fix).

> Consumes whichever business-logic doc exists. Per FR-23 (`flow-skills/documentation-budget/SKILL.md`), the AI-default authoring format is the retrieval index `templates/business-logic-index.md` (tables + source paths); the narrative `templates/business-logic.md` is the explicit human-readable option. This skill reads either as the guard layer.

## Doc-path resolution (the gate checks ALL of these)

| Doc | Path | Role |
|---|---|---|
| Retrieval index (AI-default, FR-23) | `docs/<app>/business-logic-index.md` | primary guard layer when present |
| Flow narrative (human option) | `docs/<app>/business-logic.md` | guard layer; supplementary if index exists |
| CLI-edition narrative (`app-business-docs` canonical) | `docs/en/business-logic.md` | guard layer for Fusebase CLI teams using the provider skill |

If several exist: index first, narratives supplementary. The gate no-ops only when **none** of the three exists.

## When to invoke

- Any doc in § Doc-path resolution exists — `docs/<app>/business-logic-index.md` (AI-default), `docs/<app>/business-logic.md`, or `docs/en/business-logic.md` (`app-business-docs` canonical) — AND a fix/improvement touches business behavior. If several exist, the index is the primary guard layer; narratives are supplementary.
- Operator says "don't break the business logic", "does this change behavior".
- During Implement / post-gate fixes on an app that has documented logic.

## Do not invoke when

- **None of the § Doc-path resolution paths exists** (`docs/<app>/business-logic-index.md`, `docs/<app>/business-logic.md`, `docs/en/business-logic.md`) → silent no-op; do not create any of them (author deliberately via `app-business-docs` — which writes `docs/en/business-logic.md` — or the FR-23 `business-logic-index` template).
- Net-new feature with no documented logic yet.
- Pure cosmetic edits.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Business logic doc | any § Doc-path resolution path: `docs/<app>/business-logic-index.md` / `docs/<app>/business-logic.md` / `docs/en/business-logic.md` | **STOP — no-op** only if ALL three absent. Author via `app-business-docs` (→ `docs/en/business-logic.md`) or the FR-23 index template if wanted. |
| The change in progress | current diff/plan | nothing to check; exit |

## Procedure

1. **Existence gate (FIRST STEP).** Check ALL § Doc-path resolution paths: `docs/<app>/business-logic-index.md`, `docs/<app>/business-logic.md`, `docs/en/business-logic.md`. None exists → exit silently; do not create any. At least one exists → it is the guard layer (index primary).
2. **Read** the documented business logic / main flows / edge cases.
3. **Impact-check.** Does the change alter, remove, or contradict any documented behavior or edge case?
4. **Verify against code** — the doc is the navigation layer; confirm the actual code path matches before trusting the doc (code is source of truth).
5. **Compute and emit** the Required output block below using the impact answer and code verification.
6. **Flag** any documented behavior the change would break; recommend preserving it or, if the change is intentional, updating the doc (via `app-business-docs`) in the same change.
7. **Ambiguity → ask** operator (FR-19).

## Worked example

Change: allow editing approved invoices; `BL-7` says approved invoices are immutable. Code check: `src/invoices/service.ts:updateInvoice()` enforces the lock.

```
Business logic: Drift
Guard source:   docs/billing/business-logic-index.md — BL-7
Code check:     src/invoices/service.ts:updateInvoice() — matches doc
Action:         preserve behavior
```

## Required output — business-logic impact verdict (4 lines)

Every activation that reaches step 3 MUST emit this block after step 4's code verification, in chat and verbatim into the gate/ticket note when one is written. An impact-check claim without the block is unverifiable and does not count as a check.

```
Business logic: <Preserved | Drift | Blocked (intent unclear, FR-11)>
Guard source:   <business-logic doc path + rule/flow/edge-case identifier>
Code check:     <source path/symbol — matches doc | doc stale | behavior differs>
Action:         <proceed | preserve behavior | update doc in same change | question for operator (FR-19)>
```

## Output artifacts

| Artifact | Location | Mode |
|---|---|---|
| Business-logic impact verdict block (4 lines, above) | chat / gate note | Mode A / Mode-B-lite |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact absent | step 1 | silent no-op (correct) |
| Change breaks documented behavior | step 3 | flag; preserve or update-doc-in-same-change |
| Doc disagrees with code | step 4 | trust code; note the doc is stale; suggest refresh |

## Escalation path

- Intentional behavior change → update whichever guard doc is in use in the same change (narratives via `app-business-docs`, which maintains `docs/en/business-logic.md`; the index via the FR-23 `business-logic-index` template).
- Conflict with a locked decision → ask operator (FR-11/FR-19).

## Anti-patterns

- Do not activate/create the doc when absent.
- Do not trust the doc over the code (verify).
- Do not silently change documented behavior without flagging it.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.
