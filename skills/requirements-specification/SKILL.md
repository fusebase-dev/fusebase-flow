---
name: requirements-specification
description: Use when operator starts a new ticket ("ship X", "build Y", "add feature", "fix workflow") and no spec exists; produces spec, clarify questions, acceptance criteria. Do NOT use for code edits, mid-flight reorgs, or after a spec is locked.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
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
- Task is a one-line bug fix that does not need clarify (see "Skip-clarify gate" below)

## Skip-clarify gate (when "skip clarify" is allowed)

The clarify phase exists to surface hidden ambiguity before code is written. Skipping it has a cost — undetected ambiguity surfaces later as wrong-direction code or operator-rework. Skip ONLY when ALL of the following hold:

| Skip condition | Concrete check |
|---|---|
| Single file, single function | Affects exactly one file; one named function or contiguous block |
| No new dependency / API / config | No `package.json`, no env var, no policy file change |
| Acceptance criterion fits in one sentence | "X now returns Y instead of Z" or equivalent |
| Operator typed "skip clarify" verbatim | Not inferred from "this is small" |
| No constitution-invariant question raised | Worker-undisturbed, mixed-fleet, auth gates all unaffected |

If ANY condition is unmet: run clarify, even if the operator pushes for speed. The phrase "the spec for a small fix is two paragraphs" applies (per `docs/operator-discipline.md` OD-6).

When skipping: spec.md is still drafted (DRAFT → LOCKED in same step), but the clarify-conversation.md file is replaced by a one-line note: `Clarify skipped per operator request; ticket meets skip-clarify gate (see requirements-specification/SKILL.md).`

## Phase 1 / Phase 2 split (diagnostic vs fix)

For bug investigation tickets where the root cause is unknown, split the spec into two phases:

**Phase 1 — Diagnostic.** Acceptance criterion is "we can name the root cause + cite evidence". No production code change. Output: an investigation note in `docs/specs/<slug>/diagnostic.md` with reproduction steps, suspected component, and evidence (logs, traces, repro). The phase ends when the operator confirms the diagnosis.

**Phase 2 — Fix.** Drafted as a separate spec section (or separate spec file `<slug>-fix/spec.md`) AFTER Phase 1 closes. Acceptance criteria are concrete code changes; verification gate references the diagnostic.

Why split: collapsing both phases lets the implementer guess at fixes while the bug is still not understood — produces "shotgun debugging" commits and burns context. The split also makes it explicit when the operator should be asked "is the root cause confirmed?" before you write any code.

When NOT to split: the bug is already understood (e.g., known typo, obvious off-by-one, broken import). Single-phase spec is fine.

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
| Investigation reveals the ticket is wrong | During clarify, evidence shows the reported behavior is intentional, the bug is elsewhere, or the feature already exists | **Abort the ticket.** Mark spec status `ABORTED` with one paragraph: what was investigated, what was found, why no work follows. Move ticket back to `docs/backlog/<slug>/README.md` with status `aborted-on-investigation` so it doesn't reappear. Do NOT silently downscope to "fix the wrong thing instead." |
| Operator and clarify keep disagreeing on scope | After 2 rounds of clarify, the gap between operator's intent and what the spec captures is widening | Stop. Switch to a 1:1 clarify-only chat: ask the operator to restate the goal in 3 sentences. If the gap persists, escalate to architect (`workflows/architect-escalation.md`) — the framing problem is bigger than spec drafting can resolve. |

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
