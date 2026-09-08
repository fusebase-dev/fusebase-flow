# Flow performance and recovery hardening — specification

**Status:** DONE - historical implementation contract; v4.15.0/v4.15.1/v4.15.2 remain unpublished. v4.15.2's [tagged gate](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34176386683) passed Linux, failed Windows at 633/634 essential predicates and skipped publication; T71 prepares v4.15.3. Current outcome: `docs/changes/2026-09-07-release-completion.md`.
**Scope lock:** locked 2026-09-05 — operator authorized all recommended slices and end-to-end execution
**Created:** 2026-09-05
**Change tier:** Full
**Documentation tier:** 4
**Linked decisions:** A1..A7, B1..B6
**Source evidence:** `state/audit/adversarial-review-2026-09-05.md`
**Correction basis:** `adversarial-review.md` - CHANGES REQUIRED on source `2217a9c631300e510b18437548ed4bccb5f31036`
**Deploy hash:** N/A; no deployment
**Current acceptance:** final T22 APPROVED / ZERO BLOCKERS at559ca5a; implementation completed through T59 `e99d61b`; T60 reconciles release evidence. R1-R5 remain closed for the reviewed contract; `gate-report.md` owns current evidence and residual disposition.

## Scoped completion and residual disposition

AC11 is observed for the recorded actual CLI `2026.090414.3609` Windows/Git Bash consumer scenario: update, recovery rc0, byte preservation, conflict HEALTHY, second recovery no-op, and final `e99d61b` sync/health. Earlier update/recovery/no-op evidence remains dependency evidence; only final sync and health reran at `e99d61b`. Tagged Linux and Windows/MSYS release CI, unexecuted real-symlink cases, five-provider delivered-context telemetry, and Windows authority isolation/successful signing remain DEFERRED/UNVERIFIED. AC7 host measurement remains deferred. AC9 is satisfied by unconditional fail-closed unavailability; validator reuse, successful signing, and reduced lint/typecheck execution are not delivered outcomes. No deploy, migration or app UI scope.

## Problem

FuseBase Flow imposes avoidable startup, mirroring, transcript-processing, validation, and role-transition cost in consumer projects. Its post-`fusebase update` recovery also has five demonstrated defects: it can remove trailing instructions, change MCP enablement, trust stale staging configuration, leave previously enabled hooks stripped while reporting success, and duplicate a Flow Stop hook.

## Why now

The locked North Star makes low-friction ordinary work the primary product outcome. The operator requires Flow recovery to preserve FuseBase CLI behavior and restore previously enabled Flow after CLI updates overwrite shared provider files.

## In scope

- Correct R1–R5 recovery defects with exact Flow ownership and complete/partial recovery verdicts.
- Optimize P1–P7: startup context, lane routing, mirror writes, validation duplication, Stop transcript reads, health-skill recovery ownership, and ceremony measurement.
- Preserve CLI-owned provider skills, app agents, hooks, MCP/config choices, permissions, custom settings, command order, and timeouts.
- Validate against synthetic fixtures and a disposable current-CLI refresh when the installed CLI supports a non-interactive isolated test.
- Keep safety controls for destructive operations, secrets, protected paths, exact-state validation, rollback, and sensitive-change review.

## Out of scope

- FuseBase CLI runtime, SDK, MCP, dashboard, Gate, authentication, registration, session, role, group, or permission behavior changes.
- App UI, routes, dashboards, frontend components, and client-facing functionality.
- Production deployment or database migration; this repository is a framework/template package with no app deployment target.
- Removing safety controls solely because they did not fire in a short observation window.
- Claiming a measured end-to-end consumer speedup without ordinary-project benchmark evidence.

## Acceptance criteria

