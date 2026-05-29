# Spec - cli-first-flow-second-recovery

**Status:** DRAFT
**Created:** 2026-05-29
**Linked decisions:** `docs/specs/cli-first-flow-second-recovery/decisions.md`
**Promoted from:** operator request in chat, 2026-05-29
**Deploy hash:** N/A - framework/template change

## Problem

Fusebase Flow installs on top of FuseBase CLI projects, but both layers share agent-facing files such as `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.claude/skills/`, `.claude/agents/`, and `.claude/hooks/`. Current Flow recovery correctly restores Flow after a CLI refresh, but the operator needs an explicit CLI-first, Flow-second model that prevents Flow from overwriting or restoring stale CLI instructions from Flow's bundled provider copy.

## Why now

The operator supplied a current FuseBase CLI archive and clarified that CLI instructions must remain version-owned by the current CLI, not by the Flow edition package. The health-check/recovery model must prove that invariant before Flow is safe to install into existing CLI/MCP repositories.

## In scope

- Define ownership classes for shared installation surfaces: CLI-owned, Flow-owned, and shared-merge.
- Update install/recovery guidance so current FuseBase CLI regenerates CLI-owned assets before Flow restores only Flow-owned overlay pieces.
- Extend health-check diagnostics to distinguish CLI layer drift, Flow layer drift, and shared merge drift.
- Add conflict detection for existing CLI/MCP repositories before any write.
- Add regression coverage using a CLI project-template fixture derived from the analyzed archive.
- Update docs so operators understand the recovery sequence and the non-overwrite invariant.

## Out of scope

- Replacing FuseBase CLI's update implementation.
- Copying CLI provider skill text from Flow into an existing CLI project.
- Freezing CLI skill versions in Flow's health-check logic.
- Running production deploys or modifying downstream customer projects during this ticket.
- Resolving all future CLI/Flow semantic conflicts; this ticket establishes ownership and recovery mechanics.

## Acceptance criteria

1. **AC1 - Ownership manifest**: The repo contains a maintained ownership map for collision-prone paths that classifies each path as `cli-owned`, `flow-owned`, or `shared-merge`.
2. **AC2 - Dry-run conflict report**: The install path for existing FuseBase CLI/MCP projects can produce a no-write report listing collisions, intended owner, and proposed action for each shared path.
3. **AC3 - No CLI overwrite by Flow**: Flow install/recovery never copies CLI provider instructions, CLI hooks, MCP configs, or current CLI `AGENTS.md`/`CLAUDE.md` text from Flow's bundled provider copy into an existing CLI project.
4. **AC4 - CLI-first recovery guidance**: Health-check output for missing/stale CLI-owned assets instructs the operator to run the current FuseBase CLI refresh/update first, then Flow recovery second.
5. **AC5 - Flow-only recovery**: `post-fusebase-update` restores only Flow-owned assets and shared Flow additions: Flow skills, Flow agents, Flow lifecycle hooks, Flow overlay blocks, Flow health command/skill, and Flow policy/hook framework files.
6. **AC6 - Shared merge preservation**: Shared files are append/merge only. Existing CLI Stop hooks, MCP server allowlists, `.codex/config.toml` non-MCP settings, and CLI `CUSTOM:SKILL` blocks survive Flow recovery.
7. **AC7 - Health-check layer verdicts**: Health check can report at least `HEALTHY`, `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT`, and `BROKEN`, with next-action guidance for each.
8. **AC8 - Archive simulation test**: A regression test simulates a CLI refresh from the analyzed archive/project-template, then runs Flow recovery, and verifies CLI-owned files remain current while Flow-owned overlay pieces are restored.
9. **AC9 - Documentation updated**: `docs/install-fusebase-cli-project.md`, health-check docs, and recovery docs describe the CLI-first, Flow-second model in plain terms.
10. **AC10 - Existing gates pass**: `hooks/local/preflight.sh` and `hooks/tests/run-tests.sh` pass after implementation; any new simulation test is included in the verification gate.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths (`policies/protected-paths.yml`) | No downstream worker paths; framework internals may change under this ticket. |
| Mixed-fleet considerations | Required: install/recovery behavior must remain safe across Claude Code, Codex, Cursor, VS Code, and generic local workflows. |
| Migration approach | No database migration. |
| Auth model | No runtime auth change; MCP/secret/config files remain protected and never overwritten by Flow. |
| Quality bar (lint/typecheck/tests) | Existing preflight + hook tests required; add simulation coverage for CLI/Flow shared surfaces. |

## Wire format (if applicable)

Ownership map format is to be decided in planning. Candidate shape:

```yaml
schema_version: 1
paths:
  - path: "AGENTS.md"
    owner: "shared-merge"
    cli_action: "regenerate current CLI baseline"
    flow_action: "append Flow overlay block if missing"
  - path: ".claude/skills/**"
    owner: "mixed"
    cli_action: "current CLI owns provider skills"
    flow_action: "copy only canonical Flow skills from root skills/"
```

## Backend changes

- `hooks/local/fusebase-flow-health-check.sh` - likely extend diagnostics and verdict taxonomy.
- `hooks/local/post-fusebase-update.sh` - likely enforce/document Flow-only restoration and remove stale CLI-specific patch checks.
- `hooks/local/fusebase-flow-overlays/settings-json-merge.py` - likely verify shared merge preservation for Claude settings.
- `hooks/local/*` or new helper - likely add dry-run collision reporting for existing CLI/MCP installs.
- `policies/` or new manifest path - likely hold ownership classification.
- `hooks/tests/` - add archive/project-template simulation fixture and assertions.

## Client / extension / SPA changes

- None.

## Risks

- CLI freshness cannot be proven by Flow hashes without freezing CLI versions. Mitigation: verify CLI-owned presence/shape and recommend current CLI refresh rather than restoring CLI text.
- CLI update may perform side effects beyond agent assets. Mitigation: health check recommends exact skip flags or dry-run paths where possible; implementation planning must choose the least-side-effect command sequence.
- Shared TOML/JSON merges can accidentally drop unrelated settings. Mitigation: add focused tests for `.codex/config.toml`, `.claude/settings.json`, and MCP configs.
- CLI archive fixtures may go stale. Mitigation: fixture tests assert ownership behavior, not exact long-term CLI wording.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A | Flow must not restore CLI instructions from Flow's bundled copy; current CLI remains source of truth. | 2026-05-29 |
| Q-B | Recovery model is CLI-first, Flow-second. | 2026-05-29 |
| Q-C | Flow recovery restores Flow-owned overlay pieces only. | 2026-05-29 |
| Q-D | CLI drift detection is shape-only now; version-aware checks require a future CLI manifest. | 2026-05-29 |
| Q-E | This ticket implements health/recovery/dry-run diagnostics, not a write-capable installer. | 2026-05-29 |
| Q-F | Health output recommends exact CLI refresh flags only if implementation verifies support; otherwise it uses generic current-CLI refresh wording. | 2026-05-29 |

## Related

- `docs/specs/cli-first-flow-second-recovery/clarify-conversation.md`
- `docs/specs/cli-first-flow-second-recovery/decisions.md`
- `docs/specs/cli-first-flow-second-recovery/tasks.md`
- `docs/specs/cli-first-flow-second-recovery/verification-gate.md`
- `docs/fusebase-cli-edition.md`
- `docs/install-fusebase-cli-project.md`
- `docs/backlog/install-into-existing-fusebase-cli-project/README.md`
- `hooks/local/fusebase-flow-health-check.sh`
- `hooks/local/post-fusebase-update.sh`
