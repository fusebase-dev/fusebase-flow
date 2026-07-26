
<!-- CUSTOM:SKILL:BEGIN -->

---

## FuseBase Flow — additional rules (overlay)

This repository follows **Fusebase Flow** in addition to project-specific rules. See `AGENTS.md` § "FuseBase Flow — workflow lifecycle overlay" for the full reference.

**Mandatory skills — required at session start (`.claude/skills/` supplies their descriptions, never their bodies):**

- `flow-skills/communication/SKILL.md` — Mode A (operator chat) / Mode B (internal artifacts)
- `flow-skills/role-discipline/SKILL.md` — shared role protocols + role index (don't-lists lazy-load from `references/<role>.md`)

Claude Code injects skill **descriptions/metadata only — the bodies are not injected** (verified first-hand; `hooks/handlers/session_start.py` existence-checks these files and emits reminders, it never injects a body). So: if the exact body is not already in your context, `Read` it once. Skip the Read **only** on that body-presence check — never because the surface is Claude Code, and never because the name/description appeared in the skill index. Always separate real reads: `role-discipline/references/<role>.md` and a **delegated sub-agent session** (`session_start` doesn't fire for it — it inherits nothing). Other surfaces: the per-surface matrix is in the `AGENTS.md` overlay.

**On-demand Fusebase Flow skills:** Claude Code auto-injects every skill description from `.claude/skills/` for matching — no in-file catalog needed.
The canonical catalog lives in README § Skill catalog and the `AGENTS.md` overlay skill list.
The 2 mandatory skills remain listed above (read at session start — descriptions inject, bodies do not).

**Slash commands (`.claude/commands/`):** `/fusebase-health`, `/onboard`, `/product-owner`, `/handoff`, `/token-waste-audit`, `/find-wasted-effort`, `/find-wasted-code` — native here. The cross-agent equivalents (Codex `/prompts:<cmd>` + the portable skill-name fallback) are in the `AGENTS.md` command-equivalents table.

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