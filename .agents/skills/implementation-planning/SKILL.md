---
name: implementation-planning
description: Use after spec is drafted to plan implementation; produces decisions, tasks, verification-gate, and implementer handoff. Do NOT write code, do NOT lock decisions on operator's behalf, do NOT run before spec exists.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 0.1
risk_level: medium
invocation: automatic
expected_outputs:
  - docs/specs/<slug>/decisions.md
  - docs/specs/<slug>/tasks.md
  - docs/specs/<slug>/verification-gate.md
  - docs/handoff/<YYYY-MM-DD>-<slug>-implement.md
related_workflows:
  - eight-phase-flow.md
  - greenlight-implement.md
  - architect-escalation.md
hook_dependencies:
  - none
---

# Implementation Planning

## Purpose

Convert a drafted spec into the artifacts an Implementer session needs to execute: a letter-decision matrix, a numbered task chain, a verification-gate contract, and a saved handoff prompt.

## When to invoke

- Active phase is `Plan` or `Decisions` (per FLOW_RULES state announcement)
- A spec exists at `docs/specs/<slug>/spec.md` with status `DRAFT` and clarify questions resolved
- Operator says "plan this" / "draft decisions" / "let's break this into tasks"

## Do not invoke when

- Spec status is still `DRAFT` with unresolved clarify questions (re-invoke `requirements-specification` instead)
- Spec is `LOCKED` and decisions/tasks already exist (use `code-review` or `validation-and-qa` instead)
- Operator wants to skip planning and start coding directly — STOP. FR-02 (plan before edit) requires written tasks.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Spec | `docs/specs/<slug>/spec.md` (status DRAFT) | Re-invoke `requirements-specification` |
| Acceptance criteria | numbered AC1..ACn in spec | Stop; ask operator to add ACs |
| Letter prefix | `AGENTS.md` project-specific section | Default `A`; increment per ticket |
| T-counter | `AGENTS.md` project-specific section | Default `T1`; increment monotonically across all tickets |

## Procedure

1. Re-read spec.md and the acceptance criteria.
2. Identify architectural choices that need explicit decisions. Each choice gets a letter (e.g., `G1`, `G2`, ... where `G` is the ticket's letter prefix).
3. Draft `decisions.md` using `templates/decisions.md`. For each decision: recommendation, reasoning, alternatives considered (with rejection reasons), lock status PENDING.
4. Draft `tasks.md` using `templates/tasks.md`. Number tasks T<n>, T<n+1>, ... starting from current T-counter. Mark dependency edges. Identify the verification-gate task (T<gate>) and deploy task (T<deploy>).
5. Draft `verification-gate.md` using `templates/verification-gate.md`. Include: gate-report required fields, smoke prompts (numbered S1..Sn) if user-facing, probe list, rollback procedure.
6. Run cross-artifact consistency check: every AC mapped to at least one task; every locked decision cited in at least one task; every task lands a worker-undisturbed check or notes N/A.
7. Present decisions for lock in chat (Mode A — comparison table when there are 3+ alternatives). End with explicit lock prompt: "Reply 'lock' to approve all as recommended, OR 'redirect <Letter><n>' to change."
8. Wait for operator lock confirmation per FR-11. Implicit approval ("ok", "looks good") does NOT count.
9. After lock: increment letter prefix and T-counter in `AGENTS.md`. Update `tasks.md` SHAs to LOCKED.
10. Draft implementer handoff using `templates/handoff-folder-README.md` informed shape; save to `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md` BEFORE outputting in chat (FR-04).
11. Tell operator: "Implement handoff saved to <path>. Open that file, paste into a fresh AI agent session as Implementer."

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| Decisions | `docs/specs/<slug>/decisions.md` | Mode B (full) |
| Tasks | `docs/specs/<slug>/tasks.md` | Mode B (full) |
| Verification gate | `docs/specs/<slug>/verification-gate.md` | Mode B (full) |
| Implement handoff | `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md` | Mode B (full) |
| Updated counters | `AGENTS.md` project-specific section | Human-readable |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Spec lacks numbered ACs | scan spec.md for `AC1..` | Stop; ask operator to add ACs to spec |
| Decision has no concrete alternatives | Single recommendation with no "Alternatives considered" rows | Surface this as a clarify Q rather than locking a single-option "decision" |
| Task chain has cycle | tasks.md dependencies graph has cycle | Stop; redraft to break the cycle |
| Constitution violation in plan | spec violates worker-undisturbed list or mixed-fleet rule | Stop; redirect spec OR amend project-specific rules |

## Escalation path

- 12+ tasks needed → propose ticket split via `requirements-specification` re-invoke
- Cross-cutting refactor with subtle interactions → propose architect escalation via `workflows/architect-escalation.md`
- Stack/framework expertise gap → invoke `repo-onboarding-context-map` for the unfamiliar area first

## Anti-patterns

- Do NOT lock decisions on operator's behalf (FR-11)
- Do NOT skip the cross-artifact consistency check
- Do NOT output the handoff prompt in chat without saving to disk first (FR-04)
- Do NOT increment letter prefix or T-counter before operator confirms lock
- Do NOT include code edits in tasks.md beyond the file-and-scope description; the implementer writes the code

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
