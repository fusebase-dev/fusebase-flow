---
name: design-discovery-ideation
description: Use when the operator asks for options, variations, alternatives, product/UI directions, or divergent ideation before a spec or decision is locked. Do NOT use for deterministic edits, post-lock implementation changes, simple bug fixes, or AI Developer invention of new product direction.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: medium
invocation: automatic
expected_outputs:
  - option brief in chat or clarify conversation
  - alternatives matrix for spec.md or decisions.md
  - selected direction handoff to implementation-planning
related_workflows:
  - eight-phase-flow.md
  - architect-escalation.md
hook_dependencies:
  - none
---

# Design Discovery Ideation

> **Style:** Mode-B-lite. Divergent product/UI exploration before decisions lock; no production code.

## Purpose

Help the Product Owner turn "show options" / "try approaches" requests into clear, bounded alternatives before implementation. The skill separates fixed constraints from open design dimensions, presents 2-4 meaningfully different directions, and feeds the chosen direction into `spec.md` or `decisions.md`.

## When to invoke

- Operator asks for options, variations, alternatives, ideas, directions, or other possible shapes.
- A UI, workflow, prompt, dashboard, or product behavior needs divergent exploration before lock.
- `requirements-specification` finds unclear product framing or user experience scope.
- `implementation-planning` needs real alternatives for a decision instead of a single recommendation.
- Architect escalation is active and the design space spans multiple files, flows, or constraints.

## Do not invoke when

- The task is a deterministic bug fix with known expected behavior.
- A relevant decision is already LOCKED; AI Developer must implement or stop and surface a conflict.
- Operator asks for direct implementation, not option discovery.
- The only requested change is a narrow styling tweak with no product/design ambiguity.
- Required context is unavailable and cannot be inspected read-only.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Operator intent | chat, backlog ticket, or `spec.md` | Ask one chat-text clarify question; no popup tools |
| Affected surface | file paths, route, workflow, prompt, component, or user journey | Identify likely surface with read-only search; if unclear, ask |
| Constraints | `AGENTS.md`, `docs/constitution.md`, policies, locked decisions | Read before proposing options |
| Current implementation/context | repo files, screenshots, docs, logs, or operator description | Note confidence level; avoid over-specific recommendations |
| Frontend/product inputs (if applicable) | routes, components, data contracts, API helpers, brand/source assets | Mark unknown; do not invent product surface |
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Continue with Flow-only ideation, but mark CLI UI/runtime assumptions unknown |
| Decision owner | operator via PO | Never lock the choice on the operator's behalf |

## Procedure

1. Confirm role boundary.
   - Product Owner owns ideation and option recommendation.
   - Architect escalation may deepen read-only investigation.
   - AI Developer may only flag underspecified or conflicting design and return to PO.
2. Understand the current surface:
   - User goal and workflow position.
   - Information collected or shown.
   - Interaction states and failure states.
   - Existing structure and neighboring screens/prompts.
   - Constraints from spec, constitution, policies, accessibility, platform, and locked decisions.
   - For Fusebase Apps UI/product work, supporting CLI guidance from `app-ui-design`, `app-dev-practices`, or another relevant CLI skill named in `docs/fusebase-cli-edition.md`.
3. Separate design space:
   - **Fixed:** cannot change without violating scope, constraints, or locked decisions.
   - **Assumed:** current shape that may be changed if operator chooses.
   - **Open:** dimensions worth exploring.
4. Pick 2-3 exploration dimensions that matter for this ticket. Examples:
   - Structure / flow order.
   - Content hierarchy / semantic framing.
   - Interaction behavior / state progression.
   - Visual tone / density when UI-facing.
   - Technical approach only when it changes product trade-offs.
5. Produce 2-4 options. Each option must have:
   - A short name.
   - Design hypothesis.
   - What changes.
   - What stays fixed.
   - Trade-off.
   - Verification or smoke implication.
6. For frontend/UI tickets, also draft an implementation-ready design brief:
   - Product identity and target user.
   - Selected option or option set.
   - Affected routes, pages, workflows, prompts, or components.
   - Data types, fields, states, and real interactions the UI must support.
   - API/helper surfaces by name/signature when known.
   - Applicable stack conventions or project-local frontend rules by path when known.
   - Stable test selector strategy for interactive and meaningful dynamic elements.
   - Trust-critical flows that must work with real behavior, not placeholders.
   - Brand/source inputs, only when provided or gathered from approved read-only sources.
   - Explicit non-goals: routes, entities, workflows, or visual constraints the implementer must not invent.
