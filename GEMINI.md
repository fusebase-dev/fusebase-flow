# GEMINI.md - Gemini / Antigravity adapter for Fusebase Flow

This repo runs **Fusebase Flow v3.30.7**. The full portable baseline is in `AGENTS.md` and the full rule set is in `FLOW_RULES.md`. Read both before any other action (stop `FLOW_RULES.md` at `## Amendment log` — dated history, never load it).

## Gemini / Antigravity-specific notes

| Surface | Where |
|---|---|
| Always-on rules | `FLOW_RULES.md` (FR-01..FR-27) |
| Skills (read on demand) | `flow-skills/` (canonical) |
| CLI provider skills (read on demand by path/reference) | `.claude/skills/` and `.agents/skills/` CLI entries |
| Fusebase CLI edition bridge | `docs/fusebase-cli-edition.md` |
| Workflows | `workflows/` |
| Templates | `templates/` |

This adapter is intentionally minimal because Gemini / Antigravity-style IDEs don't have a documented hook surface in v0.1 of this template. Enforcement falls back to:

- Git hooks at `hooks/git/` (install via `hooks/local/install-git-hooks.sh`)
- Operator-led discipline (state announcements, self-attestation, save-before-chat)

## Self-attestation (every session's first response)

> "Operating as {role} under Fusebase Flow v3.30.7. I will follow FR-01 through FR-27. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

## State announcement (every output)

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

## Operator questions

Per FR-19, ask operator questions in chat text. Do not use popup / clickable menu tools. Use a short markdown table or numbered list with **(Recommended)** marked when appropriate.

## Limitations in v0.1 for this surface

- No native pre-tool-use hook coverage; rely on git pre-commit + operator vigilance.
- Skills are not auto-loaded by description match; operator references them explicitly ("invoke the `validation-and-qa` skill").
- CLI provider skills are supporting domain guidance for Fusebase Apps work; Flow lifecycle artifacts and role boundaries still govern the session.
- Permission-request hook coverage is unknown; require explicit confirmation in chat for every destructive op.

See `docs/compatibility.md` for the full surface-by-surface support breakdown.

## See also

- Portable always-on baseline: `AGENTS.md`
- Full rules: `FLOW_RULES.md`
- Fusebase CLI edition bridge: `docs/fusebase-cli-edition.md`