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
| Flow lifecycle | specs, decisions, tasks, verification gates, reviews, deploy handoffs, smoke contracts | `FLOW_RULES.md`, `skills/`, `workflows/`, `templates/`, `policies/`, `hooks/` |
| CLI domain | Fusebase Apps implementation guidance, MCP/dashboard/gate usage, routing, secrets, logs, scaffold quality | `.claude/skills/<cli-skill>/`, `.agents/skills/<cli-skill>/`, `.claude/agents/`, `.codex/agents/`, `.claude/hooks/` |

Runtime, MCP, SDK, and app-domain rules from CLI skills win over generic Flow implementation guidance when they overlap. Flow still governs the lifecycle artifact, approval, and smoke discipline. See `docs/fusebase-cli-edition.md` for the full mapping.

## How to use this repo as an agent

1. **First action of every session:** load `FLOW_RULES.md`. Then load the active workflow if a ticket is in progress.
2. **Self-attest your role** (Product Owner, AI Developer, Architect, Deploy) — see `FLOW_RULES.md` role table.
3. **Append the state-announcement footer** to every output.
4. **Ask before you act** when the task is non-trivial (multi-file, deploy, schema, auth, secrets).
5. **One task = one commit** when in AI Developer role; commit messages cite a `T<number>`.
6. **Save handoffs to disk before chat output** — never hand work across sessions through chat alone.
7. **Ask questions in chat text, not popups** — options must be copyable, scrollable, forwardable, and open to follow-up.

## Where things live

| Need | Path |
|---|---|
| Always-on rules | `FLOW_RULES.md` |
| Workflows (procedures) | `workflows/` |
| Skills (on-demand expertise) | `skills/` (canonical) — mirrored to `.claude/skills/` and `.agents/skills/` |
| Fusebase CLI edition bridge | `docs/fusebase-cli-edition.md` |
| CLI provider assets | `.claude/skills/`, `.agents/skills/`, `.claude/agents/`, `.codex/agents/`, `.claude/hooks/` |
| Policies (YAML, machine-readable) | `policies/` |
| Hooks (deterministic enforcement) | `hooks/` |
| Templates (artifact substrates) | `templates/` |
| Audit and paper trail | `audit/` |
| Active tickets and specs | `docs/specs/<slug>/`, `docs/backlog/<slug>/` |
| Cross-session prompts | `docs/handoff/<YYYY-MM-DD>-<slug>-<stage>.md` |

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
- **Mode B (internal artifacts):** dense, tabular, front-loaded. Files in `docs/specs/`, `docs/decisions/`, `docs/handoff/`, `docs/problem-catalog/`, `docs/backlog/` are AI-consumed — no narrative padding, no human-onboarding preamble.

Visuals belong in chat only, never in Mode-B files.
Questions and choices also belong in chat text, never in popup / clickable menu tools.

## Destructive ops (never without explicit confirmation)

`rm -rf`, `git push --force`, `git reset --hard`, `git checkout -- .`, `git clean -fdx`, `git add -A`, `git add .`, `--no-verify`, deploy commands without a saved approval artifact. Full deny/require-approval list at `policies/command-policy.yml`. The `pre_tool_use` hook (where supported) and `pre-commit` git hook block these by default.

## Starting your first ticket

1. Tell the agent: "Let's ship `<feature description>`."
2. Agent invokes the `requirements-specification` skill → drafts `docs/specs/<slug>/spec.md`, runs clarify questions; if the operator asks for options, `design-discovery-ideation` produces the option brief before lock.
3. After clarify resolves: agent invokes `implementation-planning` skill → drafts `decisions.md`, `tasks.md`, `verification-gate.md`, and saves `docs/handoff/<date>-<slug>-implement.md`.
4. Open a fresh agent session, paste the implement handoff, agent executes task chain stopping at the gate.
5. Paste the gate report into the original session, agent invokes `code-review` and `security-permissions-review` skills.
6. If clean, agent invokes `release-deploy-reporting` skill → drafts `docs/handoff/<date>-<slug>-deploy.md` with smoke prompts governed by `smoke-testing` when applicable.

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

> Fill in or replace these fields when installing into a project. Each field is short — prose-heavy explanations belong in `docs/constitution.md`, machine-readable enforcement belongs in `policies/`.

| Field | Value | Where the data is enforced |
|---|---|---|
| **Project name** | `Fusebase Flow - Fusebase CLI edition` | (informational only) |
| **One-line description** | `Fusebase Flow lifecycle framework packaged with Fusebase Apps CLI domain skills and agents` | (informational only) |
| **Stack** | `Repo-local Flow framework + Fusebase Apps CLI provider assets` | (informational only) |
| **Workflow mode** | `direct_to_main` (default) or `branch_pr` | `policies/approval-policy.yml: workflow_mode` |
| **Worker-undisturbed paths** | `<list specific files; or "none">` | `policies/protected-paths.yml: worker_undisturbed` |
| **Mixed-fleet considerations** | `Generated apps may use original CLI assets and Flow overlay together` | per-ticket `decisions.md` references |
| **Migration constraints** | `Do not absorb CLI provider skills into root Flow canonical skills` | per-ticket `decisions.md` references |
| **Auth model** | `Edition template only; downstream apps follow Fusebase Apps token/MCP rules from CLI skills` | per-ticket security review + `policies/protected-paths.yml: env_and_secrets` |
| **Deploy command** | `N/A for template; downstream apps use fusebase deploy` | `workflows/greenlight-deploy.md` |
| **Decision letter prefix in use** | `<A, B, C, ...>` (increments per ticket) | `templates/decisions.md` |
| **T-counter** | `<0, 1, 2, ...>` (increments per task across all tickets) | `templates/tasks.md` |
| **CI workflow** | `.github/workflows/fusebase-flow-verify.yml` (default) | (existing) |

Narrative reasoning for these values — why they're set this way for THIS project — lives in `docs/constitution.md`.

## Quick links

- Full rules: `FLOW_RULES.md`
- Eight-phase flow: `workflows/eight-phase-flow.md`
- Project constitution (narrative): `docs/constitution.md`
- Fusebase CLI edition bridge: `docs/fusebase-cli-edition.md`
- Operator discipline: `docs/operator-discipline.md`
- Architecture overview: `docs/architecture-overview.md`
- Key tensions: `docs/tradeoffs.md`
- Skill catalog: `skills/`
- Audit package: `audit/`
- Compatibility matrix: `docs/compatibility.md`
- Safe install into Fusebase CLI / MCP repos: `docs/install-fusebase-cli-project.md`
