# CLAUDE.md — Claude Code adapter for Fusebase Flow

This repo runs Fusebase Flow v4.14.1. Read `AGENTS.md`, `FLOW_RULES.md` through `## Amendment log`, both mandatory skill bodies, `flow-skills/role-discipline/references/<role>.md`, and the active workflow/ticket artifacts. Canonical provider details are in the recovery-owned adapter below.

For maintenance work in this repository, also read `docs/maintainer-execution.md`. It is not copied into consumers.

<!-- CUSTOM:SKILL:BEGIN -->

---

## FuseBase Flow — Claude Code adapter

Read `AGENTS.md`, then `FLOW_RULES.md` through `## Amendment log`. Claude Code supplies skill descriptions/metadata, not skill bodies. Read `flow-skills/communication/SKILL.md`, `flow-skills/role-discipline/SKILL.md`, and the attested role's reference once unless each exact body is already in context. Read the active workflow and ticket/handoff. Use the attestation and state footer from `FLOW_RULES.md`.

| Claude surface | Canonical owner |
|---|---|
| lifecycle skills | `flow-skills/` mirrored to `.claude/skills/` |
| role agents | `agents/` mirrored to `.claude/agents/` |
| commands (`/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort`, `/find-wasted-code`) | `hooks/local/fusebase-flow-overlays/commands/` mirrored to `.claude/commands/` |
| lifecycle hooks | `hooks/handlers/` via `.claude/settings.json.example` |
| CLI runtime/quality guidance | CLI-owned `.claude/skills/`, `.claude/agents/`, `.claude/hooks/` |

Hooks are opt-in until `.claude/settings.json.example` is merged into `.claude/settings.json`; Git hooks remain the fallback. Existing Fusebase CLI runtime/MCP/SDK rules override generic Flow guidance; Flow owns the lifecycle. For active context, commands, install/update recovery, and mixed-fleet behavior, use `AGENTS.md`; do not reprint those procedures here.

<!-- CUSTOM:SKILL:END -->
