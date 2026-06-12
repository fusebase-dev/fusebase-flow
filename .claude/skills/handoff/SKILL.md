---
name: handoff
description: Use when a coding session is getting long, before stopping complex implementation/migration/debugging work, when the operator says "prepare a handoff" / "hand this off" / "continue in a new chat" / "/handoff", or when a long autonomous run needs continuity (Mode run-ledger, announced in chat) — archives the superseded restart state to docs/tmp/handoff/archive/ (paper trail), then writes the active state to docs/tmp/handoff.md so a fresh AI session resumes from the exact current point without the previous chat. Do NOT use for routine commits, human-facing status reports, formal implement/deploy role relays (those are docs/tmp/handoff/<date>-<slug>-{implement,deploy}.md), or when no meaningful code/test/schema/config/decision change happened this session.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.14
risk_level: low
invocation: manual
expected_outputs:
  - docs/tmp/handoff.md (active session state, 16 sections, Mode B, timestamped, "Mode: restart | run-ledger" header)
  - docs/tmp/handoff/archive/<YYYY-MM-DD-HHMM>-handoff.md (the superseded predecessor — restart supersede / mode transition only; run-ledger updates supersede in place)
  - a short Mode A summary in chat (goal, current state, next step)
related_workflows:
  - eight-phase-flow.md
  - session-initiation.md
hook_dependencies:
  - none
---

# Handoff

> **Style:** Mode-B-lite. Produces the active-continuity artifact `docs/tmp/handoff.md` (FR-23 Tier 2) for the NEXT AI coding agent — not a human PM report. Operator-triggered (`invocation: manual`) for **restart** mode; **`Mode: run-ledger`** is the sole sanctioned autonomous write (long-run continuity, announced in chat).

## Purpose

Capture the exact current state of a coding session into `docs/tmp/handoff.md` so a brand-new AI session continues without the previous chat. Long sessions degrade and compaction is lossy; a structured handoff preserves goal, repo state, decisions, in-flight files, failed attempts, constraints, and the single next action. This is the **active** restart state; formal role-relay prompts (implement/deploy/architect) are separate dated files under `docs/tmp/handoff/` produced by `implementation-planning` / `release-deploy-reporting`.

**Two modes** (header `Mode:` line; absent in a legacy file → treat as restart): **restart** — operator-triggered snapshot for the next session; **run-ledger** — a long autonomous run's continuity note, written without operator trigger and announced in chat (one line), so context death mid-run loses nothing. A fresh session reading `Mode: run-ledger` resumes from records (read the ledger + cited artifacts first, resume from the last durable fact — `task-delegation` successor contract); a run-ledger is a continuity note, not a role-relay draft (it does not breach "AI Developer acknowledges; doesn't draft").

## When to invoke

- Operator says "prepare a handoff" / "hand this off" / "continue in a new chat" / runs `/handoff` (→ `Mode: restart`).
- Session is getting long / context degrading, or about to stop a complex implementation, migration, or debugging session.
- Meaningful code/test/schema/config/decision changes were made and must survive into the next session.
- A long autonomous run needs continuity across possible context death (→ `Mode: run-ledger`, no operator trigger needed; announce the write in chat — one line).

## Do not invoke when

- No meaningful change happened this session (nothing to continue from) — say so; do not write a hollow file.
- Operator wants a human-facing status update / standup / PR description — this file is for an AI agent.
- The artifact needed is a formal role relay (`docs/tmp/handoff/<date>-<slug>-{implement,deploy}.md`) — that's `implementation-planning` / `release-deploy-reporting`.
- Operator wants release/deploy reporting — use `release-deploy-reporting`.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Repo state | `git status --short`, `git branch --show-current`, `git rev-parse --short HEAD`, `git diff --stat` | Stop; confirm the working dir is the intended repo |
| Output structure | `templates/handoff.md` (the 16 canonical sections) | Use that template's section order; do not improvise |
| Session facts | the current conversation (goal, role, decisions, failures, next step) | Write `Unknown`; never guess |
| Build/test commands | `package.json`, `Makefile`, `pyproject.toml`, repo docs | Detect before inventing; else `Unknown` |

## Procedure

