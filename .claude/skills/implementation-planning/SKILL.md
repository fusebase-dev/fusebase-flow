---
name: implementation-planning
description: Use after spec is drafted to plan implementation; produces decisions, tasks, verification-gate, and implementer handoff. Do NOT write code, do NOT lock decisions on operator's behalf, do NOT run before spec exists.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: medium
invocation: automatic
expected_outputs:
  - docs/specs/<slug>/decisions.md
  - docs/specs/<slug>/tasks.md
  - docs/specs/<slug>/verification-gate.md
  - docs/tmp/handoff/<YYYY-MM-DD>-<slug>-implement.md
related_workflows:
  - eight-phase-flow.md
  - greenlight-implement.md
  - architect-escalation.md
hook_dependencies:
  - none
---

# Implementation Planning

## Purpose

Convert a drafted spec into the artifacts an AI Developer session needs to execute: a letter-decision matrix, a numbered task chain, a verification-gate contract, and a saved handoff prompt.

## When to invoke

- Active phase is `Plan` or `Decisions` (per FLOW_RULES state announcement)
- A spec exists at `docs/specs/<slug>/spec.md` with status `DRAFT` and clarify questions resolved
- Operator says "plan this" / "draft decisions" / "let's break this into tasks"

## Do not invoke when

- Spec status is still `DRAFT` with unresolved clarify questions (re-invoke `requirements-specification` instead)
- Spec is `LOCKED` and decisions/tasks already exist (use `code-review` or `validation-and-qa` instead)
- Operator wants to skip planning and start coding directly — STOP. FR-02 (plan before edit) requires written tasks.

## Documentation tier gate (FR-23)

