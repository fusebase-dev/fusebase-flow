---
name: zoom-out
description: Use before committing a bug fix or improvement, when a fix is non-trivial, or when the same area has been patched before. Operationalizes FR-20 — zoom out to root cause before applying a narrow patch. Do NOT use for trivial typo/format edits, for net-new feature work with no prior code (nothing to zoom out from), or as a substitute for reproduce-before-fix (FR-10 / validation-and-qa).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.30.8
risk_level: low
invocation: automatic
expected_outputs:
  - a zoom-out check result (root-cause vs symptom; layer; consistency; drift risk)
  - either a root-cause fix plan, or a justified narrow-patch decision
  - escalation question to operator when the bigger picture is ambiguous
related_workflows:
  - eight-phase-flow.md
  - verification-gate.md
hook_dependencies:
  - none
---

# Zoom Out (FR-20)

> **Style:** Mode-B-lite. Concise, structured, AI-consumable.

## Purpose

Stop patch-myopia. Before fixing a bug or making an improvement, zoom out and confirm the change addresses the root cause and stays consistent with the bigger picture — instead of stacking a narrow patch that creates drift elsewhere. Operationalizes always-on rule FR-20.

## When to invoke

- About to commit a bug fix or behavior change that is non-trivial.
- The same file / function / area has been patched before (repeat-patch smell).
- A fix touches shared logic, data shape, an interface, or cross-app behavior.
- Operator says "fix X", "why does X keep breaking", "patch", "quick fix".
- Active phase is Implement or a post-gate fix.

## Do not invoke when

- Trivial typo / formatting / comment-only edit.
- Pure net-new feature with no existing code to reconcile against.
- The work is reproduce-before-fix itself (that is FR-10 / `validation-and-qa`) — run that first, then zoom out on the fix design.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| The observed symptom / bug | operator report, logs, test output | run reproduce-before-fix (FR-10) first |
| Spec / decisions (if under a ticket) | `docs/specs/<slug>/` | proceed; note no spec to check against |
| North Star (if present) | `docs/north-star.md` | skip the North-Star check silently (absent-by-default) |

## Procedure

1. **Name the symptom vs the cause.** State the visible failure, then the underlying cause. If you can only name the symptom, investigate before patching.
2. **Layer check.** Is this the right place to fix it? (UI symptom caused by a data/API bug → fix the source, not the surface.)
3. **Consistency check.** Does the fix contradict the spec, locked decisions, or `docs/north-star.md` (if present)? If yes → stop, raise it.
4. **Drift check.** Will this patch create inconsistency elsewhere (other apps, shared logic, future edits)? Prefer the change that reduces total inconsistency.
5. **Repeat-patch check.** Has this area been patched before? Two+ patches in one spot = treat as a design problem, not another patch.
6. **Decide — and emit the Required output block below.** Either (a) produce a root-cause fix plan, or (b) justify a deliberate narrow patch ("symptom-level fix is correct here because …"). Never an unexamined patch.
7. **Ambiguous bigger picture →** ask the operator in chat (FR-19); do not guess.

## Required output — zoom-out verdict (5 lines)

Emit before the fix lands — in chat, and verbatim into the gate/handoff note when one is written. The block is the checkable evidence FR-20 ran; a zoom-out claim without it is unverifiable.

```
Symptom:    <visible failure, one clause>
Root cause: <underlying cause, one clause — "unknown" forces investigation (FR-10), not a patch>
Layer:      <UI | API | data | shared logic | config> — fixing there? <yes | no + why>
Drift risk: <none | what becomes inconsistent elsewhere>
Decision:   <root-cause fix | justified narrow patch because <reason> | escalate (design problem / Architect)>
```

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Zoom-out verdict block (5 lines, above) | chat (Mode A) or gate/handoff note | Mode A / Mode-B-lite |
| Root-cause fix plan or justified-patch note | ticket artifact when applicable | Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Only the symptom is understood | cannot state root cause | investigate / reproduce before patching |
| Fix contradicts spec/decisions/North Star | step 3 finds conflict | stop; surface to operator (FR-11/FR-19) |
| Third patch to same area | step 5 | escalate to a design/refactor decision, not another patch |

## Escalation path

- Ambiguous bigger picture → ask operator in chat text (FR-19).
- Root cause spans >10 files / cross-cutting → Architect escalation (`workflows/architect-escalation.md`).
- Recurring problem → capture in `docs/problem-catalog/` (knowledge-curation).

## Anti-patterns

- Do not stack patch-on-patch to silence a symptom.
- Do not fix at the wrong layer because it is faster.
- Do not skip this for "small" fixes that touch shared logic.
- Do not replace reproduce-before-fix (FR-10) — complement it.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
