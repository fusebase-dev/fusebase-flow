---
name: documentation-budget
description: Use before creating, expanding, or revising any AI-consumed documentation artifact (spec, decisions, tasks, verification-gate, handoff, backlog, problem-catalog, product/business-logic docs, project-internal skills). Classifies whether a persistent doc is needed, which tier applies, and how to minimize context cost. Operationalizes FR-23 — documentation budget. Prevents duplicate rationale, narrative padding, and docs created merely because a template exists. Do NOT use for operator chat, source comments (that's `comment-policy`), or purely human-facing files (README/LICENSE/PUBLISHING).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.12
risk_level: low
invocation: automatic
expected_outputs:
  - a documentation tier classification (0-4) for the artifact request
  - the minimal artifact set for that tier, with canonical ownership assigned
  - pointer-over-duplication guidance (cite the owner, do not restate)
related_workflows:
  - eight-phase-flow.md
  - session-initiation.md
hook_dependencies:
  - none
---

# Documentation Budget

> **Style:** Mode-B-lite. Pre-write classifier for AI-consumed artifacts. Operationalizes FR-23. Reference this skill from doc-producing skills; do not duplicate it.

## Purpose

Make documentation proportional to risk, complexity, and future AI value. An AI-consumed artifact is created only when it reduces future context cost more than it adds. Duplicate rationale, narrative padding, and unnecessary persistent docs are paid in tokens on every future load and spawn stale conflicting copies. This is the documentation-axis complement to FR-21 (`lightweight-lane`, which scales process ceremony): FR-21 decides how much *process* a change carries; FR-23 decides how much *persistent documentation* it leaves behind.

## When to invoke

Before creating, expanding, or revising any of:

- `docs/specs/<slug>/spec.md`, `decisions.md`, `tasks.md`, `verification-gate.md`
- `docs/tmp/handoff.md` (active session continuity)
- `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-{implement,deploy}.md` (formal role-relay)
- `docs/changes/<date>-<slug>.md` (Lightweight change-note)
- `docs/backlog/**`, `docs/problem-catalog/**`
- `docs/<app>/product.md`, `docs/<app>/business-logic.md`, `docs/<app>/business-logic-index.md`
- project-internal skills under `docs/skills/**`
- any persistent AI-consumed doc not in the carve-out below

## Do not invoke when

- Writing operator chat only (Mode A).
- Writing or editing source comments — use `comment-policy` (FR-22).
- Editing human-facing files only: `README.md`, `LICENSE`, `PUBLISHING.md`, `CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` — unless the edit changes AI workflow behavior.
- No persistent artifact will be created or changed.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| The artifact request | operator intent / current ticket | Ask what future action the doc must enable |
| Change risk + size | spec / lane classification (`lightweight-lane`, FR-21) | Default to higher tier (fail-safe-up) |
| Existing artifacts | `docs/specs/<slug>/`, `docs/<app>/`, git history | Read before writing; prefer a pointer to an existing owner |

## Core rule (FR-23)

Before writing a persistent AI-consumed artifact, classify the documentation tier. If there is no clear future consumer, no future action enabled, and no gate requirement, **do not create the artifact.** Do not create a doc merely because a template exists.

## Classification questions

| # | Question |
|---|---|
| Q1 | Who is the next consumer — AI, human, or both? |
| Q2 | What concrete future action does this doc enable? |
| Q3 | Is this already captured in code, tests, git history, spec, decisions, tasks, or handoff? |
| Q4 | Can this be a pointer instead of duplicated text? |
| Q5 | Can this be a single Lightweight change-note (FR-21) instead? |
| Q6 | Will this artifact be loaded repeatedly by future AI sessions? |
| Q7 | Is the documentation cost proportional to the change risk? |

## Documentation tiers

| Tier | Name | Use when | Output |
|---|---|---|---|
| 0 | No persistent doc | transient exploration, no code change, already captured in code/tests/git/existing docs | none |
| 1 | Change-note | Lightweight-eligible change (FR-21): small, reversible, single-concern, mechanically verifiable, no security/permission/public-contract risk, root cause understood | a single change-note (`templates/change-note.md`) inline in the commit body or `docs/changes/<date>-<slug>.md` |
| 2 | Active handoff | long session restart, code mid-flight, no new product/architecture decision, next AI session needs exact continuation state | `docs/tmp/handoff.md` (superseded each session, FR-18; predecessors auto-archived to `docs/tmp/handoff/archive/` — dated history, never loaded) |
| 3 | Spec + tasks | multi-file Full-lane work, clear scope, few/no architectural decisions, no major security/migration/public-contract risk | `docs/specs/<slug>/spec.md` + `tasks.md`; `decisions.md` only if real decisions; gate per policy |
| 4 | Full pack | high-risk / ambiguous product behavior / new app / new public contract / permissions / auth / migrations / data ownership / cross-cutting architecture / deploy-sensitive | full Flow artifact chain — no duplicated rationale across artifacts |

**Lesson/incident routing:** a diagnosis lesson, recurring pattern, or platform quirk is not a ticket artifact in this tier table — route it via `workflows/knowledge-curation.md` (FR-15: problem-catalog entry or project-internal skill); its creation cost is still gated by FR-23.

**Fail-safe:** when unsure between two tiers, choose the higher one (mirrors FR-21's in-doubt→Full).

**Promotion:** if a Tier 0/1/2 change grows a security/permission/migration/public-contract concern or a real architectural decision mid-flight, STOP and reclassify upward before continuing (mirrors FR-21 mid-flight promotion).

## Artifact ownership (canonical owner; others point, never restate)

| Artifact | Owns | Must NOT duplicate |
|---|---|---|
| `spec.md` | WHAT, scope, acceptance criteria, externally visible behavior | full decision rationale |
| `decisions.md` | real locked choices, rejected alternatives, tradeoffs | full problem statement, full ACs |
| `tasks.md` | execution slices, file-level work, dependencies, validation commands | product rationale, full spec |
| `verification-gate.md` | gate status, proof, unresolved risk, approval status | task details beyond gate evidence |
| `docs/tmp/handoff.md` | active restart state, repo state, files in flight, failed attempts, single next action | full spec/decisions/tasks |
| `docs/tmp/handoff/*-{implement,deploy}.md` | formal role-relay prompt for a fresh session | full spec/decisions/tasks (point to canonical) |
| change-note | lightweight change proof + rollback + commit/deploy summary (FR-21) | full lifecycle docs (it replaces them for LL work) |
| `product.md` | long-lived product/app/workflow intent (`product-docs-first`) | implementation detail |
| `business-logic-index.md` | implemented rules/workflows as AI retrieval index | narrative onboarding |

## Active handoff path

Active session continuity uses **`docs/tmp/handoff.md`** — single file, superseded every session (FR-18), not an audit log. Active state goes in that top-level `.md`, never in the dated `docs/tmp/handoff/<...>` relay files. Formal role-relay prompts are dated siblings under the same folder:

| Path | Role |
|---|---|
| `docs/tmp/handoff.md` | Active restart state. Superseded every session. Point to canonical artifacts; `Unknown` not a guess; `None` not filler. |
| `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-implement.md` | Formal implement relay (`implementation-planning`), only when needed. |
| `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-deploy.md` | Formal deploy relay (`release-deploy-reporting`), only when needed. |

## Product docs rule

Defer to `product-docs-first`. Create or expand `product.md` ONLY for: new app, new product/workflow direction, new user type, major user-facing behavior change, long-lived business logic, or explicit operator request. Do NOT expand product docs for: simple bug fixes, refactors, copy-only changes, small UI adjustments, already-scoped implementation tickets, narrow technical fixes. If a product doc exists, read it to ground planning; do not rewrite it unless the work changes long-lived product intent.

## Business logic index rule

Default format for business-logic docs in AI workflows: **AI-readable retrieval index** (`templates/business-logic-index.md`) — tables for invariants, workflows, permissions, data ownership, edge cases, open questions; add `Source paths` wherever possible; document observable implemented behavior only (mark intended-but-unbuilt behavior as such). The human-narrative `templates/business-logic.md` is the secondary option, used only on explicit human-readable request. `business-logic-guardian` consumes whichever exists as a guard layer. Do not update either for purely technical changes with no business-logic impact. Use prose only where a table loses meaning.

## Pointer over duplication

Cite the canonical owner; never restate it.

Good: `Decision: B2. See decisions.md#b2.` / `Acceptance: AC1-AC3 (spec.md).` / `Failing test: groupAssignment.test.ts.` / `Next file: src/workflows/groupAssignment.ts.`

Bad: a doc that reprints full background, all decisions, all ACs, and all implementation detail already owned by other files.

## Procedure

1. Identify the artifact request (path + intent).
2. Run the classification questions (Q1-Q7).
3. Select the tier; if unsure, choose higher.
4. Reduce to the minimal artifact set for that tier.
5. Assign canonical ownership per the table; replace would-be duplication with pointers.
6. Supersede stale content (FR-18); do not accumulate.
7. Write Mode B / Mode-B-lite (no narrative padding, no chat visuals).
8. If scope/risk grows mid-flight, reclassify upward and stop for promotion.

## Output artifacts

| Output | When |
|---|---|
| no persistent doc | Tier 0 |
| change-note (`templates/change-note.md`) | Tier 1 |
| `docs/tmp/handoff.md` | Tier 2 |
| `spec.md` + `tasks.md` (+ decisions if real) | Tier 3 |
| full Flow artifact chain | Tier 4 |
| tier classification + ownership note in chat (Mode A) | every invocation |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Artifact has no clear consumer/action | Q1-Q2 fail | Do not create. |
| Same rationale in 2+ artifacts | duplicate content | Keep canonical owner; replace others with a pointer. |
| Handoff reprints full spec | handoff too long | Replace body with canonical links + current state. |
| Product doc expanded for small fix | no product-intent change | Revert the expansion. |
| Business doc is narrative-heavy | paragraphs dominate | Convert to retrieval tables (`business-logic-index.md`). |
| Lightweight work grew risky | security/decision/migration appears | Stop; promote tier (and Full lane per FR-21). |
| Active continuity written to `docs/tmp/handoff/` | wrong path | Move to `docs/tmp/handoff.md`. |

## Escalation path

- Product ambiguity → ask operator in chat (FR-19).
- Architecture ambiguity → `workflows/architect-escalation.md`.
- Risk / security / migration / public contract → Tier 4 (Full) + FR-12 approval gate.
- Recurring documentation bloat across 3+ tickets → propose a rule/template update (operator decides).

## Anti-patterns

- Creating a doc because a template exists.
- Creating `decisions.md` with no real decision or rejected alternative.
- Repeating full ACs in `tasks.md` when `spec.md` owns them.
- Reprinting the full spec inside a handoff.
- Appending "resumption notes" above stale handoff content (FR-18).
- Using `docs/tmp/handoff/` for active continuity.
- Writing business-logic docs as long prose when tables would work.
- Expanding `product.md` for small fixes/refactors.
- Treating git history as content to copy into docs.
- Adding human-onboarding explanation into AI-only artifacts.

## Clean-room note

Original Fusebase Flow content. The "documentation proportional to value" principle is common to mature engineering-doc practice; no third-party code, prompts, or skill files are copied. See `docs/source-map.md`.