1. **AC1 — bounded overlay replacement:** refresh replaces exactly one valid Flow-owned marker block, preserves prefix, suffix, unrelated custom blocks, CRLF/Unicode, and FLOW:PRESERVE bytes, and is byte/mtime stable on the second run. Markerless input is accepted only when both legacy boundaries are proven; an unrelated suffix/custom heading or any ambiguity refuses with exit 2 and zero writes.
2. **AC2 — settings ownership:** recovery does not add/remove MCP servers, change permissions/custom settings, or source hook configuration from incidental staging trees; alternate configuration is accepted only through an explicit verified source with the complete Flow handler set.
3. **AC3 — intent-aware restoration:** a valid enabled same-project hook-intent record restores only its proven surfaces. Recovery prevalidates the complete target plan before mutation, retains an interruption/retry ledger and originals, and assigns exit 2/zero writes to invalid input, exit 1 to partial/uncertain recovery, and exit 0 only after authoritative parsed/hash verification. Missing provider bytes require a verified backup restore or explicit uncertainty; Git restoration requires per-surface intent plus verified installed-hook ownership.
4. **AC4 — one exactly owned hook:** every expected Flow event has exactly one exact recognized Flow handler in a dedicated Flow-owned block after recovery. Substring lookalikes and mixed custom blocks are not Flow-owned; custom block order, matchers, timeouts, commands, and scope remain unchanged. Stop detection searches all blocks and convergence is byte-identical.
5. **AC5 — ownership-safe no-op recovery and mirroring:** each skill, agent, command, health-skill, settings, and Git-hook target is classified before write. Unowned collisions and symlinks remain untouched and yield partial/exit 1; owned repair retains the original and replaces atomically. Three independent write-mode no-op recoveries perform zero target copies/writes and preserve target/manifest bytes and mtimes; `--check` is labeled read-only integrity only.
6. **AC6 — single transcript read:** an ordinary native Stop event reads its transcript once while retaining final-assistant-only claim matching, whole-transcript signal detection, corrupt-transcript fail-closed behavior, and existing fixture verdicts.
7. **AC7 — smaller consumer context:** one authoritative always-on safety/ownership core and short role deltas replace duplicated startup prose across AGENTS/FLOW_RULES/mandatory skills/provider adapters. Measured host-delivered startup context decreases on measured supported hosts without changing deterministic safety behavior. Each host records identical scenario/model/settings and baseline/new input measurement; character-only estimates are labeled UNVERIFIED host coverage, never an AC7 pass for that host.
8. **AC8 — lightweight ordinary default:** ordinary diagnosis may run read-only before lane selection; objective auth/data/schema/permissions/public-contract/release-risk triggers escalate to Full. The workflow fixture performs and records real diagnosis/actions/artifact writes; counts derive from observed files/actions, and mutation proves an extra relay, extra artifact, or skipped diagnosis fails. A simulation is labeled as such and cannot verify AC8.
9. **AC9 — validation responsibility:** CLI-owned lint/typecheck Stop hooks remain untouched. Reuse requires a complete validator-visible identity, including ignored declared inputs/dependencies, symlink targets, all validator-affecting environment, and every executable/toolchain layer. The trusted runner owns child execution and signing; direct mint/substituted runner fails. Completeness or external authority unavailable means reuse unavailable and validators rerun. Fixtures are portable without mandatory `cygpath` and execute on Linux where available.
10. **AC10 — honest measurement:** window conclusions require outcome- and task-specific linkage; a cosmetic current edit, generic SHA mention, or mixed historical/current report cannot promote an old outcome. Benchmarks label `--check` read-only integrity and use repeated write-mode evidence for writes/mtimes. Workflow counts come from executed actions; unavailable tokens/tool telemetry remain explicit.
11. **AC11 — CLI-safe recovery proof:** disposable recovery tests compare CLI-owned bytes and semantics before/after repair, restore every proven prior Flow surface, reject unowned overwrite, and repeat to a no-op. Actual install/update/recover comparison is required for verified current-CLI coverage; an update-only probe remains UNVERIFIED. Inability to run it is an explicit residual risk.
12. **AC12 — recovery-source convergence:** canonical Flow skills are the normal mirror source; the health-check recovery snapshot is fallback-only when canonical content is absent and may never supersede present canonical content. Provider mirrors and manifests finish at zero drift.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths | none configured; CLI-owned surfaces treated as stricter zero-change boundaries |
| Mixed-fleet considerations | required: Claude, Codex, Git fallback, Cursor/Copilot/Gemini instruction paths |
| Migration approach | no migration |
| Auth model | N/A; no app/auth functionality |
| UI / audience posture | N/A; internal developer tooling with no visual or interactive product surface |
| Quality bar | risk-scoped AC evidence and affected dependency tests; full release CI; mirror/preflight checks (B6) |

## Runtime and file changes

- Recovery: `hooks/local/post-fusebase-update.sh`, its overlay/config helpers, intent library, recovery fixtures.
- Hot paths: `hooks/local/mirror-skills.sh`, `hooks/handlers/stop.py`, related tests.
- Consumer flow: `FLOW_RULES.md`, AGENTS/CLAUDE overlay sources, mandatory skills/role deltas, lane/router/workflow carriers and provider mirrors.
- Validation and measurement: pre-commit/recovery guidance without editing CLI-owned Stop validators; wasted-effort evidence collector and fixtures.

## Risks

- Instruction compaction can remove a safety invariant; mitigate with semantic carrier inventory and behavior fixtures before/after.
- Automatic restoration can mistake copied/stale intent for authorization; require schema, enabled state, nonempty same-project identity, and parsed hook structure.
- Recovery can overwrite CLI/user state; compute exact Flow-owned changes and verify CLI-owned bytes.
- Performance caching can create stale proof; reuse only exact-state evidence and keep fail-closed live checks.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | Execute every recommendation in recovery-first order | 2026-09-05 |
| Q-B | Preserve CLI work and restore previously enabled Flow | 2026-09-05 |
| Q-C | UI/client-facing work is N/A | 2026-09-05 |
| Q-D | Migrations and deploy authorized if needed; neither applies to this framework-only ticket | 2026-09-05 |
| Q-E | All recommended decisions and end-to-end sub-agent execution authorized | 2026-09-05 |
| Q-F | Proactive delegated-work polling and bounded same-agent retry | 2026-09-05 |
| Q-G | Astra verdict CHANGES REQUIRED; execute B1-B8 and N1-N2 before a repeated independent review; prior gate PASS is superseded | 2026-09-06 |

## Related

- `docs/specs/flow-performance-and-recovery-hardening/clarify-conversation.md`
- `docs/specs/flow-performance-and-recovery-hardening/roadmap.md`
- `docs/specs/flow-performance-and-recovery-hardening/decisions.md`
- `docs/specs/flow-performance-and-recovery-hardening/tasks.md`
- `docs/specs/flow-performance-and-recovery-hardening/verification-gate.md`
- `docs/specs/flow-performance-and-recovery-hardening/adversarial-review.md`