1. Classify per FR-23 (`documentation-budget`): a handoff is **Tier 2** — warranted only when the next session needs exact continuation state. If nothing meaningful changed, stop.
2. Inspect repo state: branch, short HEAD, `git status --short`, `git diff --stat`; review small diffs.
3. Detect real build/test/lint commands from manifests. Do not invent.
4. Reconstruct session facts: role + authority, goal + non-goals, done/partial/not-started, locked decisions, constraints, what failed and why, open questions, the single next concrete action.
5. **Mode + archive (paper trail).** Stamp `Mode: restart` (operator-triggered) or `Mode: run-ledger` (autonomous continuity — announce the write in chat, one line). Archive the predecessor to `docs/tmp/handoff/archive/<YYYY-MM-DD-HHMM>-handoff.md` (timestamp from its `Updated:` header when parseable, else file mtime/now) ONLY on restart supersede or **mode transition** (restart↔run-ledger, `/handoff` over a live ledger, or a different ticket's file). **Run-ledger updates supersede IN PLACE** (FR-18; git history is the audit trail) — never one archive file per ledger update. Archive files are **dated history — agents never load them**; the operator may prune the archive anytime (nothing references it).
6. Create `docs/tmp/` if absent. Write `docs/tmp/handoff.md` fresh from `templates/handoff.md` — same section order, every section filled with content / `Unknown` / `None`, and current `Updated: <YYYY-MM-DD HH:MMZ>` + `Mode:` lines in the header. Do NOT append resumption notes above old content (FR-18); the superseded restart predecessor lives in the archive.
7. Quality bar: factual only; pointers to canonical spec/decisions/tasks instead of reprinting them (FR-23); exactly one concrete executable Next Step; preserve repo terminology; product/user decisions separate from implementation detail; before reusing any copied procedural block, check whether a capability shipped since it was written supersedes the procedure.
8. Report a short Mode A summary in chat (Goal, Current state, Active files, Next step, Validation). Do not paste the full file unless asked.

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| Active session handoff | `docs/tmp/handoff.md` | Mode B (16 sections from `templates/handoff.md`, `Updated:` + `Mode:` header) |
| Archived predecessor | `docs/tmp/handoff/archive/<YYYY-MM-DD-HHMM>-handoff.md` | dated history — never loaded (restart supersede / mode transition only) |
| Handoff summary | chat | Mode A |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Nothing meaningful to hand off | `git status` clean, no in-flight decisions | Tell operator no handoff is warranted; do not write a hollow file |
| Facts unknown | A section can't be filled from session/repo | Write `Unknown`; never invent results/decisions |
| Vague next step | Next Step reads "continue" / "fix issues" | Rewrite as one named file/function/command + expected result |
| Stale existing handoff | `docs/tmp/handoff.md` describes a different/old task | Archive it, then write current state fresh (FR-18); do not merge contradictory histories |
| Reprinting canonical docs | Handoff restates the full spec/decisions/tasks | Replace with pointers (FR-23) + current state |

## Escalation path

- Repo state ambiguous (detached HEAD, mid-rebase, dirty submodules) → record under `Environment / Branch / Repo State` and ask the operator to confirm before the next session continues.
- Session made deploy/production-affecting changes → also route through `release-deploy-reporting`; the active handoff is not a deploy record.
- Decisions still unsettled → list under `Known Issues / Open Questions`, not `Key Decisions Made`.

## Anti-patterns

- Do not write a human-PM / marketing-style document — the reader is an AI agent.
- Do not guess; write `Unknown`.
- Do not hide failed attempts or dead-end debugging paths.
- Do not emit a vague Next Step.
- Do not include chain-of-thought or unrelated chat history.
- Do not use `docs/tmp/handoff.md` for a formal implement/deploy relay (those are dated files under `docs/tmp/handoff/`).
- Do not auto-invoke restart mode (`invocation: manual`) — the operator triggers it. `Mode: run-ledger` is the sole sanctioned autonomous write and MUST be announced in chat when written.
- Do not archive on every run-ledger update (in-place supersede; archive fires on restart supersede / mode transition only).

## Clean-room note

Original Fusebase Flow content. The session-continuity-doc concept is common to long-running agent workflows; no third-party code, prompts, or skill files are copied. See `docs/source-map.md`.
