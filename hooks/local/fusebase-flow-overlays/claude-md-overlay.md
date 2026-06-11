
<!-- CUSTOM:SKILL:BEGIN -->

---

## Fusebase Flow — additional rules (overlay)

This repository follows **Fusebase Flow** in addition to project-specific rules. See `AGENTS.md` § "Fusebase Flow — workflow lifecycle overlay" for the full reference.

**Always loaded at session start (Fusebase Flow mandatory skills, auto-loaded via `.claude/skills/`):**

- `flow-skills/communication/SKILL.md` — Mode A (operator chat) / Mode B (internal artifacts)
- `flow-skills/role-discipline/SKILL.md` — per-role don't-list + refusal phrasing

**On-demand Fusebase Flow skills:** Claude Code auto-injects every skill description from `.claude/skills/` for matching — no in-file catalog needed.
The canonical catalog lives in README § Skill catalog and the `AGENTS.md` overlay skill list.
The 2 mandatory skills remain listed above (always loaded at session start).

**Slash commands (`.claude/commands/`):** `/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`.

**Active project context:** if `docs/north-star.md` / `docs/<app>/product.md` exist, read and follow them; if absent, run generically — never auto-create. Run `/onboard` to capture project vision.

**Fusebase Flow sub-agents (description-matched from `.claude/agents/`):**

- `product-owner` — covers phases 1–6 + Architect inline. PO Bash gated by `hooks/local/po-investigate.sh` allowlist (read-only investigation only).
- `ai-developer` — covers phase 7 (AI Developer attestation when given `*-implement.md` handoff) and phase 8b (Deploy phase attestation when given `*-deploy.md` handoff). Deploy gated by DP.6 magic-phrase confirm + DP.1 approval artifact.

**State announcement footer (every output):**

> ---
> Phase: {Specify | Clarify | Plan | Decisions | Tasks | Verify | Implement | Deploy}
> Ticket: {slug or "—"}
> Next: {what the operator does next}

**Operator questions:** per FR-19, ask questions in chat text, not popup / clickable menu tools. Use short option tables or numbered lists so the operator can copy, forward, quote, and follow up.

Project-specific rules in `AGENTS.md` (CLI/MCP/SDK conventions, type-safety, runtime constraints) take precedence over any Fusebase Flow rule that overlaps.

<!-- CUSTOM:SKILL:END -->