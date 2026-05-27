
---

## Fusebase Flow — additional rules (overlay)

This repository follows **Fusebase Flow** in addition to project-specific rules. See `AGENTS.md` § "Fusebase Flow — workflow lifecycle overlay" for the full reference.

**Always loaded at session start (Fusebase Flow mandatory skills, auto-loaded via `.claude/skills/`):**

- `skills/communication/SKILL.md` — Mode A (operator chat) / Mode B (internal artifacts)
- `skills/role-discipline/SKILL.md` — per-role don't-list + refusal phrasing

**On-demand Fusebase Flow skills (description-matched from `.claude/skills/`):**

- `code-review` — multi-perspective code review for PRs and significant patches
- `design-discovery-ideation` — explore product/UI/workflow options before spec or decision lock
- `fusebase-flow-health-check` — verify Fusebase Flow overlay state; offer recovery if drifted (also via `/fusebase-health`)
- `implementation-planning` — produce decisions.md, tasks.md, verification-gate.md from a clarified spec
- `release-deploy-reporting` — deploy reporting (manual-for-side-effects; do not auto-invoke)
- `repo-onboarding-context-map` — first-pass repo orientation for a new agent session
- `requirements-specification` — turn a feature ask into a clarified spec
- `security-permissions-review` — review of authz, secret handling, protected-paths
- `smoke-testing` — define and execute outcome-based deploy smoke with ground-truth diagnostics
- `task-delegation` — coordinate bounded read-only or disjoint implementation subtasks when the host supports subagents
- `validation-and-qa` — verification-gate authoring and execution

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
