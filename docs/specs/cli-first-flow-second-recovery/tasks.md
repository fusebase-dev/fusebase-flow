# Tasks - cli-first-flow-second-recovery

**T-counter going in:** T1 (next task is T2)
**Task range:** T2..T8
**Gate task:** T8
**Deploy task:** N/A - framework/template change, no production deploy
**Linked spec:** `docs/specs/cli-first-flow-second-recovery/spec.md`
**Linked decisions:** `docs/specs/cli-first-flow-second-recovery/decisions.md`

## Task chain

| T# | Track | Scope | Cites decision | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T2 | planning/manifest | Lock spec decisions, save implement handoff, add ownership manifest. | A1, A2, A3 | - | pending | in_progress |
| T3 | tooling | Add read-only CLI/Flow conflict reporter using the ownership manifest. | A1, A2, A4 | T2 | pending | pending |
| T4 | recovery | Enforce Flow-only recovery and remove stale CLI-hook patch behavior. | A3, A5 | T2 | pending | pending |
| T5 | health | Add layer verdicts and CLI-first next-action guidance to health check and skill text. | A2, A3, A5 | T3, T4 | pending | pending |
| T6 | tests | Add simulation coverage for CLI refresh followed by Flow recovery. | A6 | T3, T4, T5 | pending | pending |
| T7 | docs | Update install and health docs for CLI-first, Flow-second model. | A1..A6 | T3..T6 | pending | pending |
| T8 | gate | Run validation gate and produce gate report. | A1..A6 | T2..T7 | pending | pending |

## Per-task detail

### T2. Planning lock and ownership manifest

**Track:** planning/manifest
**Scope:** Resolve clarify log, lock decisions, write tasks/gate/handoff, add path ownership manifest.
**Files:** `docs/specs/cli-first-flow-second-recovery/*`, `docs/handoff/2026-05-29-cli-first-flow-second-recovery-implement.md`, `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json`
**Cites:** decisions A1, A2, A3
**Depends on:** -
**Acceptance:** AC1
**Tests:** JSON parse check in T3/T6; full gate in T8
**Worker-undisturbed:** no downstream worker paths
**SHA:** pending

---

### T3. Read-only conflict reporter

**Track:** tooling
**Scope:** Add `hooks/local/check-cli-flow-conflicts.sh` that reads the manifest and reports collisions, owners, current status, and proposed actions without writing.
**Files:** `hooks/local/check-cli-flow-conflicts.sh`, optional docs references
**Cites:** decisions A1, A2, A4
**Depends on:** T2
**Acceptance:** AC2
**Tests:** run reporter in current repo and in simulation fixture
**Worker-undisturbed:** no downstream worker paths
**SHA:** pending

---

### T4. Flow-only recovery guardrails

**Track:** recovery
**Scope:** Update `post-fusebase-update.sh` so it restores Flow-owned mirrors and shared Flow additions only; remove stale CLI-hook patch behavior.
**Files:** `hooks/local/post-fusebase-update.sh`
**Cites:** decisions A3, A5
**Depends on:** T2
**Acceptance:** AC3, AC5, AC6
**Tests:** simulation fixture in T6; existing hook tests in T8
**Worker-undisturbed:** no downstream worker paths
**SHA:** pending

---

### T5. Layer verdict health check

**Track:** health
**Scope:** Extend health check to classify `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT`, `BROKEN`, and `HEALTHY`; update health-check skill mirrors.
**Files:** `hooks/local/fusebase-flow-health-check.sh`, `skills/fusebase-flow-health-check/SKILL.md`, `.claude/skills/fusebase-flow-health-check/SKILL.md`, `.agents/skills/fusebase-flow-health-check/SKILL.md`, `hooks/local/fusebase-flow-overlays/skills/fusebase-flow-health-check/SKILL.md`
**Cites:** decisions A2, A3, A5
**Depends on:** T3, T4
**Acceptance:** AC4, AC7
**Tests:** health check on current repo; fixture checks in T6
**Worker-undisturbed:** no downstream worker paths
**SHA:** pending

---

### T6. Archive-style simulation test

**Track:** tests
**Scope:** Add a local test that simulates current CLI refresh sentinels, runs Flow recovery, and asserts CLI-owned content stays untouched while Flow overlay is restored.
**Files:** `hooks/tests/test-cli-flow-recovery.sh`
**Cites:** decision A6
**Depends on:** T3, T4, T5
**Acceptance:** AC8, AC10
**Tests:** `bash hooks/tests/test-cli-flow-recovery.sh`
**Worker-undisturbed:** no downstream worker paths
**SHA:** pending

---

### T7. Documentation update

**Track:** docs
**Scope:** Update install and health docs with CLI-first/Flow-second recovery model, conflict reporter usage, and removed CLI-hook patch posture.
**Files:** `docs/install-fusebase-cli-project.md`, `docs/fusebase-health/README.md`, `docs/fusebase-health/OPERATOR-WORKFLOWS.md`, optional health docs
**Cites:** decisions A1..A6
**Depends on:** T3..T6
**Acceptance:** AC9
**Tests:** docs reviewed for consistency; full gate T8
**Worker-undisturbed:** no downstream worker paths
**SHA:** pending

---

### T8. Verification gate

No code change. AI Developer produces gate report per `verification-gate.md` contract:

- Per-task SHAs
- Test counts before/after
- Preflight status
- Hook test status
- Simulation test status
- Health check status
- Conflict reporter status
- Worker-undisturbed git diff
- Architect/PO deviations

After gate report, stop. No production deploy applies to this ticket.
