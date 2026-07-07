# AGENTS.md - Fusebase Flow always-on baseline

This repo uses **Fusebase Flow**: a repo-local discipline framework for AI coding agents and IDEs, packaged with Fusebase Apps domain skills, agents, and Claude Code quality hooks. The full rule set is at `FLOW_RULES.md`. This file is the portable always-on baseline that every agent reads first regardless of tool.

## What Fusebase Flow is (and isn't)

| Is | Isn't |
|---|---|
| Repo-local discipline (rules, skills, workflows, hooks, policies, templates) | A coding agent or chat product |
| Activated when you open the repo in any agentic IDE | A SaaS or external service |
| Tool-portable across Cursor, Claude Code, Codex, GitHub Copilot/VS Code, Gemini-style IDE agents, and generic local workflows | Tied to one vendor |
| A GitHub template you copy into projects | Auto-installed dependencies |

## Layering: lifecycle + domain

Fusebase Flow includes original Fusebase Apps CLI provider assets as a runtime/domain layer. Flow remains the lifecycle layer.

| Layer | Owns | Paths |
|---|---|---|
| Flow lifecycle | specs, decisions, tasks, verification gates, reviews, deploy handoffs, smoke contracts | `FLOW_RULES.md`, `flow-skills/`, `workflows/`, `templates/`, `policies/`, `hooks/` |
| CLI domain | Fusebase Apps implementation guidance, MCP/dashboard/gate usage, routing, secrets, logs, scaffold quality | `.claude/skills/<cli-skill>/`, `.agents/skills/<cli-skill>/`, `.claude/agents/`, `.codex/agents/`, `.claude/hooks/` |

Runtime, MCP, SDK, and app-domain rules from CLI skills win over generic Flow implementation guidance when they overlap. Flow still governs the lifecycle artifact, approval, and smoke discipline. See `docs/fusebase-cli-edition.md` for the full mapping.

## How to use this repo as an agent

1. **First action of every session:** load `FLOW_RULES.md` **down to `## Amendment log`** (the log is dated history — never load it; ~40% of the file). Then load the active workflow if a ticket is in progress.
2. **Self-attest your role** (Product Owner, AI Developer, Architect, Deploy) — see `FLOW_RULES.md` role table.
3. **Append the state-announcement footer** to every output.
4. **Ask before you act** when the task is non-trivial (multi-file, deploy, schema, auth, secrets).
5. **One task = one commit** when in AI Developer role; commit messages cite a `T<number>`.
6. **Save handoffs to disk before chat output** — never hand work across sessions through chat alone.
7. **Ask questions in chat text, not popups** — options must be copyable, scrollable, forwardable, and open to follow-up.

## Active project context — read first

Before starting work, check whether this project has been **onboarded** — see the identical check + artifact table in the overlay below (§ Active project context — read first; single copy).

## Where things live

| Need | Path |
|---|---|
| Always-on rules | `FLOW_RULES.md` |
| Workflows (procedures) | `workflows/` |
| Skills (on-demand expertise) | `flow-skills/` (canonical) — mirrored to `.claude/skills/` and `.agents/skills/` |
| Fusebase CLI edition bridge | `docs/fusebase-cli-edition.md` |
| CLI provider assets | `.claude/skills/`, `.agents/skills/`, `.claude/agents/`, `.codex/agents/`, `.claude/hooks/` |
| Policies (YAML, machine-readable) | `policies/` |
| Hooks (deterministic enforcement) | `hooks/` |
| Templates (artifact substrates) | `templates/` |
| Audit and paper trail | `audit/` |
| Active tickets and specs | `docs/specs/<slug>/`, `docs/backlog/<slug>/` |
| Active session continuity | `docs/tmp/handoff.md` (single live file, timestamped; `Mode: restart` — operator-triggered — or `Mode: run-ledger` — autonomous continuity, announced in chat. Archived to `docs/tmp/handoff/archive/` on restart supersede / mode transition only; run-ledger updates supersede in place. Dated history, never loaded; FR-23 Tier 2 / FR-18) |
| Formal cross-session relay prompts | `docs/tmp/handoff/<YYYY-MM-DD>-<slug>-<stage>.md` (implement / deploy) |

## Rules vs skills vs workflows vs hooks vs policies vs ignore

| Concept | Definition | Always loaded? |
|---|---|---|
| Rule | Always-on behavior | Yes |
| Skill | On-demand expertise (loaded when triggered by description match) | No |
| Workflow | Repeatable procedure (loaded when running the procedure) | No |
| Hook | Deterministic enforcement at lifecycle events | Yes (when the hosting tool supports them) |
| Policy | Machine-readable rule data (read by hooks) | Indirectly via hooks |
| Ignore | Path/access boundary (`.gitignore`, tool-specific ignore files) | Yes (by the tool that reads them) |

