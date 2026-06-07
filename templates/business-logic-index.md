# Business Logic Index — <project name or app/feature area>

> **Style:** Mode B (AI-readable retrieval index). DEFAULT format for business-logic docs in AI workflows (FR-23 / `flow-skills/documentation-budget/SKILL.md`). Table-first, not narrative. For an explicitly human-readable narrative doc, use `templates/business-logic.md` instead. Document observable implemented behavior only; mark intended-but-unbuilt behavior as such. Do not update for purely technical changes with no business-logic impact. Consumed by `business-logic-guardian` as a guard layer during fixes.

**Status:** current | partial | stale
**Last verified:** <YYYY-MM-DD>
**Source of truth:** code + tests (paths below). This index points; it does not restate.

## Invariants

| ID | Rule | Applies to | Source paths | Verified |
|---|---|---|---|---|
| INV1 | <rule that must always hold> | <entity/flow> | `<path:line>` | <date / Unknown> |

## Workflows

| ID | Trigger | Actor | System behavior | Edge cases | Source paths |
|---|---|---|---|---|---|
| WF1 | <event/input> | <user type/system> | <observable outcome> | <None / case> | `<path>` |

## Permissions

| Actor | Can | Cannot | Source paths |
|---|---|---|---|
| <role> | <action> | <action> | `<path>` |

## Data ownership

| Data | Owner | Storage | Mutation paths |
|---|---|---|---|
| <entity> | <component/role> | <table/store> | `<path>` |

## Edge cases

| Case | Expected behavior | Source paths |
|---|---|---|
| <condition> | <observable behavior> | `<path>` |

## Open questions

| ID | Question | Blocks | Owner |
|---|---|---|---|
| Q1 | <unresolved> | <what it blocks> | <operator/Unknown> |

## Notes

Use prose ONLY where a table loses meaning. Keep `Unknown` where unverified; keep `None` where a column has no entries. Audit history lives in git, not in this file.
