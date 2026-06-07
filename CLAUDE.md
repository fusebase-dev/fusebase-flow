# CLAUDE.md - Claude Code adapter for Fusebase Flow

This repo runs **Fusebase Flow v3.14.0**. The portable always-on baseline is in `AGENTS.md`. The full rule set is in `FLOW_RULES.md`. Read both before any other action.

## Claude Code-specific notes

| Surface | Where |
|---|---|
| Flow lifecycle skills (Claude Code reads automatically) | `.claude/skills/` entries mirrored from canonical `flow-skills/` |
| CLI provider skills (Claude Code reads automatically) | `.claude/skills/<cli-skill>/` entries copied from Fusebase Apps CLI provider assets |
| Flow and CLI app agents | `.claude/agents/` |
| Settings example (hooks wiring) | `.claude/settings.json.example` — copy to `.claude/settings.json` and customize before hooks run |
| Flow hook handlers | `hooks/handlers/*.py` (Python, lifecycle-event-named) |
| CLI quality hooks | `.claude/hooks/*` |
| Always-on rules | `FLOW_RULES.md` (FR-01..FR-23) |

## Skills behavior under Claude Code

- Skills load via SKILL.md frontmatter (`name`, `description`).
- Side-effecting skills (`release-deploy-reporting`, parts of `validation-and-qa`) carry `invocation: manual-for-side-effects` — Claude Code should not auto-invoke them. Operator triggers them explicitly.
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

## Self-attestation (every session's first response)

> "Operating as {role} under Fusebase Flow v3.14.0. I will follow FR-01 through FR-23. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

If your first response doesn't include this attestation, you're drifting. See `FLOW_RULES.md`.

## Operator questions

Per FR-19, ask operator questions in chat text. Do not use popup / clickable menu tools for clarify prompts, option selection, deploy confirmation, or recovery choices. Use a short markdown table or numbered list with **(Recommended)** marked when appropriate.

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
- Fusebase CLI edition bridge: `docs/fusebase-cli-edition.md`
- Tool compatibility matrix: `docs/compatibility.md`
- License clean-room attestation: `docs/clean-room.md`

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
- `handoff` — writes active session restart state to `docs/tmp/handoff.md` (16-section template) so a fresh session resumes exactly; operator-triggered (also via `/handoff`)

(27 canonical Fusebase Flow skills total.)

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