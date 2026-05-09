---
name: requirements-specification
description: Use when operator starts a new ticket ("ship X", "build Y", "add feature", "fix workflow") and no spec exists; produces spec, clarify questions, acceptance criteria. Do NOT use for code edits, mid-flight reorgs, or after a spec is locked.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 0.1
risk_level: low
invocation: automatic
expected_outputs:
  - docs/specs/<slug>/spec.md
  - docs/specs/<slug>/clarify-conversation.md
related_workflows:
  - eight-phase-flow.md
  - session-initiation.md
hook_dependencies:
  - none
---

# Requirements Specification

## Purpose

Turn vague operator intent into a versioned spec with explicit acceptance criteria, unresolved clarify questions, and risk notes. The output is the contract every later skill (planning, implementation, validation, code review, security, deploy) reads.

## When to invoke

- Operator says "let's ship <feature>" / "build <feature>" / "add <feature>" / "fix <workflow>" / "we need <capability>"
- Backlog ticket exists at `docs/backlog/<slug>/README.md` and operator says "promote it"
- Active phase is `Specify` or `Clarify` (per FLOW_RULES state announcement)

## Do not invoke when

- A spec at `docs/specs/<slug>/spec.md` already exists with status `LOCKED` or `DONE`
- Operator is asking how something already works (use code-review or repo-onboarding-context-map instead)
- Task is a one-line bug fix that does not need clarify (operator can short-circuit by typing "skip clarify")

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Backlog ticket or operator intent | `docs/backlog/<slug>/README.md` or chat | Ask operator for one-liner + why-now + rough scope |
| Constitution / project context | `FLOW_RULES.md` + project-specific values in `AGENTS.md` | Stop and ask operator to fill `AGENTS.md` project-specific section |
| Letter prefix in use | Project-specific section of `AGENTS.md` | Default to `A`; ask operator to confirm |

## Procedure

1. Read the backlog ticket (or capture operator intent in chat as a 1-paragraph problem statement).
2. Identify ambiguities. For each, draft a clarify question with 2–3 options + recommendation. Save to `docs/specs/<slug>/clarify-conversation.md` using `templates/clarify-conversation.md`.
3. Present clarify questions in chat (Mode A — visual when there are 3+ options to compare).
4. Wait for operator answers. Update `clarify-conversation.md` with locked answers.
5. Draft `docs/specs/<slug>/spec.md` using `templates/spec.md`. Status: DRAFT.
6. Spec must include: problem statement, why-now, in-scope, out-of-scope, acceptance criteria (numbered AC1..ACn), risks, constraints from FLOW_RULES (worker-undisturbed, mixed-fleet if applicable).
7. State announcement footer in chat: phase advances from `Specify` to `Plan` once spec.md is saved.

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| Spec | `docs/specs/<slug>/spec.md` | Mode B (full) |
| Clarify conversation | `docs/specs/<slug>/clarify-conversation.md` | Mode B (full) |
| Backlog index update (if promoted) | `docs/backlog/index.md` | Mode B (full) |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Operator can't answer clarify question | After 1 round, operator says "I don't know" | Park spec at `BLOCKED` status; file follow-up backlog ticket for the unknown |
| Backlog ticket conflicts with FLOW_RULES invariant | Constitution check fails | Stop. Ask operator to revise scope OR amend project-specific rules. Don't proceed silently. |
| Scope is actually two tickets | Spec needs >12 acceptance criteria, multiple deploys, or splits naturally | Stop. Propose splitting into `<slug>-a` and `<slug>-b` backlog tickets. |

## Escalation path

- Investigation surface > 10 files across multiple subsystems → propose architect escalation via `workflows/architect-escalation.md`
- Operator can't decide between two architectural directions → invoke `implementation-planning` skill in "decision-only" mode to surface trade-offs

## Anti-patterns

- Do not draft `decisions.md` here — that's `implementation-planning`'s job
- Do not draft `tasks.md` here — same
- Do not write production code (FR-01)
- Do not lock the spec on operator's behalf (FR-11) — operator confirms by saying "lock spec" or "redirect AC<n>"
- Do not skip the clarify phase if ambiguities exist; "I'll figure it out during implementation" is FR-11 violation

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