7. Recommend one option in chat text with **(Recommended)** marked. Do not use popup / clickable menu tools.
8. Wait for operator direction:
   - If approved, write the selected direction into `spec.md`, `clarify-conversation.md`, or `decisions.md` as appropriate.
   - If redirected, revise the options without preserving stale discarded content in authoritative artifacts.
   - If unresolved, leave status DRAFT / PENDING and name the blocking question.
9. If delegated investigation is useful, invoke `task-delegation` with a read-only/doc-only brief. The brief must include the selected exploration dimensions and forbid code edits unless the session is AI Developer and the task is already locked.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Option brief | chat text | Mode A |
| Clarify record | `docs/specs/<slug>/clarify-conversation.md` | Mode B |
| Decision alternatives | `docs/specs/<slug>/decisions.md` | Mode B |
| Spec updates | `docs/specs/<slug>/spec.md` | Mode B |
| Implementation-ready design brief | `docs/specs/<slug>/decisions.md` or implement handoff | Mode B |
| Delegation brief | chat or handoff section | Mode-B-lite |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Options are just reskins | Same structure, hierarchy, and behavior across all options | Redraft around a stronger dimension before presenting |
| Hidden locked decision | `decisions.md` already fixes the disputed direction | Stop; ask whether to redirect the decision |
| AI Developer invents new direction | Implementation diverges from locked spec/decision | Stop under IM.2 and return to PO |
| Frontend brief omits real interactions | UI work would rely on placeholders for primary actions | Amend brief with data/API/trust-critical flows before handoff |
| Frontend brief omits selector strategy | UI smoke would rely on brittle selectors | Add stable selector guidance before handoff |
| Operator wants only one answer | Operator says "just pick" | Recommend one option, but ask for explicit lock per FR-11 |
| Design space is too large | More than 4 plausible options or multiple workflows | Split into narrower decisions or invoke Architect escalation |

## Escalation path

- Cross-cutting product/workflow change -> `workflows/architect-escalation.md`.
- Need implementation sequencing -> `flow-skills/implementation-planning/SKILL.md`.
- Need smoke criteria for a UI/operator-facing outcome -> `flow-skills/smoke-testing/SKILL.md`.
- Need parallel read-only analysis -> `flow-skills/task-delegation/SKILL.md`.

## Prototype before build

Use when a UI / screen / app is about to be implemented and the operator would benefit from *seeing* it before code is written — cheap visual agreement avoids expensive rebuilds.

| Step | Action |
|---|---|
| 1. Mock in markdown | Draw the layout as an ASCII/box mockup in chat (Mode A) — structure, key elements, states. No code. |
| 2. Get feedback | Operator reacts to the mockup; iterate in chat until the shape is agreed. |
| 3. Optional HTML prototype | If a richer preview is needed, build a single throwaway static HTML page of the screen for visual testing — clearly a prototype, not the implementation. |
| 4. Then build | Only after the visual is agreed, hand the agreed shape to `implementation-planning` -> AI Developer. |

Pre-build prototyping is a generic technique (no project artifact needed). Keep prototypes disposable; the real build follows the locked direction. ASCII mockups belong in chat (Mode A), never embedded in Mode-B artifact files (FR-08).

## Anti-patterns

- Do not write production code from this skill.
- Do not treat an HTML prototype as the real implementation — it is throwaway.
- Do not present only one option unless the operator explicitly narrowed the choice.
- Do not produce alternatives that differ only by color, wording, or spacing unless the operator asked for that narrow axis.
- Do not prescribe exact UI structure, colors, typography, spacing, or component patterns unless the operator explicitly made them constraints.
- Do not let UI implementation briefs omit real data, states, and primary interactions.
- Do not bury the recommendation in prose; mark it clearly.
- Do not lock a direction without operator approval.
- Do not use popup / clickable menu tools; options must be written in chat text per FR-19.
- Do not let AI Developer use ideation to bypass locked decisions.

## Clean-room note

Original Fusebase Flow content. Derived from operator-provided capability requirements and generalized into repo-local workflow discipline; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
