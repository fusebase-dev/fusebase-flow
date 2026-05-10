# CLAUDE.md — Claude Code adapter for Fusebase Flow

This repo runs **Fusebase Flow Local v2.1**. The portable always-on baseline is in `AGENTS.md`. The full rule set is in `FLOW_RULES.md`. Read both before any other action.

## Claude Code-specific notes

| Surface | Where |
|---|---|
| Project skills (Claude Code reads automatically) | `.claude/skills/` (mirrored from canonical `skills/`) |
| Settings example (hooks wiring) | `.claude/settings.json.example` — copy to `.claude/settings.json` and customize before hooks run |
| Hook handlers | `hooks/handlers/*.py` (Python, lifecycle-event-named) |
| Always-on rules | `FLOW_RULES.md` (FR-01..FR-17) |

## Skills behavior under Claude Code

- Skills load via SKILL.md frontmatter (`name`, `description`).
- Side-effecting skills (`release-deploy-reporting`, parts of `validation-and-qa`) carry `invocation: manual-for-side-effects` — Claude Code should not auto-invoke them. Operator triggers them explicitly.
- Skill descriptions are trigger-oriented: include "Use when..." and "Do NOT use when..." so the matcher can decide.

## Hooks behavior under Claude Code

`.claude/settings.json.example` wires lifecycle events to the canonical handlers:

- `SessionStart` → `hooks/handlers/session_start.py`
- `UserPromptSubmit` → `hooks/handlers/user_prompt_submit.py`
- `PreToolUse` → `hooks/handlers/pre_tool_use.py`
- `PostToolUse` → `hooks/handlers/post_tool_use.py`
- `Stop` → `hooks/handlers/stop.py`
- `PreCompact` → `hooks/handlers/pre_compact.py`

Hooks read policies from `policies/*.yml`. They are **opt-in**: nothing runs until you copy `settings.json.example` → `settings.json`. The git fallback hooks (`hooks/git/`) provide a safety net even when Claude Code hooks are off.

## Self-attestation (every session's first response)

> "Operating as {role} under Fusebase Flow v2.1. I will follow FR-01 through FR-17. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

If your first response doesn't include this attestation, you're drifting. See `FLOW_RULES.md`.

## State announcement (every output)

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

## Quick activation

```bash
# Enable hooks (one-time)
cp .claude/settings.json.example .claude/settings.json
# Edit .claude/settings.json to point hooks at your Python interpreter

# Enable git fallback hooks (one-time)
bash hooks/local/install-git-hooks.sh
```

## See also

- Portable always-on baseline: `AGENTS.md`
- Tool compatibility matrix: `docs/compatibility.md`
- License clean-room attestation: `docs/clean-room.md`
