# Verification gate - cli-first-flow-second-recovery

**Linked spec:** `docs/specs/cli-first-flow-second-recovery/spec.md`
**Linked tasks:** `docs/specs/cli-first-flow-second-recovery/tasks.md`
**Gate task:** T8
**Pass threshold for smoke:** N/A - local framework tooling, no deployed surface

## Acceptance-criterion -> task mapping

| AC | Implemented in | Test coverage |
|---|---|---|
| AC1 | T2 | manifest parse by conflict reporter and simulation test |
| AC2 | T3 | `bash hooks/local/check-cli-flow-conflicts.sh` |
| AC3 | T4, T6 | recovery script inspection plus simulation sentinel assertions |
| AC4 | T5 | health-check CLI drift scenario / recommendation text |
| AC5 | T4, T6 | simulation verifies Flow-only restoration |
| AC6 | T4, T6 | settings and Codex preservation assertions |
| AC7 | T5 | health-check output shows layer verdict taxonomy |
| AC8 | T6 | `bash hooks/tests/test-cli-flow-recovery.sh` |
| AC9 | T7 | docs review in gate |
| AC10 | T8 | preflight, hook tests, simulation, health, conflict reporter |

## Required gate-report fields

| Field | Format |
|---|---|
| Implementation summary | 1-3 sentences |
| Per-task SHAs | `T<n>: <sha> <subject>` for every implementation task |
| Test counts | before/after/delta for hook fixture tests and new simulation |
| Preflight status | `clean` / error count |
| Hook test status | `14/14 PASS` or failure details |
| Simulation status | PASS/FAIL plus key assertions |
| Health status | verdict plus exit code |
| Conflict reporter status | verdict plus exit code |
| Worker-undisturbed git diff | `N/A - no downstream worker paths` unless touched paths require exception |
| Manifest version | ownership manifest schema version |
| Architect/PO deviations | listed with reasoning, or `none` |
| Self-attestation | "Operating as AI Developer..." phrase |

## Lint / typecheck / test commands

| Layer | Command |
|---|---|
| Preflight | `& 'C:\Program Files\Git\bin\bash.exe' hooks/local/preflight.sh` |
| Hook fixture tests | `& 'C:\Program Files\Git\bin\bash.exe' hooks/tests/run-tests.sh` |
| Simulation | `& 'C:\Program Files\Git\bin\bash.exe' hooks/tests/test-cli-flow-recovery.sh` |
| Health check | `& 'C:\Program Files\Git\bin\bash.exe' hooks/local/fusebase-flow-health-check.sh` |
| Conflict report | `& 'C:\Program Files\Git\bin\bash.exe' hooks/local/check-cli-flow-conflicts.sh` |
| Git review | `git status --short`, `git diff --stat` |

## Worker-undisturbed paths

No downstream worker paths apply. This ticket edits Flow framework docs and local recovery tooling only.

## Smoke prompts

N/A - no deployed operator UI. The local simulation test is the smoke-equivalent evidence.

## Probes

| ID | Probe | Pass criterion | Evidence |
|---|---|---|---|
| G-A | Ownership manifest parse | conflict reporter reads schema version 1 | command transcript |
| G-B | Flow-only recovery simulation | CLI-owned sentinels unchanged, Flow-owned mirrors restored | simulation output |
| G-C | Health verdict taxonomy | health check emits one of documented verdicts | command transcript |
| G-D | Existing gates | preflight clean and hook tests 14/14 PASS | command transcript |

## Manifest version bump

Old: N/A
New: `agent-surface-ownership.json` schema version 1
Reason: first maintained ownership map for CLI/Flow shared surfaces

## Rollback procedure

If any gate step fails:

1. Stop before deploy/release.
2. Revert the failing task commit with `git revert <sha>`.
3. File a follow-up backlog item if the failure reveals a larger CLI/Flow boundary issue.
4. Keep `spec.md` DRAFT until the follow-up resolves.

## Cross-artifact consistency check

```
Constitution invariants verified:
[ ] Worker-undisturbed list - no downstream worker paths touched
[ ] Mixed-fleet considerations - Claude, Codex, MCP, and generic local paths addressed
[ ] Migration approach - no data migration
[ ] Auth model - no runtime auth or secret changes
[ ] Quality bar - preflight, hook tests, simulation pass

Cross-artifact:
[ ] Every AC<n> exercised in at least one task
[ ] Every locked decision A<n> cited in at least one task
[ ] All clarify questions resolved
[ ] All T-numbered implementation tasks have SHAs filled in
[ ] No TODO/FIXME/WIP markers in diff
[ ] Spec status still DRAFT
```
