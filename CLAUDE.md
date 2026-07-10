# CLAUDE.md - Claude Code adapter for Fusebase Flow

This repo runs **Fusebase Flow v4.2.2**. The portable always-on baseline is in `AGENTS.md`. The full rule set is in `FLOW_RULES.md`. Read both before any other action (stop `FLOW_RULES.md` at `## Amendment log` — dated history, never load it).

## Claude Code-specific notes

| Surface | Where |
|---|---|
| Flow lifecycle skills (Claude Code reads automatically) | `.claude/skills/` entries mirrored from canonical `flow-skills/` |
| CLI provider skills (Claude Code reads automatically) | `.claude/skills/<cli-skill>/` entries copied from Fusebase Apps CLI provider assets |
| Flow and CLI app agents | `.claude/agents/` |
| Settings example (hooks wiring) | `.claude/settings.json.example` — copy to `.claude/settings.json` and customize before hooks run |
| Flow hook handlers | `hooks/handlers/*.py` (Python, lifecycle-event-named) |
| CLI quality hooks | `.claude/hooks/*` |
| Always-on rules | `FLOW_RULES.md` (FR-01..FR-27; stop at `## Amendment log` — dated history) |

## Skills behavior under Claude Code

- Skills load via SKILL.md frontmatter (`name`, `description`).
- The side-effecting skill `release-deploy-reporting` carries `invocation: manual-for-side-effects` — Claude Code should not auto-invoke it. Operator triggers it explicitly. (`validation-and-qa` is `invocation: automatic`; be mindful that its release/deploy sub-flows have side effects when run in that context.)
- Skill descriptions are trigger-oriented: include "Use when..." and "Do NOT use when..." so the matcher can decide.
- For Fusebase Apps runtime work, load the relevant CLI provider skill as supporting domain guidance while keeping Flow artifacts and role rules authoritative.

## Hooks behavior under Claude Code

`.claude/settings.json.example` wires Flow lifecycle events to the canonical handlers and preserves CLI Stop hooks:

- `SessionStart` → `hooks/handlers/session_start.py`
- `UserPromptSubmit` → `hooks/handlers/user_prompt_submit.py`
- `PreToolUse` → `hooks/handlers/pre_tool_use.py`
- `PostToolUse` → `hooks/handlers/post_tool_use.py`
- `Stop` → CLI lint/typecheck/app quality hooks, then `hooks/handlers/stop.py`
- `PreCompact` → `hooks/handlers/pre_compact.py`

Hooks read policies from `policies/*.yml`. They are **opt-in**: nothing runs until you copy `settings.json.example` → `settings.json`. The git fallback hooks (`hooks/git/`) provide a safety net even when Claude Code hooks are off.

## Attestation, footer, operator questions

Apply all three every session. Canonical homes: self-attestation text — `AGENTS.md` overlay § Self-attestation (also `FLOW_RULES.md` § Self-attestation); state-announcement footer + FR-19 chat-text question rule — the overlay below (§ Fusebase Flow — additional rules).

## Quick activation

```bash
# Enable hooks (one-time). Lifecycle hooks route through hooks/local/run-handler.sh,
# which auto-detects your Python interpreter (python3 / py / python) — no manual edit.
# Prerequisite: Python 3.11+ for the hook handlers; without it hooks self-disable with
# one warning (Flow still works; git fallback hooks still enforce protected paths/secrets).
cp .claude/settings.json.example .claude/settings.json

# Enable git fallback hooks (one-time)
bash hooks/local/install-git-hooks.sh
```

## See also

- Portable always-on baseline: `AGENTS.md`
- Fusebase CLI edition bridge: `docs/fusebase-cli-edition.md`
- Tool compatibility matrix: `docs/compatibility.md`
- License clean-room attestation: `docs/clean-room.md`

<!-- CUSTOM:SKILL:BEGIN -->

---

## FuseBase Flow — additional rules (overlay)

This repository follows **Fusebase Flow** in addition to project-specific rules. See `AGENTS.md` § "FuseBase Flow — workflow lifecycle overlay" for the full reference.

**Always loaded at session start (Fusebase Flow mandatory skills, auto-loaded via `.claude/skills/`):**

- `flow-skills/communication/SKILL.md` — Mode A (operator chat) / Mode B (internal artifacts)
- `flow-skills/role-discipline/SKILL.md` — shared role protocols + role index (don't-lists lazy-load from `references/<role>.md`)

**On-demand Fusebase Flow skills:** Claude Code auto-injects every skill description from `.claude/skills/` for matching — no in-file catalog needed.
The canonical catalog lives in README § Skill catalog and the `AGENTS.md` overlay skill list.
The 2 mandatory skills remain listed above (always loaded at session start).

**Slash commands (`.claude/commands/`):** `/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort` — native here. The cross-agent equivalents (Codex `/prompts:<cmd>` + the portable skill-name fallback) are in the `AGENTS.md` command-equivalents table.

**Active project context:** if `docs/north-star.md` / `docs/<app>/product.md` exist, read and follow them; if absent, run generically — never auto-create. Run `/onboard` to capture project vision.

**Fusebase Flow sub-agents (description-matched from `.claude/agents/`):**

- `product-owner` — covers phases 1–6 + Architect inline. PO Bash is instructed to route through the `hooks/local/po-investigate.sh` read-only wrapper (the structural allowlist lives inside the wrapper; a direct Bash call bypassing it is a discipline breach, not a hook-blocked action).
- `ai-developer` — covers phase 7 (AI Developer attestation when given `*-implement.md` handoff) and phase 8b (Deploy phase attestation when given `*-deploy.md` handoff). Deploy gated by DP.6 magic-phrase confirm + DP.1 approval artifact.

**State announcement footer (every output):**

> ---
> Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
> Ticket: {slug or "—"}
> Next: {what the operator does next}

**Operator questions:** per FR-19, ask questions in chat text, not popup / clickable menu tools. Use short option tables or numbered lists so the operator can copy, forward, quote, and follow up.

Project-specific rules in `AGENTS.md` (CLI/MCP/SDK conventions, type-safety, runtime constraints) take precedence over any Fusebase Flow rule that overlaps.

<!-- CUSTOM:SKILL:END -->