## Communication discipline (Mode A vs Mode B)

- **Mode A (operator chat):** visual, concrete, brief. ASCII roadmap / decision-tree / comparison / dependency / timeline diagrams when state has spatial relationships. Status footer otherwise.
- **Mode B (internal artifacts):** dense, tabular, front-loaded. Files in `docs/specs/`, `docs/decisions/`, `docs/tmp/handoff/`, `docs/problem-catalog/`, `docs/backlog/` are AI-consumed — no narrative padding, no human-onboarding preamble.

Visuals belong in chat only, never in Mode-B files.
Questions and choices also belong in chat text, never in popup / clickable menu tools.

## Destructive ops (never without explicit confirmation)

`rm -rf`, `git push --force`, `git reset --hard`, `git checkout -- .`, `git clean -fdx`, `git add -A`, `git add .`, `--no-verify`, deploy commands without a saved approval artifact. Full deny/require-approval list at `policies/command-policy.yml`. The `pre_tool_use` hook (where supported) and `pre-commit` git hook block these by default.

## Starting your first ticket

1. Tell the agent: "Let's ship `<feature description>`."
2. Agent invokes the `requirements-specification` skill → drafts `docs/specs/<slug>/spec.md`, runs clarify questions; if the operator asks for options, `design-discovery-ideation` produces the option brief before lock.
3. After clarify resolves: agent invokes `implementation-planning` skill → drafts `decisions.md`, `tasks.md`, `verification-gate.md`, and saves `docs/tmp/handoff/<date>-<slug>-implement.md`.
4. Open a fresh agent session, paste the implement handoff, agent executes task chain stopping at the gate.
5. Paste the gate report into the original session, agent invokes `code-review`; `security-permissions-review` runs only when the diff touches its trigger surfaces (auth, secrets, env, deploy config, external messages, production data), else the review summary records `security: N/A — no sensitive surface`.
6. If clean, agent invokes `release-deploy-reporting` skill → drafts `docs/tmp/handoff/<date>-<slug>-deploy.md` with smoke prompts governed by `smoke-testing` when applicable.

## Activating provider and IDE compatibility files

| Provider / IDE | What to do |
|---|---|
| Anthropic Claude Code | Reads `CLAUDE.md` automatically. Skills mirrored to `.claude/skills/`. Hooks via `.claude/settings.json.example` (rename + customize). |
| OpenAI / ChatGPT Codex | Reads `AGENTS.md`. Skills mirrored to `.agents/skills/`. Hooks via `.codex/hooks.json.example` and `.codex/config.toml.example`. |
| Cursor | Reads `.cursor/rules/*.mdc`. AGENTS.md is also loaded. No native hooks; relies on git hooks and workflows. |
| GitHub Copilot / VS Code | Reads `.github/copilot-instructions.md` and `.github/instructions/*.instructions.md`. AGENTS.md is also loaded. No native hooks; relies on git hooks and workflows. |
| Gemini / Antigravity-style IDE agents | Reads `AGENTS.md` and `GEMINI.md`. |
| Generic local repo workflow | `AGENTS.md` plus `*` (rules, workflows, skills, policies, templates, hooks, git fallback, local scripts). |

If your provider supports project-trust prompts (Codex, etc.), accept them so hooks can run.

## Installation safety rule

When installing Fusebase Flow into an existing repository, never automatically overwrite these files or folders:

- `AGENTS.md`
- `CLAUDE.md`
- `.gitignore`
- `.claude/settings.json`
- `.mcp.json`
- `.cursor/mcp.json`
- `fusebase.json`
- `skills-lock.json`
- existing `.agents/skills/`
- existing `.claude/skills/`
- existing `.github/workflows/`

If any of these files or folders already exist, append or merge only after reviewing the existing content.

Preserve existing Fusebase CLI, MCP, SDK, provider, and project-specific rules. Fusebase Flow is a workflow lifecycle overlay, not a replacement for runtime/MCP configuration. See `docs/install-fusebase-cli-project.md` for the safe-install procedure.

## Project-specific values

Single copy lives in the overlay's `FLOW:PRESERVE` block below (§ Project-specific values) — fill via `/onboard` or edit there; preserved across overlay refreshes. Narrative reasoning belongs in `docs/constitution.md`; machine-readable enforcement in `policies/`.

## Quick links

