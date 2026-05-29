---
name: fusebase-flow-health-check
description: Use when the operator asks "is Fusebase Flow healthy", "check Fusebase Flow", "did fusebase update break anything", "Fusebase Flow status", "restore Fusebase Flow", or asks whether Fusebase CLI and Fusebase Flow agent files conflict. Runs the read-only health engine, reports layer verdicts (`HEALTHY`, `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT`, `EXCEPTION_IN_EFFECT`, `BROKEN`), and offers Flow recovery only when the drift is Flow-owned or shared-merge. For CLI-owned drift, instruct the operator to run the current FuseBase CLI refresh/update first, then Flow recovery.
source_inspiration: original (operator-maintained recovery infrastructure)
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: low - diagnosis phase is read-only; recovery phase executes hooks/local/post-fusebase-update.sh only after explicit operator affirmative reply in chat
invocation: automatic (description match) - also via /fusebase-health slash command
expected_outputs:
  - Health check report printed to chat
  - Layer verdict and next action
  - Recovery offer only for FLOW_LAYER_DRIFT or SHARED_MERGE_DRIFT
  - CLI-first guidance for CLI_LAYER_DRIFT
related_workflows:
  - hooks/local/fusebase-flow-health-check.sh
  - hooks/local/check-cli-flow-conflicts.sh
  - hooks/local/post-fusebase-update.sh
hook_dependencies:
  - none
---

# Fusebase Flow Health Check

## Purpose

Verify the local Fusebase Flow overlay and the shared FuseBase CLI / Flow agent surfaces without writing to the repository. The health engine now separates failures by ownership layer:

| Verdict | Meaning | Recovery posture |
|---|---|---|
| `HEALTHY` | CLI-owned, Flow-owned, and shared-merge surfaces look intact. | No action. |
| `CLI_LAYER_DRIFT` | CLI-owned assets are missing or structurally damaged. | Do not run Flow recovery first. Run the current FuseBase CLI refresh/update, then Flow recovery. |
| `SHARED_MERGE_DRIFT` | Shared files are missing Flow overlay/merge additions. | Offer Flow recovery. |
| `FLOW_LAYER_DRIFT` | Flow-owned mirrors or overlay files are missing/drifted. | Offer Flow recovery. |
| `EXCEPTION_IN_EFFECT` | Drift is covered by active approval/deferral artifacts. | Do not run recovery automatically. Surface the artifact. |
| `BROKEN` | Preflight, hook tests, manifest parsing, or other critical checks failed. | Do not offer recovery; inspect the broken item first. |

## Procedure

1. Confirm the engine exists:

   ```bash
   test -f hooks/local/fusebase-flow-health-check.sh
   ```

2. Run the read-only engine:

   ```bash
   bash hooks/local/fusebase-flow-health-check.sh
   ```

3. Optionally run the no-write ownership report for more detail:

   ```bash
   bash hooks/local/check-cli-flow-conflicts.sh
   ```

4. Interpret exit code:

   | Exit | Verdicts |
   |---:|---|
   | 0 | `HEALTHY` |
   | 1 | `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT` |
   | 2 | `BROKEN` |
   | 3 | `EXCEPTION_IN_EFFECT` |

5. If verdict is `FLOW_LAYER_DRIFT` or `SHARED_MERGE_DRIFT`, ask in chat before writing:

   > Run Flow recovery now? Reply `yes`, `run it`, `fix it`, or `proceed` and I will execute `bash hooks/local/post-fusebase-update.sh`, then re-run the health check.

6. If the operator already gave an affirmative in the same turn, that counts as confirmation for this recovery action. Execute:

   ```bash
   bash hooks/local/post-fusebase-update.sh
   bash hooks/local/fusebase-flow-health-check.sh
   ```

7. If verdict is `CLI_LAYER_DRIFT`, do not run Flow recovery as the first step. Say:

   > CLI-owned files need the current FuseBase CLI to restore them. Run the current FuseBase CLI refresh/update for this project first, then run `bash hooks/local/post-fusebase-update.sh`.

## Recovery Boundary

`post-fusebase-update.sh` restores only Flow-owned assets and shared Flow additions:

- Flow skills into `.claude/skills/` and `.agents/skills/`
- Flow agents into `.claude/agents/` and `.codex/agents/`
- Flow overlay blocks in `AGENTS.md` and `CLAUDE.md`
- Flow lifecycle hooks merged into `.claude/settings.json`
- `fusebase-flow-health-check` skill mirrors
- `.claude/commands/fusebase-health.md`

It does not patch or restore `.claude/hooks/**`, FuseBase CLI provider skills, MCP configs, `fusebase.json`, `skills-lock.json`, or active `.codex/config.toml` content. Those are CLI-owned or project-owned surfaces.

## Output Shape

Report:

- Verdict
- Layer that drifted
- Concrete next action
- Whether recovery was offered, declined, or executed
- Re-check result when recovery runs

Keep chat output brief and concrete. Do not paste the full engine transcript unless the operator asks.
