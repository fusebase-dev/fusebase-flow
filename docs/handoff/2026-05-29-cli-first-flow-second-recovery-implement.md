# Implement handoff - cli-first-flow-second-recovery

**Role:** AI Developer
**Created:** 2026-05-29
**Spec:** `docs/specs/cli-first-flow-second-recovery/spec.md`
**Decisions:** `docs/specs/cli-first-flow-second-recovery/decisions.md`
**Tasks:** `docs/specs/cli-first-flow-second-recovery/tasks.md`
**Gate:** `docs/specs/cli-first-flow-second-recovery/verification-gate.md`
**Status:** ready for implementation

## Start state

- Operator locked recommended clarify/decision path with `lock recommended`.
- CLI archive analyzed at `C:\Users\abcpa\OneDrive\Downloads\apps-cli-main (1).zip`.
- Temporary extraction used during analysis: `C:\tmp\apps-cli-main-1-analysis-20260528-223555\apps-cli-main`.
- Archive package: `fusebase-apps-cli` version `0.25.5`.
- Current repo branch before implementation: `main`.
- Recent baseline commit: `95f9bcb T1: package Fusebase CLI edition v3.1`.

## Required reads

1. `FLOW_RULES.md`
2. `AGENTS.md`
3. `docs/specs/cli-first-flow-second-recovery/spec.md`
4. `docs/specs/cli-first-flow-second-recovery/decisions.md`
5. `docs/specs/cli-first-flow-second-recovery/tasks.md`
6. `docs/specs/cli-first-flow-second-recovery/verification-gate.md`
7. `hooks/local/post-fusebase-update.sh`
8. `hooks/local/fusebase-flow-health-check.sh`

## Implementation chain

Run T2..T8 in order. Commit each implementation task separately with subjects beginning `T<n>:`. Stop after T8 gate report. No production deploy applies.

## Load-bearing facts from CLI archive

| Fact | Consequence |
|---|---|
| CLI `copyAgentsAndSkills()` captures and restores `CUSTOM:SKILL` blocks. | Flow AGENTS overlay can use custom block wrapper; Flow still must not own CLI AGENTS text. |
| CLI refresh touches `AGENTS.md`, `.claude/skills`, `.claude/agents`, `.claude/hooks`, `.claude/settings.json`, IDE/MCP config. | Ownership manifest must classify these surfaces explicitly. |
| CLI package has newer provider skill content than this Flow edition copy. | Flow must never restore CLI provider skills from its bundled copy. |
| CLI `.codex/config.toml` merge path can drop non-MCP keys. | Health/conflict docs must warn and tests must preserve existing Codex settings where Flow controls writes. |
| Current CLI hook is `run-typecheck-apps.js` and already contains Windows shell handling. | Flow recovery should remove stale `run-typecheck-features.js` patch behavior. |

## Verification commands

Use Git Bash explicitly on this Windows host:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' hooks/local/preflight.sh
& 'C:\Program Files\Git\bin\bash.exe' hooks/tests/run-tests.sh
& 'C:\Program Files\Git\bin\bash.exe' hooks/tests/test-cli-flow-recovery.sh
& 'C:\Program Files\Git\bin\bash.exe' hooks/local/fusebase-flow-health-check.sh
& 'C:\Program Files\Git\bin\bash.exe' hooks/local/check-cli-flow-conflicts.sh
git status --short
git diff --stat
```

## Stop conditions

- If a task requires writing active downstream FuseBase CLI project files outside this repo, stop and ask.
- If health recovery would need to copy CLI provider text from Flow into a project, stop; that violates A2/A3.
- If a protected path under `policies/*.yml`, `hooks/handlers/**`, `hooks/shared/**`, or `hooks/git/**` becomes necessary, create/obtain the appropriate protected-path approval artifact before editing.
