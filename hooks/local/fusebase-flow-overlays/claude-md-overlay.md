
<!-- CUSTOM:SKILL:BEGIN -->

---

## Fusebase Flow — additional rules (overlay)

This repository follows **Fusebase Flow** in addition to project-specific rules. See `AGENTS.md` § "Fusebase Flow — workflow lifecycle overlay" for the full reference.

**Always loaded at session start (Fusebase Flow mandatory skills, auto-loaded via `.claude/skills/`):**

- `flow-skills/communication/SKILL.md` — Mode A (operator chat) / Mode B (internal artifacts)
- `flow-skills/role-discipline/SKILL.md` — per-role don't-list + refusal phrasing

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
- `skill-authoring` — create/update reusable skills (clean-room; incl. domain-expert mode)
- `zoom-out` — FR-20 root-cause-vs-patch check before a fix
- `phase-audit` — independent sub-agent audit of all slices of a phase
- `git-history-diagnostic` — regression archaeology (locate the causing commit)
- `project-onboarding` — `/onboard` discovery interview → writes project artifacts (operator-triggered)
- `north-star` — steer work to `docs/north-star.md` if present (no-op if absent)
- `client-vs-internal` — simple-for-client / robust-for-internal (no-op if absent)
- `product-docs-first` — design per-app product docs before code (no-op if absent)
- `business-logic-guardian` — protect documented business logic during fixes (no-op if absent)
- `product-apps-decomposition` — product → focused apps guidance
- `lightweight-lane` — FR-21 change-size tiering; small/reversible changes use a change-note + one build→verify→deploy pass instead of the full lifecycle
- `comment-policy` — FR-22 write-time carrier; delivers the tripwire + retrieval-pointer comment policy into a code-writing agent's context (description-matched on code/comment edits)
- `documentation-budget` — FR-23 doc-budget classifier; tier (0-4) before any AI-consumed artifact; canonical ownership + pointers over duplication; active handoff = `docs/tmp/handoff.md`
- `handoff` — portable skill: writes active session restart state to `docs/tmp/handoff.md`; operator-triggered (`/handoff` on Claude Code; invoke by name elsewhere)
- `module-size-discipline` — FR-25 module-size ratchet; gated source files stay ≤ ceiling (default 800), over-ceiling files may shrink never grow; extraction on a responsibility seam is in-scope; pre-commit gate + plan-time target-file rule

(28 canonical Fusebase Flow skills total.)

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