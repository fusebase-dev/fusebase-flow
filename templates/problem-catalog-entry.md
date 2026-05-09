# Problem: <one-liner title>

**Slug:** `<kebab-case-slug>`
**Filed:** <YYYY-MM-DD>
**Severity:** low | medium | high | production-blocker
**Status:** open | mitigated | resolved | known-limitation
**Filed by:** <operator name or "PO per HR-PO-15">

## Symptom

<1–3 sentences describing what the operator or system observed. Concrete, observable, with timestamps if known.>

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | <action> | <observed> |
| 2 | <action> | <observed> |
| 3 | <action> | <observed> |

Reproduces: <3/3 / 2/3 / 1/3 / 0/3 — see FR-10>

## Root cause

<2–4 sentences explaining the underlying cause once diagnosed. If still investigating, note "investigating" and the working hypothesis.>

## Why it matters

- <impact 1: who is affected, how>
- <impact 2>

## Mitigation / workaround

<concrete steps. If a permanent fix is in flight, link to the ticket.>

1. <step>
2. <step>

## Permanent fix

| Status | Detail |
|---|---|
| Filed as ticket | `docs/backlog/<slug>/README.md` |
| In progress | `docs/specs/<slug>/spec.md` |
| Shipped | `<commit SHA + date>` |
| Won't fix | <reason: out of scope, vendor responsibility, accepted limitation> |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- Operator says <pattern>
- Logs show <pattern>
- File path `<path>` shows <symptom>
- Vendor surface returns <error code / shape>

## Related

- `docs/specs/<slug>/decisions.md` — decisions made because of this problem
- `docs/skills/<slug>/SKILL.md` — project-internal skill if pattern recurred 3+ times
- `docs/problem-catalog/<other-slug>/problem.md` — adjacent or duplicate problem

## Audit log

| Date | Event | Source |
|---|---|---|
| <YYYY-MM-DD> | filed | <ticket / chat ref> |
| <YYYY-MM-DD> | mitigated | <commit / handoff> |
| <YYYY-MM-DD> | resolved | <commit / deploy> |
