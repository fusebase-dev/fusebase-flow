---
description: Run the read-only health check. Reports CLI_LAYER_DRIFT, FLOW_LAYER_DRIFT, SHARED_MERGE_DRIFT, PARTIAL_UPGRADE, PUBLISHER_PACKAGING_DRIFT, EXCEPTION_IN_EFFECT, BROKEN, or HEALTHY, and offers Flow recovery only for Flow-owned/shared drift after explicit operator confirmation. (FuseBase Flow)
---

# /fusebase-health

Trigger the `fusebase-flow-health-check` skill.

Procedure:

1. Run:

   ```bash
   bash hooks/local/fusebase-flow-health-check.sh
   ```

2. If more ownership detail is useful, run:

   ```bash
   bash hooks/local/check-cli-flow-conflicts.sh
   ```

3. Apply verdict rules:

   - `HEALTHY`: report no action required.
   - `CLI_LAYER_DRIFT`: tell the operator to run the current FuseBase CLI refresh/update first, then Flow recovery.
   - `FLOW_LAYER_DRIFT` or `SHARED_MERGE_DRIFT`: offer `bash hooks/local/post-fusebase-update.sh`; run only after an affirmative reply.
   - `PARTIAL_UPGRADE`: stale derived attestation strings only; re-run `bash hooks/local/upgrade.sh`.
   - `PUBLISHER_PACKAGING_DRIFT`: publisher repo only — bump the plugin/marketplace manifests with `VERSION`; this is packaging drift, not an interrupted upgrade, so do not offer recovery.
   - `EXCEPTION_IN_EFFECT`: surface active artifact(s); do not offer recovery.
   - `BROKEN`: surface broken item(s); do not offer recovery.

Recovery boundary:

- Flow recovery restores Flow skill/agent mirrors, AGENTS/CLAUDE overlays, `.claude/settings.json` Flow lifecycle merge, the health skill mirrors, and this slash command.
- Flow recovery does not patch `.claude/hooks/**`, restore CLI provider skill text, or overwrite MCP/Codex/project runtime config.