- Full rules: `FLOW_RULES.md`
- Eight-phase flow: `workflows/eight-phase-flow.md`
- Project constitution (narrative): `docs/constitution.md`
- Fusebase CLI edition bridge: `docs/fusebase-cli-edition.md`
- Operator discipline: `docs/operator-discipline.md`
- Architecture overview: `docs/architecture-overview.md`
- Key tensions: `docs/tradeoffs.md`
- Skill catalog: `flow-skills/`
- Audit package: `audit/`
- Compatibility matrix: `docs/compatibility.md`
- Safe install into Fusebase CLI / MCP repos: `docs/install-fusebase-cli-project.md`

<!-- CUSTOM:SKILL:BEGIN -->

---

## FuseBase Flow — workflow lifecycle overlay

This repository follows **Fusebase Flow** (https://github.com/fusebase-dev/fusebase-flow) for AI agent workflow discipline. The Fusebase Flow framework governs the workflow lifecycle (specification → planning → decisions → tasks → verification → implementation → review → deploy readiness). Existing project rules (Fusebase CLI, MCP, SDK, runtime conventions) remain authoritative for runtime behavior.

Fusebase Flow ships:

- **Always-on rules:** `FLOW_RULES.md` (FR-01..FR-27; read it down to `## Amendment log` — the log is dated history, never load it)
- **Mandatory skills (auto-loaded via `.claude/skills/` and `.agents/skills/`):** `communication`, `role-discipline`
- **On-demand skills (description-matched):** `code-review`, `design-discovery-ideation`, `implementation-planning`, `release-deploy-reporting`, `repo-onboarding-context-map`, `requirements-specification`, `security-permissions-review`, `smoke-testing`, `task-delegation`, `validation-and-qa`, `skill-authoring`, `fusebase-flow-health-check`, `zoom-out`, `phase-audit`, `git-history-diagnostic`, `project-onboarding`, `north-star`, `client-vs-internal`, `product-docs-first`, `business-logic-guardian`, `product-apps-decomposition`, `lightweight-lane`, `comment-policy`, `documentation-budget`, `handoff`, `module-size-discipline`, `app-quality-patterns`, `token-economy`, `liveness-discipline`, `find-wasted-effort` (32 canonical skills total)
- **Sub-agents (description-matched from `.claude/agents/`):** `product-owner` (phases 1–6 + Architect inline), `ai-developer` (phase 7 AI Developer + phase 8b Deploy attestation)
- **Workflows:** `workflows/*.md`
- **Policies:** `policies/*.yml` (machine-readable; consumed by hooks)
- **Hooks:** `hooks/handlers/*.py` (lifecycle events wired in `.claude/settings.json`)
- **Templates:** `templates/*.md`

**Self-attestation (every session's first response):**

> "Operating as {role} under Fusebase Flow v3.30.8. I will follow FR-01 through FR-27. I will apply Mode A on chat output and Mode B on every internal-artifact write. I will apply the role-discipline skill section for {role}."

**Operator questions:** per FR-19, ask questions in chat text, not popup / clickable menu tools. Use short option tables or numbered lists so the operator can copy, forward, quote, and follow up.

**Command equivalents.** The 6 commands are native Claude Code slash commands; on every other agent invoke the named skill (or type the command as text). Canonical command bodies live in `hooks/local/fusebase-flow-overlays/commands/*.md` (no body re-paste here — pointer only).

| Command | Claude Code | Codex (`/prompts:<cmd>` if installed) | Portable (any agent) |
|---|---|---|---|
| `/product-owner` | `/product-owner` | `/prompts:product-owner` | invoke the `product-owner` agent / type `/product-owner` |
| `/onboard` | `/onboard` | `/prompts:onboard` | invoke the `project-onboarding` skill / type `/onboard` |
| `/handoff` | `/handoff` | `/prompts:handoff` | invoke the `handoff` skill / type `/handoff` |
| `/fusebase-health` | `/fusebase-health` | `/prompts:fusebase-health` | invoke the `fusebase-flow-health-check` skill / type `/fusebase-health` |
| `/token-waste-audit` | `/token-waste-audit` | `/prompts:token-waste-audit` | invoke the `token-economy` skill / type `/token-waste-audit` |
| `/find-wasted-effort` | `/find-wasted-effort` | `/prompts:find-wasted-effort` | invoke the `find-wasted-effort` skill / type `/find-wasted-effort` |

Claude Code surfaces these from `.claude/commands/`. The Codex `/prompts:<cmd>` column applies only after the per-machine opt-in install (`bash hooks/local/install-codex-prompts.sh`; user-global, Codex-deprecated). Cursor/Copilot/Gemini have no native command mechanism — use the Portable column (invoke the skill, or type the command as text and the agent follows it).

### Active project context — read first

Check whether this project has been onboarded. These artifacts are **absent by default** (created only by `/onboard` or manually):

| Artifact | If present → | If absent → |
|---|---|---|
| `docs/north-star.md` | read it; keep work aligned to the vision (`north-star` skill) | run generically; do not create it |
| `docs/<app>/product.md` | read it for that app's product intent | run generically |
| `docs/<app>/business-logic.md` | treat documented logic as a guard during fixes | run generically |

This check is universal across every surface (it lives in this file, which every agent reads). On Claude Code the `SessionStart` hook also surfaces these automatically, but discovery does not depend on hooks. If an artifact is absent, Fusebase Flow runs as a generic install — no clutter. Run `/onboard` to capture project vision.

### Maintenance posture (Fusebase CLI ↔ Fusebase Flow coexistence)

> **Flow's canonical skills live in `flow-skills/` (v3.9.0+), not root `skills/`.** The FuseBase CLI deprecates the root `./skills` folder (`⚠️ The ./skills folder is obsolete and should be deleted`); Flow now uses the Flow-namespaced `flow-skills/`, which the CLI never touches, so that warning is safe to follow. `hooks/local/mirror-skills.sh`, `hooks/local/upgrade.sh`, and the health check's mirror-count all build on `flow-skills/`. Upgrading from a pre-3.9.0 install: `bash hooks/local/upgrade.sh` auto-migrates (moves `skills/` → `flow-skills/`, retires the old dir with a backup). The health check flags an empty/absent `flow-skills/` while Flow mirrors exist, with restore steps.

> **`.fusebase-flow-source/` and ESLint (deploy lint).** The upstream staging clone `.fusebase-flow-source/` contains CLI-owned CommonJS hooks; ESLint **flat config does not read `.gitignore`**, and the CLI's `eslint.config` only ignores `.claude/**` — so if your `fusebase deploy` runs lint, the staged clone fails it (`@typescript-eslint/no-require-imports`) even with zero app errors. The clone is **transient** — either delete it after an upgrade (`rm -rf .fusebase-flow-source`; it's re-created on the next upgrade), or add `".fusebase-flow-source/**"` to your `eslint.config` `ignores` (next to `".claude/**"`). One-shot helper: `bash hooks/local/eslint-ignore-flow-paths.sh`.

`.claude/skills/`, `.claude/agents/`, `.claude/hooks/`, `.claude/settings.json`, and `AGENTS.md` are touched by `fusebase update` (without `--skip-skills`). Use either:

**Option A (recommended for routine updates):**

```bash
fusebase update --skip-skills
```

Skips the Fusebase Flow regeneration entirely. Doesn't get CLI-side skill / hook updates but keeps Fusebase Flow overlay intact.

**Option B (when you want full CLI updates):**

```bash
fusebase update                              # let CLI regenerate; Fusebase Flow overlay is destroyed
bash hooks/local/post-fusebase-update.sh     # idempotent recovery: re-mirrors skills+agents,
                                             # re-appends AGENTS.md/CLAUDE.md overlays,
                                             # re-merges settings.json hook chain,
                                             # re-applies Windows shell:true patch
```

The recovery script is self-detecting: it skips parts that don't need restoration (idempotent; safe to run multiple times).

**Or use the in-chat health check:** type `/fusebase-health` (or ask "is Fusebase Flow healthy?") — the skill diagnoses any drift and offers to run recovery on your confirmation.

<!-- FLOW:PRESERVE:BEGIN (operator-owned — overlay refresh carries this region forward verbatim; edit freely) -->
### Project-specific values

> Fill these by running **`/onboard`** (the canonical step — the `project-onboarding` skill populates them), or just edit the table directly. Either way your values are preserved across overlay refreshes (they live inside the `FLOW:PRESERVE` markers).

| Field | Value | Where the data is enforced |
|---|---|---|
| Project name | (run `/onboard` or edit) | (informational) |
| Stack | (run `/onboard` or edit) | (informational) |
| Workflow mode | `direct_to_main` | `policies/approval-policy.yml: workflow_mode` |
| Worker-undisturbed paths | `none` (extend if needed) | `policies/protected-paths.yml: worker_undisturbed` |
| Decision letter prefix | `A` | `templates/decisions.md` |
| T-counter | `0` | `templates/tasks.md` |

**Where Fusebase Flow and project-specific rules conflict, project-specific rules win.**
<!-- FLOW:PRESERVE:END -->

<!-- CUSTOM:SKILL:END -->