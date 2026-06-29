# Codex plugin packaging (codex-plugin-packaging)

**Status:** parked
**Filed:** 2026-06-29 (v3.29.0 baseline)
**Parent:** codex-slash-command-parity (shipped v3.29.0 — B command-equivalents table + A opt-in `/prompts:` installer)
**One-liner:** Package Flow's skills/agents as a Codex **plugin** (via `codex plugin marketplace`) — a distinct distribution from the v3.29.0 per-machine prompt installer.

## Why this is a separate ticket (verified ground truth, Codex CLI 0.128.0)

The v3.29.0 design review established that Codex **plugins bundle skills / mcp / apps / hooks — NOT slash commands**. So the two delivery channels do not overlap:

| Channel | Carries | Scope | Shipped? |
|---|---|---|---|
| Custom prompts (`$CODEX_HOME/prompts/*.md`) | the 6 `/prompts:<cmd>` | user-global, per-machine, Codex-**deprecated** | v3.29.0 (opt-in `install-codex-prompts.sh`) |
| Plugin (`codex plugin marketplace`) | skills / mcp / apps / hooks | distributable package | **this ticket** |

The command-parity problem is already solved by B (the `AGENTS.md` command-equivalents table, repo-portable, every agent) + A (the opt-in prompts). This ticket is about whether Flow's **skills + agents** should additionally ship as a first-class Codex plugin so multi-agent users get them via Codex's own package manager rather than the repo mirror.

## Open questions (resolve at Specify)

- Does a Codex plugin add real value over the existing `.agents/skills/` + `.codex/agents/` mirrors that Codex already reads from the repo?
- Single-source: a plugin manifest must generate from canonical `flow-skills/` + `agents/` (drift-guard, like A's transform) — never a hand-maintained third copy.
- Distribution: marketplace listing vs local install; versioning against `VERSION`.
- Overlap with the Claude Code plugin (`.claude-plugin/plugin.json`) — keep one canonical source, two package wrappers.

## Constraints

- Additive / opt-in (same posture as A): never default-on, never wired into `post-fusebase-update.sh`.
- FR-07 clean: no FR-rule / deploy-policy / ratchet change.
- Verify the Codex plugin mechanism FIRST (the recurring trap — build only on a confirmed mechanism, not an assumed one).
