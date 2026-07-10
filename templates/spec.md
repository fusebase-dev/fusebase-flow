# Spec — <slug>

**Status:** DRAFT | DONE
<!-- tripwire: DRAFT until the deploy session flips it to DONE. "Locked" is NOT a status value — scope-lock is recorded in decisions.md (Lock status: LOCKED), the spec Status stays DRAFT. -->
**Scope lock:** <not locked | locked YYYY-MM-DD — decisions frozen; see decisions.md>
**Created:** <YYYY-MM-DD>
**Linked decisions:** <Letter>1..<Letter>N
**Promoted from:** `docs/backlog/<slug>/README.md`
**Deploy hash:** <captured at DRAFT → DONE flip>

## Problem

<2–4 sentences: what is broken / missing / friction-y. Concrete, observable.>

## Why now

<1–2 sentences: why this is being shipped now. Recent precedent / customer / constraint.>

## In scope

What this spec covers.

- <bullet>
- <bullet>

## Out of scope

What this spec does NOT cover. Pulls from backlog README "Out of scope" + any items added during clarify.

- <bullet>
- <bullet>

## Acceptance criteria

Numbered AC1..ACn. Each AC is observable and testable. Each AC is referenced in at least one task in `tasks.md`.

1. **AC1** — <observable outcome with concrete pass criterion>
2. **AC2** — <observable outcome>
3. **AC3** — <observable outcome>
4. ...

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths (`policies/protected-paths.yml`) | <touched files: list, or "none"> |
| Mixed-fleet considerations | <addressed: how, or "N/A"> |
| Migration approach | <"no migration" \| "migration with documented blocker workaround"> |
| Auth model | <endpoint auth gates correct: yes/no with detail> |
| Quality bar (lint/typecheck/tests) | <added: count + locations> |

## Wire format (if applicable)

API request/response shapes, types added/changed, schema deltas.

```ts
// example
type SkipFlags = { transcript?: boolean; ... }
```

## Backend changes

File-by-file scope.

- `<path/to/file.ts>` — <scope>
- `<path/to/another.ts>` — <scope>

## Client / extension / SPA changes

- `<path>` — <scope>
- `<path>` — <scope>

## Risks

- <risk + mitigation>
- <risk + mitigation>

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | <one-liner> | <date> |
| Q-B | <one-liner> | <date> |

(Or "clarify skipped per operator request — no ambiguities surfaced.")

## Related

- `docs/specs/<slug>/decisions.md`
- `docs/specs/<slug>/tasks.md`
- `docs/specs/<slug>/verification-gate.md`
- `docs/tmp/handoff/<date>-<slug>-implement.md` (when filed)
- `docs/tmp/handoff/<date>-<slug>-deploy.md` (when filed)
