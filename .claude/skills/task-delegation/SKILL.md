---
name: task-delegation
description: Use when the operator explicitly asks for delegation, subagents, parallel agents, or when an AI Developer has independent T-task slices that can safely run in parallel. Do NOT use for simple edits, immediate blocking work, deploy commands, production side effects, or Product Owner code-writing.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: high
invocation: automatic
expected_outputs:
  - delegation brief in chat or handoff
  - subtask ownership table
  - integration / verification notes in gate or deploy report
related_workflows:
  - greenlight-implement.md
  - architect-escalation.md
  - verification-gate.md
hook_dependencies:
  - none
---

# Task Delegation

> **Style:** Mode-B-lite. Role-aware subtask delegation without weakening Fusebase Flow ownership, verification, or role boundaries.

## Purpose

Coordinate bounded work across multiple agents when the host environment supports subagents. Delegation is a speed tool, not an authority transfer: the self-attested main role remains accountable for scope, integration, verification, and final reporting.

## When to invoke

- Operator explicitly asks for delegation, subagents, parallel agents, or parallel work.
- AI Developer has independent implementation/test slices with disjoint write scopes.
- Product Owner needs read-only investigation, option comparison, or artifact review that can run in parallel.
- Architect escalation needs independent read-only probes over distinct subsystems.

## Do not invoke when

- The task is simple enough to finish directly.
- The next critical-path step depends on the subtask result; do that locally.
- The work requires operator interaction or a decision while the subagent is running.
- The work touches deploy commands, production side effects, approval artifacts, secrets, or live-user credentials.
- Product Owner would be delegating production code edits.
- Write scopes overlap or cannot be clearly owned.
- The host has no subagent/delegation tool; use normal `docs/tmp/handoff/` Flow instead.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Self-attested role | current session | Stop; role defines allowed delegation |
| Source task / objective | `tasks.md`, `verification-gate.md`, handoff, or operator prompt | Stop; delegation needs bounded scope |
| Ownership boundary | file paths, modules, or read-only question | Keep work local until boundary is clear |
| Relevant artifacts | spec, decisions, tasks, gate, files, skills | Pass only what the subtask needs |
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Pass the relevant CLI provider skill names in the brief |
| Verification expectation | tests, checks, evidence, or requested answer shape | Add before delegating |
| Integration owner | main session | Main session always owns final integration |

## Procedure

### 1. Decide whether delegation is allowed

| Role | Allowed delegation | Forbidden delegation |
|---|---|---|
| Product Owner | Read-only repo investigation; compare options; review gate/deploy reports; draft doc-only alternatives | Production code edits; deploy execution; decision locking without operator |
| Architect escalation | Read-only subsystem probes; risk comparison; migration/constraint investigation | Production code edits; locked decisions |
| AI Developer | Bounded implementation/test slices under a T-task; focused bug investigation; non-overlapping test repair; test-only UI automation with clear evidence requirements | Deploy command; production side effects; overlapping writes; locked-decision changes |
| Deploy phase | Read-only failure triage while main session owns deploy state | Running deploy, rollback, secret handling, live smoke with credentials |

If the requested delegation is forbidden, refuse under `role-discipline` and offer a compliant alternative.

### 2. Keep the critical path local

Before spawning any subtask, name the immediate local action. Delegate only sidecar work that can progress while the main session continues non-overlapping work. Do not delegate the task that blocks your next action.

### 3. Write a delegation brief

Every delegated task gets a brief with:

| Field | Required content |
|---|---|
| Objective | one bounded outcome |
| Role boundary | read-only / code-edit / test-only |
| Ownership | exact files, modules, or question |
| Inputs | relevant artifacts and skill paths already loaded |
| Forbidden actions | no revert of others' edits; no deploy; no secrets; no broad cleanup |
| Domain skills | relevant CLI provider skill names from `docs/fusebase-cli-edition.md`, if the task touches Fusebase Apps runtime/domain behavior |
| Output format | changed files list, findings table, commands run, residual risk |
| Verification | expected tests/checks/evidence |

For code-edit subtasks, tell the worker: "You are not alone in the codebase. Do not revert or overwrite other concurrent edits; adapt to them."

**Turn-completion rule (every delegated session — binding):** a delegated session's deliverable must be COMPLETE within its turn. A delegated session cannot self-resume: when its turn ends, its context dies and nothing comes back. If the work requires waiting (ticks, agent runs, external processes, human gates), either poll with bounded sleeps INSIDE the turn until the result exists, or restructure the task as record-then-read (`flow-skills/smoke-testing` § Verification cost discipline). NEVER end the turn with "running in background — I'll resume when it completes" — you won't, and the orchestrator may trust the false completion. The delegating prompt MUST state this rule in one sentence (push, not pull).

