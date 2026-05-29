# Clarify conversation - cli-first-flow-second-recovery

**Status:** resolved
**Linked spec:** `docs/specs/cli-first-flow-second-recovery/spec.md`

## Locked answers

| ID | Question | Locked answer | Date |
|---|---|---|---|
| Q-A | Should Flow ever restore CLI instructions from Flow's bundled provider copy? | No. Current FuseBase CLI remains source of truth for CLI-owned instructions/assets. | 2026-05-29 |
| Q-B | What is the recovery order when both CLI and Flow surfaces are damaged? | Run current FuseBase CLI refresh/update first, then Flow recovery. | 2026-05-29 |
| Q-C | What does Flow recovery restore? | Flow-owned overlay pieces only: Flow skills, Flow agents, Flow lifecycle hooks, Flow overlay blocks, Flow health skill/command, and Flow framework files. | 2026-05-29 |
| Q-D | How deep should Flow health check go when checking CLI-owned assets? | Shape-only detection now: verify CLI-owned files exist and contain structural markers; do not compare hashes. Version-aware detection is a follow-up only if CLI exposes a stable manifest. | 2026-05-29 |
| Q-E | Should this ticket implement the existing-project installer script, or only the health-check/recovery model? | Health/recovery first: ownership map, layer verdicts, recovery guardrails, dry-run conflict reporting, and simulation tests. Leave a write-capable installer for the existing backlog ticket. | 2026-05-29 |
| Q-F | What exact CLI command should health check recommend when CLI-owned assets appear damaged? | Prefer exact agent-refresh flags only when verified in implementation; otherwise recommend "run the current FuseBase CLI refresh/update for this project", then Flow recovery. | 2026-05-29 |

## Active questions

None.
