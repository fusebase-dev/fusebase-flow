# Flow performance and recovery hardening — specification

**Status:** DRAFT
**Scope lock:** locked 2026-09-05 — operator authorized all recommended slices and end-to-end execution
**Created:** 2026-09-05
**Change tier:** Full
**Documentation tier:** 4
**Linked decisions:** A1..A7
**Source evidence:** `state/audit/adversarial-review-2026-09-05.md`
**Deploy hash:** N/A until completion

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

1. **AC1 — bounded overlay replacement:** refresh replaces exactly one valid Flow-owned marker block, preserves prefix, suffix, unrelated custom blocks, CRLF/Unicode, and FLOW:PRESERVE bytes, refuses ambiguous markers without writing, and is byte/mtime stable on the second run.
2. **AC2 — settings ownership:** recovery does not add/remove MCP servers, change permissions/custom settings, or source hook configuration from incidental staging trees; alternate configuration is accepted only through an explicit verified source with the complete Flow handler set.
3. **AC3 — intent-aware restoration:** a valid enabled same-project hook-intent record restores previously enabled Flow hooks, including from a missing settings file where Flow can safely reconstruct its own settings; absent, revoked, malformed, foreign, or incomplete intent never enables integrations. Recovery follows the per-surface authorization and failure contract in A2; reports machine-readable complete, partial, or failed status after verification, with safe retry and retained recovery material.
4. **AC4 — one owned hook:** every expected Flow event has exactly one recognized Flow handler after recovery; Stop detection searches all blocks, preserves CLI/consumer block order and timeouts, and converges on a byte-identical second run.
5. **AC5 — no-op recovery and mirroring:** an unchanged canonical/mirror tree performs zero destination copies and leaves target/manifest mtimes unchanged; a one-file drift repairs only that file while preserving canonical inventory and manifest format. Whole recovery also leaves agent mirrors, settings, backups, receipts, intent records, and Git-hook targets unchanged on a second run; only explicitly separate diagnostic evidence may be newly written.
6. **AC6 — single transcript read:** an ordinary native Stop event reads its transcript once while retaining final-assistant-only claim matching, whole-transcript signal detection, corrupt-transcript fail-closed behavior, and existing fixture verdicts.
7. **AC7 — smaller consumer context:** one authoritative always-on safety/ownership core and short role deltas replace duplicated startup prose across AGENTS/FLOW_RULES/mandatory skills/provider adapters. Measured host-delivered startup context decreases on measured supported hosts without changing deterministic safety behavior. Each host records identical scenario/model/settings and baseline/new input measurement; character-only estimates are labeled UNVERIFIED host coverage, never an AC7 pass for that host.
8. **AC8 — lightweight ordinary default:** ordinary diagnosis may run read-only before lane selection; objective auth/data/schema/permissions/public-contract/release-risk triggers escalate to Full. Ordinary low-risk changes need one product decision and no forced cross-session role relay; all carriers agree. The path router supplies mechanical matches only; the semantic assessor and workflow evidence owner follow A4, including sensitive changes in otherwise ordinary source paths.
9. **AC9 — validation responsibility:** CLI-owned lint/typecheck Stop hooks remain untouched. The actual Flow pre-commit invocation boundary reuses only authentic successful exact-state validator evidence under A6; Flow instructions follow the same contract; consumer recovery runs focused ownership/wiring/hash checks. Missing or mismatched evidence reruns, and secret/protected-path/release checks always remain live.
10. **AC10 — honest measurement:** ceremony reports separate historical artifacts from the requested Git window and correlate claims only when task/commit linkage exists. Benchmarks record wall time, actual tokens when available, tool calls, operator decisions, validator runs/duration, and no-op writes without hard performance gates.
11. **AC11 — CLI-safe recovery proof:** disposable recovery tests compare CLI-owned bytes and semantics before/after repair, restore every previously enabled Flow surface, reject unowned overwrite, and repeat to a no-op. The installed CLI channel is exercised only in an isolated project with a bounded command; inability to run it is reported as an explicit residual risk, never a false pass.
12. **AC12 — recovery-source convergence:** canonical Flow skills are the normal mirror source; the health-check recovery snapshot is fallback-only when canonical content is absent and may never supersede present canonical content. Provider mirrors and manifests finish at zero drift.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths | none configured; CLI-owned surfaces treated as stricter zero-change boundaries |
| Mixed-fleet considerations | required: Claude, Codex, Git fallback, Cursor/Copilot/Gemini instruction paths |
| Migration approach | no migration |
| Auth model | N/A; no app/auth functionality |
| UI / audience posture | N/A; internal developer tooling with no visual or interactive product surface |
| Quality bar | targeted mutation/regression fixtures, full registered suite, mirror/preflight checks |

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

## Related

- `docs/specs/flow-performance-and-recovery-hardening/clarify-conversation.md`
- `docs/specs/flow-performance-and-recovery-hardening/roadmap.md`
- `docs/specs/flow-performance-and-recovery-hardening/decisions.md`
- `docs/specs/flow-performance-and-recovery-hardening/tasks.md`
- `docs/specs/flow-performance-and-recovery-hardening/verification-gate.md`
