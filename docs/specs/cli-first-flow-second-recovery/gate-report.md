# Gate report - cli-first-flow-second-recovery

**Gate task:** T8
**Date:** 2026-05-29
**Self-attestation:** Operating as AI Developer for implementation and gate execution.

## Implementation summary

Implemented CLI-first, Flow-second recovery semantics for the Fusebase CLI edition. Flow now has a parseable ownership manifest, a no-write conflict reporter, layer verdicts in health check, Flow-only recovery guardrails, simulation coverage, and tracked install docs for the model.

## Per-task SHAs

| Task | SHA | Subject |
|---|---|---|
| T2 | 01a3bed | lock CLI Flow recovery plan |
| T3 | d439f4a | add CLI Flow conflict reporter |
| T4 | 0ce1392 | keep Flow recovery off CLI hooks |
| T5 | a43fead | add health layer verdicts |
| T6 | 90e422c | simulate CLI refresh recovery |
| T7 | 21b05c9 | document CLI first recovery |
| T8 | gate-report commit | this report and task ledger update |

## Test results

| Check | Command | Result |
|---|---|---|
| Preflight | `bash hooks/local/preflight.sh` | PASS - 0 errors, 0 warnings |
| Hook fixtures | `bash hooks/tests/run-tests.sh` | PASS - 14/14 |
| Simulation | `bash hooks/tests/test-cli-flow-recovery.sh` | PASS - 5/5 assertion groups |
| Conflict report | `bash hooks/local/check-cli-flow-conflicts.sh` | PASS - `Verdict: HEALTHY`, CLI/shared/Flow drift all 0 |
| Health check | `bash hooks/local/fusebase-flow-health-check.sh` | PASS - `Verdict: HEALTHY`, 11 checks |

## Test counts

| Layer | Before | After | Delta |
|---|---:|---:|---:|
| Hook fixtures | 14 | 14 | 0 |
| CLI/Flow recovery simulation | 0 | 1 script / 5 assertion groups | +1 script |

## Acceptance coverage

| AC | Evidence |
|---|---|
| AC1 | `agent-surface-ownership.json` schema version 1 parsed by reporter. |
| AC2 | `check-cli-flow-conflicts.sh` returns no-write collision report and `HEALTHY` on current repo. |
| AC3 | Recovery script no longer patches `.claude/hooks/**`; simulation verifies CLI hook sentinel unchanged. |
| AC4 | Health recommendations route CLI-owned drift to current CLI refresh/update first. |
| AC5 | Recovery restores only Flow mirrors, overlay blocks, settings merge, health skill, and slash command. |
| AC6 | Simulation verifies settings merge preserves CLI Stop hooks and `.codex/config.toml` checksum. |
| AC7 | Health check supports `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT`, `HEALTHY`, `BROKEN`, and `EXCEPTION_IN_EFFECT`. |
| AC8 | `test-cli-flow-recovery.sh` simulates CLI refresh then Flow recovery. |
| AC9 | `docs/install-fusebase-cli-project.md` updated; health skill and slash command docs updated. Ignored `docs/fusebase-health/**` files are not counted as shipped evidence. |
| AC10 | Existing preflight and hook tests pass; new simulation passes. |

## Worker-undisturbed

N/A - no downstream worker paths apply. This ticket changed Flow framework docs and local recovery tooling only.

## Manifest version

`agent-surface-ownership.json`: N/A -> schema version 1.

## Architect/PO deviations

- `docs/fusebase-health/**` is ignored by `.gitignore`, so it is not counted as shipped documentation evidence for AC9.
- Unrelated commits appeared in history during execution: `befa7df docs: restructure README for new-user onboarding` and `89bbfb3 docs: add promotion pass - skill catalog, FAQ, positioning + community health files`. They are not part of the T2..T8 task chain.

## Git status note

Final `git status --short --untracked-files=all`: clean.
