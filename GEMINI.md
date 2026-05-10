# GEMINI.md — Gemini / Antigravity adapter for Fusebase Flow

This repo runs **Fusebase Flow Local v2.1**. The full portable baseline is in `AGENTS.md` and the full rule set is in `FLOW_RULES.md`. Read both before any other action.

## Gemini / Antigravity-specific notes

| Surface | Where |
|---|---|
| Always-on rules | `FLOW_RULES.md` (FR-01..FR-18) |
| Skills (read on demand) | `skills/` (canonical) |
| Workflows | `workflows/` |
| Templates | `templates/` |

This adapter is intentionally minimal because Gemini / Antigravity-style IDEs don't have a documented hook surface in v0.1 of this template. Enforcement falls back to:

- Git hooks at `hooks/git/` (install via `hooks/local/install-git-hooks.sh`)
- Operator-led discipline (state announcements, self-attestation, save-before-chat)

## Self-attestation (every session's first response)

> "Operating as {role} under Fusebase Flow v2.1. I will follow FR-01 through FR-18. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

## State announcement (every output)

```
---
📍 Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
🎯 Ticket: {slug or "—"}
⏭️ Next: {what the operator does next}
```

## Limitations in v0.1 for this surface

- No native pre-tool-use hook coverage; rely on git pre-commit + operator vigilance.
- Skills are not auto-loaded by description match; operator references them explicitly ("invoke the `validation-and-qa` skill").
- Permission-request hook coverage is unknown; require explicit confirmation in chat for every destructive op.

See `docs/compatibility.md` for the full surface-by-surface support breakdown.

## See also

- Portable always-on baseline: `AGENTS.md`
- Full rules: `FLOW_RULES.md`
