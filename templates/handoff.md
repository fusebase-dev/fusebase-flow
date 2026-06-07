# Handoff — <slug>

> **Style:** Mode B. Active session restart state for the NEXT AI coding agent (not a human PM report). Written to `docs/tmp/handoff.md` (FR-23 Tier 2). Supersede in place — do NOT append resumption notes above old content (FR-18). Use `Unknown` instead of guessing, `None` for empty sections, tables where possible, and pointers to canonical artifacts instead of reprinting them. Not an audit log (git history is). For formal role relays use `docs/tmp/handoff/<date>-<slug>-{implement,deploy,architect}.md` instead.

**Updated:** <YYYY-MM-DD HH:MMZ>  ·  **Branch:** <branch>  ·  **HEAD:** <short-sha>

## Session Role
<Product Owner | AI Developer | Architect | Deploy phase> + authority level.

## Goal
<1-2 lines: what this session is trying to achieve. Non-goals on one line.>

## Current State
<Done / partial / not-started — tabular. Point to canonical spec/decisions/tasks; do not reprint.>

| Item | State | Pointer |
|---|---|---|
| <unit> | done/partial/not-started | `spec.md` AC<n> / `path:line` |

## Active Files in Flight
| Path | Change in progress | Committed? |
|---|---|---|
| `<path>` | <what> | yes/no |

## Changed This Session
<Commits / diffs landed this session — SHAs + one-line each. `None` if nothing committed.>

## Key Decisions Made
<Locked decisions only, by ID + pointer. `decisions.md#<id>`. Unsettled → Known Issues.>

## Constraints and Guardrails
<Worker-undisturbed paths, protected files, mixed-fleet/migration constraints, approvals required. Pointer to policy.>

## Failed Attempts
<What was tried and why it failed — so the next agent doesn't repeat it. `None` if none.>

## Known Issues / Open Questions
<Unresolved problems, undecided questions, blockers. Mark who/what each blocks.>

## Next Step
<EXACTLY ONE concrete, executable action: named file/function/command + expected result. Not "continue implementation".>

## Validation Plan
<Commands to prove the next step worked (lint/typecheck/test/smoke). Detected from manifests, not invented.>

## Relevant Commands
<Build/run/test/deploy commands actually used in this repo. `Unknown` if not yet detected.>

## Environment / Branch / Repo State
<Branch, HEAD, dirty/clean, mid-rebase/detached flags, runtime/toolchain versions if relevant.>

## Dependencies / External References
<Tickets, specs, external services, MCP/dashboards, decisions in other files — by pointer.>

## Risks
<What could go wrong on the next step; rollback note if mid-flight.>

## Completion Criteria
<How the next agent knows the goal is done (maps to spec ACs / gate by pointer).>
