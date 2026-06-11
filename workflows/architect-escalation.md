# Workflow: architect-escalation

> **Style:** Mode-B-lite. Optional fresh-eyes investigation session for tickets that warrant it.

## Purpose

The merged Product Owner role does most investigation inline. For tickets with large investigation surface, cross-cutting refactor, or platform-blocker diagnosis, escalating to a separate fresh-eyes architect session can produce better decisions.

## When to escalate

| Signal | Reason |
|---|---|
| Investigation surface > 10 files across multiple subsystems | PO context will get heavy; fresh session has clean slate |
| Cross-cutting refactor with subtle interactions | Independent diagnosis catches what familiarity misses |
| Platform / vendor blocker suspected | Fresh eyes may spot misdiagnosis |
| Product Owner context is getting stale (long session, many tickets) | Fresh session resets context budget |

## When NOT to escalate

- Ticket is straightforward (1–2 files, well-known pattern)
- Operator just wants a fast turnaround on a small change
- The clarify phase already resolved the ambiguity

## Procedure

1. Product Owner identifies the ticket warrants escalation. State explicitly to operator:
   > "This ticket warrants fresh-eyes review because <reason>. Drafting architect handoff."
2. Draft architect handoff using the template below.
3. Save to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-architect.md` BEFORE outputting in chat (FR-04).
4. Tell operator: "Architect handoff saved to <path>. Open and paste into a fresh AI agent session as Architect's first message. Architect will investigate independently and report back."
5. When operator pastes architect's report, review it:
   - Spec / decisions / tasks / verification-gate produced
   - Constitution invariants honored
   - Decision recommendations have alternatives + reasoning
6. Recommend locks or redirects to operator. Operator confirms per FR-11.
7. Continue with normal flow from `implementation-planning` (drafting implementer green-light).

## Architect-side procedure

1. Read mandatory pre-execution files:
   - `FLOW_RULES.md`
   - `flow-skills/repo-onboarding-context-map/SKILL.md` (for investigation discipline)
   - `AGENTS.md` (project-specific section)
   - `docs/backlog/<slug>/README.md` (the seed ticket)
2. Self-attest as Architect (escalation):
   > "Operating as Architect (escalated session) under Fusebase Flow v3.19.0. I will follow FR-01 through FR-25. I will produce spec/decisions/tasks/verification-gate per templates and apply Mode B to every artifact I write. I will NOT lock decisions on operator's behalf — recommendations only. I will apply the role-discipline skill section for Architect (AR.1..AR.9) and use its refusal phrasing when an action would violate a rule."
3. Investigate the surface listed in the architect handoff.
4. Produce all four artifacts in `docs/specs/<slug>/`:
   - `spec.md` (DRAFT)
   - `decisions.md` (PENDING locks)
   - `tasks.md` (T-numbered)
   - `verification-gate.md`
5. Record any tech-stack validation or schema findings in `spec.md` (architecture/design sections) — no separate research/data-model files.
6. Report back to operator **using `templates/architect-response.md`** (v2.6.0+). The template includes a section-12 operator-relay block that the operator copies into PO chat — per FR-16, you (Architect) compose this block so the operator doesn't have to scan the technical body to figure out what to tell PO.

## Architect handoff template

```markdown
# Architect handoff — <slug> (<YYYY-MM-DD>)

**Status:** awaiting Architect investigation
**Reason for escalation:** <one-liner: large surface / cross-cutting / platform blocker / context heavy>

## Mandatory pre-execution reads

1. `FLOW_RULES.md`
2. `flow-skills/repo-onboarding-context-map/SKILL.md` (investigation discipline)
3. `AGENTS.md` (project-specific section)
4. `docs/backlog/<slug>/README.md` (seed ticket)

## What you're producing

- `docs/specs/<slug>/spec.md` (DRAFT, sections per templates/spec.md)
- `docs/specs/<slug>/decisions.md` (letter-decisions <Letter>1+ with reasoning + alternatives + lock status PENDING)
- `docs/specs/<slug>/tasks.md` (T-numbered chain from T<next-T>)
- `docs/specs/<slug>/verification-gate.md`

## Project context

<concrete description of stack, constraints, recent precedents, what worker components are running>

## Investigation surface

Files to read:
- `<path>` — <what to look for>
- ...

Key questions:
- <Q1>
- <Q2>
- ...

## Critical-decision categories to cover

- <Letter>1. <most architectural choice>
- <Letter>2. <wire format / protocol>
- <Letter>3. <schema / type definition>
- <Letter>4. <worker-undisturbed scope assertion>
- <Letter>5. <mixed-fleet / backwards-compat>
- ...

## Working invariants

- Spec-before-code (FR-01)
- One-task-one-commit (FR-03)
- Worker-undisturbed (FR-07)
- Mode B for every artifact (FR-09)
- No production code edits (you're Architect, not AI Developer)

## Out of scope

- <item 1>
- <item 2>

## Final deliverable

When ready, summarize for operator:
- <Letter>1..<Letter>N decisions with reasoning
- Critical-path task chain T<first> → T<deploy>
- Estimated effort
- Manifest version bump (if applicable)

PO will review your output, recommend locks, and operator will confirm.
```

## Related

- `templates/architect-response.md` — **canonical architect response template** (v2.6.0+); Architect fills this when reporting back; section 12 is the operator-relay block per FR-16
- `flow-skills/requirements-specification/SKILL.md` — may invoke this workflow when surface is large
- `flow-skills/role-discipline/SKILL.md` — § Operator Relay Protocol (FR-16) used when operator pastes the architect response back to PO; Architect don't-list at `references/architect.md`
- `workflows/eight-phase-flow.md` — the canonical flow this slot-fills into
- `workflows/greenlight-implement.md` — the next handoff after architect output is locked