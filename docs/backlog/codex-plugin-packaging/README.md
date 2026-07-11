# Codex plugin packaging (codex-plugin-packaging)

**Status:** done (pending release)
**Filed:** 2026-06-29 (v3.29.0 baseline)
**Parent:** codex-slash-command-parity (shipped v3.29.0 — B command-equivalents table + A opt-in `/prompts:` installer)
**One-liner:** Package Flow's skills/agents as a Codex **plugin** (via `codex plugin marketplace`) — a distinct distribution from the v3.29.0 per-machine prompt installer.

## Why this is a separate ticket (verified ground truth, Codex CLI 0.128.0)

The v3.29.0 design review established that Codex **plugins bundle skills / mcp / apps / hooks — NOT slash commands**. So the two delivery channels do not overlap:

| Channel | Carries | Scope | Shipped? |
|---|---|---|---|
| Custom prompts (`$CODEX_HOME/prompts/*.md`) | the 6 `/prompts:<cmd>` | user-global, per-machine, Codex-**deprecated** | v3.29.0 (opt-in `install-codex-prompts.sh`) |
| Plugin (`codex plugin marketplace`) | skills / mcp / apps / hooks | distributable package | done (pending release) |

The command-parity problem is already solved by B (the `AGENTS.md` command-equivalents table, repo-portable, every agent) + A (the opt-in prompts). This ticket now ships the Codex plugin wrapper and a `product-owner` skill bridge so Codex users can discover Product Owner from `/product` or `/skills`.

## Resolved

- `.codex-plugin/plugin.json` is the Codex wrapper and points at the existing `.agents/skills/` mirror surface.
- `product-owner` is a thin canonical Flow skill that routes to the Product Owner agent body instead of duplicating it.
- `preflight.sh` parity-checks `.codex-plugin/plugin.json` version against `VERSION`.
- `test-codex-plugin-surface.sh` validates the manifest shape and Product Owner skill bridge.

## Constraints

- Additive / opt-in (same posture as A): plugin installation remains operator/host controlled.
- FR-07 clean: no FR-rule / deploy-policy / ratchet change.
- Verify the Codex plugin mechanism FIRST (the recurring trap — build only on a confirmed mechanism, not an assumed one).