**Mandatory (code-writing / implementation slices):** the delegating prompt MUST inline the comment-policy **Delegation push block** from `flow-skills/comment-policy/SKILL.md` (push, not pull — sub-agents do not reliably auto-load skills, so don't just tell the worker to "load comment-policy"). Read-only / triage delegation is exempt (no code is written).

For frontend/design subtasks, add:

| Field | Required content |
|---|---|
| Product identity | who the UI is for and what problem it solves |
| Selected direction | decision/spec reference; no new direction after lock |
| Surface map | routes, screens, workflows, components, or prompts in scope |
| Data contract | entities, fields, states, API/helper names and signatures if known |
| Stack conventions | project-local frontend rules or skill/doc paths, if applicable |
| Stable selectors | selector strategy for interactive and meaningful dynamic elements |
| Trust-critical flows | save/send/auth/purchase/primary actions that must be real |
| Creative freedom boundary | what the worker may decide, and what is fixed by spec/decision |
| Forbidden inventions | no new routes, entities, modules, workflows, or fake primary flows beyond scope |

For test-only UI automation subtasks, add:

| Field | Required content |
|---|---|
| User flow | one journey only: route, start state, primary action, expected result |
| Viewport | desktop/mobile dimensions or "project default" |
| Locators | stable selectors or accessible locators to use; no brittle style/layout selectors |
| Test data | unique values to create, existing records allowed, cleanup expectations |
| Auth/session | synthetic account, test account, live-user workflow, or no-auth |
| Diagnostics | browser-visible evidence plus backend/log/API surface to inspect |
| Side effects | external services touched; sandbox/test-mode requirement or forbidden |
| Output | screenshots/log excerpts/evidence paths and PASS/FAIL rationale |

### 4. Parallelize only independent slices

Use parallel delegation only when all are true:

- Each subtask has a distinct write set or is read-only.
- Results can be integrated in any order.
- Failure of one subtask will not corrupt another subtask's work.
- The main session can do useful non-overlapping work while subtasks run.

### 5. Integrate, verify, and report

The main session must:

1. Read each returned result.
2. Inspect changed files or evidence before trusting the result.
3. Resolve conflicts without reverting unrelated user or subagent changes.
4. Run the relevant verification gate commands.
5. Record delegated work in the gate/deploy report when it affected implementation or evidence.

Subagent output is evidence, not proof. Fusebase Flow success still requires the normal gate, smoke, security, and deploy checks.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Delegation brief | chat or task-local handoff section | Mode A / Mode-B-lite |
| Ownership table | chat, `tasks.md`, or handoff | Mode B when persisted |
| Integration notes | gate report / deploy report | Mode B |
| Follow-up ticket | `docs/backlog/<slug>/README.md` | Mode B |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Overlapping write scopes | same file/module assigned twice | Stop; merge subtasks or serialize them |
| Subtask blocks next action | main session waits immediately | Do it locally next time; delegation was misapplied |
| Product Owner delegated code edits | PO output includes production code patch | Reject result; route through AI Developer handoff |
| Worker changed out-of-scope files | changed files exceed ownership | Review manually; revert only the worker-owned out-of-scope changes if needed, never user changes |
| Worker skipped verification | no commands/evidence reported | Main session runs checks before claiming success |
| Test-only subtask uses vague browser plan | no route, locator, test data, auth plan, or expected result | Reject result; rerun with a complete test brief |
| Test subtask relies on shared state | asserts exact counts or empty state without creating/isolating data | Revise test data setup before accepting evidence |
| Frontend worker invents product scope | new route/entity/workflow not in brief | Reject or park as backlog; do not merge silently |
| Primary UI flow is fake | click/save/auth path has placeholder behavior | Mark incomplete; implement real behavior or revise scope |
| Deploy side effect delegated | subtask attempts deploy/rollback/approval artifact | Stop; deploy phase main session owns side effects |

## Escalation path

- If the work cannot be made independent, run it serially in the main session.
- If Product Owner needs implementation work, draft or amend the AI Developer handoff.
- If a delegated result contradicts locked decisions, stop and return to Product Owner.
- If repeated delegation failures occur, add a problem-catalog entry and tighten task boundaries.

## Anti-patterns

- Do not delegate because the task feels large; delegate because slices are independent.
- Do not delegate read-only searches that a quick `rg` can answer locally.
- Do not delegate vague work like "fix the feature" without file ownership.
- Do not delegate vague testing like "check the UI"; define the exact route, user flow, locators, data, auth plan, diagnostics, and evidence.
- Do not run multiple agents against the same files at the same time.
- Do not treat subagent output as final without main-session verification.
- Do not delegate frontend work with only a file path; include the product identity, surface map, data contract, selector strategy, stack conventions if applicable, and trust-critical flows.
- Do not delegate deploy commands, rollback, approval artifacts, or secret handling.
- Do not use popup / clickable menu tools to coordinate delegation decisions; ask in chat text per FR-19.

## Clean-room note

Original Fusebase Flow content. Derived from operator-provided capability requirements and generalized into repo-local workflow discipline; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