Before drafting any planning artifact, apply the tier from `flow-skills/documentation-budget/SKILL.md` (don't duplicate it). Create each artifact ONLY when its trigger holds:

| Artifact | Create only when |
|---|---|
| `decisions.md` | a **real** decision exists — alternatives with rejection reasons or a locked tradeoff to preserve. No real decision → omit the file (do not write single-option "decisions"). |
| `tasks.md` | Tier 3/4 (multi-file Full-lane work). Reference ACs by pointer (`spec.md` AC1..ACn); do not reprint them. |
| `verification-gate.md` | Full lane **or** `policies/required-artifacts.yml` / `policies/gate-contracts.yml` requires it for this tier. |
| implement handoff | a fresh AI Developer session will execute the chain. Point to canonical spec/decisions/tasks; do NOT reprint them. |

Fail-safe: when unsure, choose the higher tier. Never weaken a safety artifact required by policy to "save docs". (Lightweight-eligible work should not reach this skill — it takes the change-note path in `requirements-specification`.)

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Spec | `docs/specs/<slug>/spec.md` (status DRAFT) | Re-invoke `requirements-specification` |
| Acceptance criteria | numbered AC1..ACn in spec | Stop; ask operator to add ACs |
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Continue with Flow-only planning, but mark CLI domain assumptions unknown |
| Letter prefix | `AGENTS.md` project-specific section | Default `A`; increment per ticket |
| T-counter | `AGENTS.md` project-specific section | Default `T1`; increment monotonically across all tickets |

## Procedure

1. Re-read spec.md and the acceptance criteria.
2. For Fusebase Apps tickets, read `docs/fusebase-cli-edition.md` and list the CLI domain skills that should inform decisions, tasks, gate probes, or deploy handoff. Cite the relevant skill names; do not duplicate their runtime instructions in Flow artifacts.
3. Identify architectural choices that need explicit decisions. Each choice gets a letter (e.g., `G1`, `G2`, ... where `G` is the ticket's letter prefix).
4. Draft `decisions.md` using `templates/decisions.md` — ONLY if step 3 surfaced a real decision with alternatives (FR-23; otherwise omit the file). For each decision: recommendation, reasoning, alternatives considered (with rejection reasons), lock status PENDING. If the decision needs divergent product/UI/workflow alternatives, invoke `flow-skills/design-discovery-ideation/SKILL.md` first so the options are meaningfully different, not cosmetic variants.
5. For frontend/UI tickets, add an implementation-ready design brief to decisions or the implement handoff: selected direction, product identity, routes/screens/workflows, data types and fields, API/helper names and signatures when known, applicable stack conventions/project frontend rules, stable test selector strategy, trust-critical real interactions, and explicit non-goals.
6. Draft `tasks.md` using `templates/tasks.md`. Number tasks T<n>, T<n+1>, ... starting from current T-counter. Mark dependency edges. Identify the verification-gate task (T<gate>) and deploy task (T<deploy>). **Module-size check (FR-25): every task names its target file(s).** For each target over the `policies/module-size.yml` ceiling (or that the task would push over it), the task must either (a) state the extraction — new module name + the responsibility seam — or (b) carry a one-line exemption with reason for operator approval. "Where does this code live" is decided here, at Plan — mid-implement it is never asked, which is exactly how monoliths accrete. Full rule: `flow-skills/module-size-discipline/SKILL.md`.
7. Draft `verification-gate.md` using `templates/verification-gate.md` — when Full lane or gate policy requires it (FR-23). If user-facing/operator-facing smoke is needed, invoke `flow-skills/smoke-testing/SKILL.md` before writing S1..Sn. Include: gate-report required fields, outcome-based smoke prompts, probe list, rollback procedure.
8. Run cross-artifact consistency check: every AC mapped to at least one task; every locked decision cited in at least one task; every task lands a worker-undisturbed check or notes N/A.
9. Present decisions for lock in chat (Mode A — comparison table when there are 3+ alternatives). End with explicit lock prompt: "Reply 'lock' to approve all as recommended, OR 'redirect <Letter><n>' to change."
10. Wait for operator lock confirmation per FR-11. Implicit approval ("ok", "looks good") does NOT count.
11. After lock: increment letter prefix and T-counter in `AGENTS.md`. Update `tasks.md` SHAs to LOCKED.
12. Draft implementer handoff using `templates/handoff-folder-README.md` informed shape; save to `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-implement.md` BEFORE outputting in chat (FR-04). Per FR-23, the handoff points to canonical `spec.md` / `decisions.md` / `tasks.md` (cite paths + AC/decision IDs); it must NOT reprint their contents.
13. Tell operator: "Implement handoff saved to <path>. Open that file, paste into a fresh AI agent session as AI Developer."

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| Decisions | `docs/specs/<slug>/decisions.md` | Mode B (full) |
| Tasks | `docs/specs/<slug>/tasks.md` | Mode B (full) |
| Verification gate | `docs/specs/<slug>/verification-gate.md` | Mode B (full) |
| Implement handoff | `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-implement.md` | Mode B (full) |
| Updated counters | `AGENTS.md` project-specific section | Human-readable |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Spec lacks numbered ACs | scan spec.md for `AC1..` | Stop; ask operator to add ACs to spec |
| Decision has no concrete alternatives | Single recommendation with no "Alternatives considered" rows | Surface this as a clarify Q rather than locking a single-option "decision" |
| Task chain has cycle | tasks.md dependencies graph has cycle | Stop; redraft to break the cycle |
| Constitution violation in plan | spec violates worker-undisturbed list or mixed-fleet rule | Stop; redirect spec OR amend project-specific rules |
| Frontend plan lacks real interaction contract | handoff names screens but not data/actions/API surfaces | Amend design brief before locking tasks |
| Frontend plan lacks selector strategy | UI smoke will need brittle text/CSS selectors | Add stable selector guidance before handoff |

## Escalation path

- 12+ tasks needed → propose ticket split via `requirements-specification` re-invoke
- Cross-cutting refactor with subtle interactions → propose architect escalation via `workflows/architect-escalation.md`
- Product/UI direction unclear or operator asks for options → invoke `design-discovery-ideation` before locking decisions
- Stack/framework expertise gap → invoke `repo-onboarding-context-map` for the unfamiliar area first

## Anti-patterns

- Do NOT lock decisions on operator's behalf (FR-11)
- Do NOT skip the cross-artifact consistency check
- Do NOT output the handoff prompt in chat without saving to disk first (FR-04)
- Do NOT increment letter prefix or T-counter before operator confirms lock
- Do NOT include code edits in tasks.md beyond the file-and-scope description; the implementer writes the code
- Do NOT create `decisions.md` when no real decision was made (FR-23) — a single-option "decision" is not a decision
- Do NOT reprint spec ACs, full problem statement, or product rationale in `tasks.md` or the handoff (FR-23) — point to the canonical owner
- Do NOT create `verification-gate.md` when neither Full lane nor gate policy requires it (FR-23)
- Do NOT plan a task onto an over-ceiling file without an extraction or an explicit exemption (FR-25) — defaulting new code into the existing big file is how monoliths grow

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
