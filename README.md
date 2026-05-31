# FuseBase Flow

**The framework client-facing teams use to build internal and client-facing apps with AI.**

[![Version](https://img.shields.io/badge/version-3.2.0-blue.svg)](VERSION)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![CI](https://github.com/fusebase-dev/fusebase-flow/actions/workflows/fusebase-flow-verify.yml/badge.svg)](https://github.com/fusebase-dev/fusebase-flow/actions/workflows/fusebase-flow-verify.yml)
[![Use this template](https://img.shields.io/badge/GitHub-Use_this_template-brightgreen.svg?logo=github)](https://github.com/fusebase-dev/fusebase-flow/generate)

A development framework for client-facing businesses and teams, FuseBase Flow covers what breaks during real app development for internal and external collaboration — drift, context rot, scope creep, unreliable hand-offs — so two AI agents (a Product Owner and an AI Developer) can ship reliably.

It shapes your existing AI agent through **repo files** — no SaaS, no daemon, no proprietary runtime. Works in Claude Code, Codex, Cursor, Copilot, and Gemini.

## Built by FuseBase

FuseBase Flow is built and maintained by **FuseBase** (Nimbus Web Inc.) — a US company building client-facing collaboration software since **2014 (11 years)**. It's the framework FuseBase itself uses to ship apps, backed by a proven product track record:

- 🏆 **Product Hunt** — Product of the Day, Week, Month & Year (team collaboration)
- 🥇 **3× top-selling deal on AppSumo**
- ⭐ **~600 five-star reviews**

FuseBase Flow isn't an experiment — it's the workflow a real product company runs on.

## Who it's for

- **Agencies, consultancies, and client-facing teams** building apps for both their own internal operations and their clients.
- Teams who want to **productize their expertise** — turn the knowledge only you have into apps and systems you deliver, internally and to clients.
- Anyone who's hit the wall where one AI chat gets clogged, the model drifts, and a half-built app stops being trustworthy.

## Why a framework (and why two agents)

Building real apps with an AI agent breaks in predictable ways: one chat fills up and the model **drifts**; context rot makes later edits contradict earlier ones; a single mega-prompt smuggles in **scope creep**; and work handed between sessions loses its thread. FuseBase Flow closes those gaps with a disciplined loop run by **two agents** — a consultant and a builder, not a sprawling fleet. The simplicity is the point.

| Agent | Role |
|---|---|
| **Product Owner** | Your single point of contact. Consults on *what* to build and *how to build it right*, then breaks the work into phases and slices. Owns Specify -> Clarify -> Plan -> Decisions -> Tasks -> Review -> deploy hand-off. |
| **AI Developer** | The builder. Executes each slice one task = one commit, stops at a verification gate, and deploys only on approval -- in a separate session so the main context stays clean. |

```mermaid
flowchart LR
    Client([Client / team request]) --> S[📋 Specify]
    S --> C[❓ Clarify] --> P[🗺️ Plan] --> D[🔒 Decisions] --> T[✅ Tasks / slices]
    T --> V[🚦 Verify gate]
    V -->|handoff| I[⚙️ Implement<br/>one task = one commit]
    I --> R[🔍 Review] --> H[📦 Deploy handoff] --> X[🚀 Deploy] --> Done([Shipped])
    style Client fill:#fef9c3,stroke:#a16207
    style S fill:#dbeafe,stroke:#1d4ed8
    style V fill:#fff3e0,stroke:#f57c00
    style I fill:#dcfce7,stroke:#15803d
    style X fill:#dcfce7,stroke:#15803d
```

*Product Owner (blue) is the single point of contact -- consults, advises, and breaks work into phases and slices. AI Developer (green) builds and deploys. The full eight-phase procedure lives at [`workflows/eight-phase-flow.md`](workflows/eight-phase-flow.md).*

## How it stays reliable

- **No drift** -- the Product Owner (advise) and AI Developer (build) split the work so neither chat clogs and the model stays on target.
- **Phases -> slices** -- complex work is decomposed Jira-style into reviewable slices, never one risky mega-prompt.
- **Durable hand-offs** -- work survives session resets with full context, so a fresh chat picks up without fatigue.
- **Many small apps, not one monster** -- a product is composed of focused apps, so one failure can't sink the whole system.

## What it costs

FuseBase Flow runs natively in your IDE through the FuseBase CLI. There are **no per-token platform fees** -- you pay only for the AI subscription you already have (Claude Code, Codex, Cursor, Gemini, or Copilot).

## Coming from ad-hoc agent prompting?

If today you open Claude Code / Codex / Cursor and just say *"build me X"*, you already have everything FuseBase Flow needs -- it doesn't replace your agent, it **gives it a process**:

| Without FuseBase Flow | With FuseBase Flow |
|---|---|
| One giant prompt -> one giant diff you have to trust | Spec -> decisions -> tasks -> one-commit-per-task you can review |
| "It worked on my machine" | Verification gate + outcome-based smoke before deploy |
| Scope creep mid-session | Locked decisions; supersede discipline (FR-18) |
| Re-explaining context every session | Durable repo artifacts (`docs/specs/`, `docs/handoff/`) |
| Risky deploys | Deploy gated on an explicit approval artifact |

Nothing to uninstall from your agent -- drop the files in, attest once, keep working.

## Contents

- [Built by FuseBase](#built-by-fusebase)
- [Who it's for](#who-its-for)
- [Why a framework (and why two agents)](#why-a-framework-and-why-two-agents)
- [How it stays reliable](#how-it-stays-reliable)
- [What it costs](#what-it-costs)
- [Coming from ad-hoc agent prompting?](#coming-from-ad-hoc-agent-prompting)
- [What's in the box](#whats-in-the-box)
- [Quick start (GitHub template)](#quick-start-github-template)
- [Filing your first ticket](#filing-your-first-ticket)
- [Supported agents & IDEs](#supported-agents--ides)
- [Using sub-agents](#using-sub-agents)
- [Skill catalog](#skill-catalog)
- [Installing into an existing project](#installing-into-an-existing-project)
- [Health check & recovery](#health-check--recovery)
- [How enforcement works](#how-enforcement-works)
- [Default workflow modes](#default-workflow-modes)
- [Validating an installation](#validating-an-installation)
- [FAQ & troubleshooting](#faq--troubleshooting)
- [What's inside](#whats-inside)
- [Clean-room, license & publishing](#clean-room-license--publishing)

## What's in the box

FuseBase Flow has two layers. **Flow** is the lifecycle: specs, decisions, tasks, gates, reviews, deploy handoffs, and smoke discipline. The bundled **FuseBase Apps domain skills** are the build layer: app architecture, FuseBase CLI usage, dashboards, gate, secrets, routing, logs, and scaffold checks — so the agent can ship real apps, not just plan them.

See [`docs/fusebase-cli-edition.md`](docs/fusebase-cli-edition.md) for the layer boundary map and overlap table.

| Is | Isn't |
|---|---|
| Repo-local discipline (rules, skills, workflows, hooks, policies, templates) | A coding agent or chat product |
| A GitHub template you copy into projects | A SaaS or external service |
| Tool-portable across multiple AI coding surfaces | Tied to one vendor |
| Stdlib-first Python + bash + git | Requires heavy frameworks (FastAPI, daemons, servers) |
| Local-only hooks | Network webhooks |

## Quick start (GitHub template)

1. On GitHub, click **"Use this template"** → "Create a new repository".
2. Clone your new repo locally.
3. Open the repo in your IDE / agent of choice. The agent reads `AGENTS.md` first; from there it follows `FLOW_RULES.md`.
4. (Optional) Run the convenience installer:

   ```bash
   bash install.sh
   ```

   This installs git fallback hooks, runs preflight, and offers to mirror canonical skills into the provider folders. It does NOT install heavy dependencies and does NOT require any external service.

5. Install the runtime dependency for hook handlers:

   ```bash
   pip install -r hooks/requirements.txt
   ```

   (Only PyYAML; ~100 KB.)

## Filing your first ticket

1. Tell the agent: *"Let's ship `<feature description>`."*
2. The agent invokes the `requirements-specification` skill, drafts `docs/specs/<slug>/spec.md`, and runs clarify questions.
3. After clarify resolves, the agent invokes `implementation-planning` to produce `decisions.md`, `tasks.md`, `verification-gate.md`, plus a saved handoff at `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md`.
4. Open a fresh agent session, paste the handoff, and the AI Developer executes the task chain — stopping at the verification gate.
5. Paste the gate report back to the originating session. Run `code-review` and `security-permissions-review`.
6. If clean, the operator says *"prepare deploy"* — the `release-deploy-reporting` skill drafts the deploy handoff, you paste it into the AI Developer session, deploy runs, probes and outcome-based smoke verify.

The full eight-phase lifecycle lives at [`workflows/eight-phase-flow.md`](workflows/eight-phase-flow.md).

## Supported agents & IDEs

FuseBase Flow provides compatibility files for:

- **Anthropic Claude Code** — `CLAUDE.md`, `.claude/skills/`, `.claude/settings.json.example`
- **OpenAI / ChatGPT Codex** — `AGENTS.md`, `.agents/skills/`, `.codex/config.toml.example`, `.codex/hooks.json.example`
- **Cursor** — `.cursor/rules/*.mdc`, `AGENTS.md`
- **GitHub Copilot / VS Code** — `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `AGENTS.md`
- **Gemini / Antigravity-style IDE agents** — `GEMINI.md`, `AGENTS.md`
- **Generic local repo workflows** — `AGENTS.md` + root-level framework dirs (`skills/`, `workflows/`, `policies/`, `templates/`, `hooks/`) + git fallback hooks + local scripts

`.claude/skills/` and `.agents/skills/` include both canonical Flow skill mirrors and FuseBase Apps domain skills. The audit mirror manifest tracks the Flow mirrors only.

The full surface support breakdown lives at [`docs/compatibility.md`](docs/compatibility.md).

## Using sub-agents

Two role-shaped sub-agents cover the full eight-phase lifecycle. They are **opt-in** — the framework remains fully usable via the skill-and-workflow pattern alone — but they make role boundaries explicit and harder to drift across.

| Sub-agent | Owns | Skills it invokes |
|---|---|---|
| **Product Owner** | Specify, Clarify, Plan, design discovery/ideation, Decisions, Tasks, draft-verification-gate, smoke contract definition, clean-room skill classification, post-implement code-review and security-permissions-review, deploy-handoff drafting, spec DRAFT→DONE flip, **plus Architect responsibilities inline on escalation** (>10 files / cross-cutting refactor / platform blocker / blocked migration) | `requirements-specification`, `design-discovery-ideation`, `implementation-planning`, `smoke-testing`, `task-delegation`, `skill-authoring`, `code-review`, `security-permissions-review`, `release-deploy-reporting` |
| **AI Developer** | Run gate, Implement T-chain (one task = one commit; stops at gate), implement approved framework skill changes, Run deploy command (gated on approval artifact, captures hash, runs probes and smoke evidence) | `validation-and-qa`, `smoke-testing`, `task-delegation`, `skill-authoring`, `repo-onboarding-context-map` |

Both sub-agents always load the mandatory `communication` and `role-discipline` skills.

FuseBase Flow also ships FuseBase Apps app-agents (`app-architect`, `app-create-checker`) as domain assets. They support FuseBase Apps architecture and scaffold validation; they do not replace the Flow Product Owner or AI Developer role agents.

### Invoking from Claude Code

```
> Use the product-owner sub-agent. Let's ship pagination.
```

```
> Use the ai-developer sub-agent. Run docs/handoff/2026-05-09-pagination-implement.md.
```

Claude Code auto-discovers `.claude/agents/<name>.md`.

### Invoking from Codex

Codex doesn't auto-discover sub-agent files. Reference them in the first message of a fresh session:

```
> Read .codex/agents/product-owner.md and operate as Product Owner per its instructions.
> Let's ship pagination.
```

```
> Read .codex/agents/ai-developer.md and operate as AI Developer per its instructions.
> Run docs/handoff/2026-05-09-pagination-implement.md.
```

### Updating sub-agent definitions

Edit the canonical at `agents/<name>/AGENT.md`, then regenerate provider mirrors:

```bash
bash hooks/local/mirror-agents.sh
```

Preflight will warn on drift if the mirrors and canonical fall out of sync. Full release notes for the v2.1.0 sub-agents launch live at [`docs/release-notes/v2.1.0.md`](docs/release-notes/v2.1.0.md).

## Skill catalog

Skills are on-demand expertise the agent loads when a task matches the skill's description. **14 canonical Flow skills** govern the lifecycle; **19 FuseBase CLI provider skills** supply the app-building domain knowledge. You never invoke them by hand — describe the work and the matcher loads the right one.

### Flow lifecycle skills (14)

| Phase | Skill | What it does |
|---|---|---|
| _always_ | `communication` ★ | Mode A chat output + Mode B artifact writing |
| _always_ | `role-discipline` ★ | Enforces role boundaries + FR refusal phrasing |
| Specify / Clarify | `requirements-specification` | Drafts the spec + clarify questions + acceptance criteria |
| Clarify / Plan | `design-discovery-ideation` | Divergent options & UI/product directions before lock |
| Plan / Decisions / Tasks | `implementation-planning` | Produces decisions, tasks, verification-gate, handoff |
| Tasks / Implement | `task-delegation` | Safe parallel/subagent slicing of independent tasks |
| Verify / Implement | `validation-and-qa` | Gate report: lint, typecheck, tests, repro-before-fix |
| Implement / Deploy | `smoke-testing` | Proves the operator-visible outcome on the deployed surface |
| Review | `code-review` | Diff vs spec/decisions, maintainability, scope, rollback |
| Review | `security-permissions-review` | Auth, secrets, deploy-config, customer-visible changes |
| Deploy | `release-deploy-reporting` | Deploy handoff, hash + probes + smoke, DRAFT→DONE flip |
| Onboarding | `repo-onboarding-context-map` | Durable context map for a new/unfamiliar repo |
| Meta | `skill-authoring` | Create/update reusable skills (clean-room classified) |
| Health | `fusebase-flow-health-check` | Read-only overlay drift diagnosis + offered recovery |

★ = mandatory, loaded every session.

### FuseBase CLI provider skills (19)

<details>
<summary><strong>App build · runtime · data · ops domain skills</strong></summary>

| Group | Skills |
|---|---|
| **Build & structure** | `fusebase-cli`, `app-dev-practices`, `app-routing`, `app-ui-design` |
| **Backend & infra** | `app-backend`, `app-secrets`, `app-sidecar`, `managed-integrations` |
| **Data & dashboards** | `fusebase-dashboards`, `fusebase-gate`, `file-upload`, `fusebase-portal-specific-apps` |
| **Auth & errors** | `handling-authentication-errors` |
| **Debug & ops** | `dev-debug-logs`, `remote-logs`, `api-exploration`, `mcp-gate-debug` |
| **Docs & git** | `app-business-docs`, `git-workflow` |

</details>

### Which one do I use?

| Situation | Reach for |
|---|---|
| Starting a new ticket | `requirements-specification` (or the **Product Owner** sub-agent) |
| Plan is set, time to build | the **AI Developer** sub-agent + `validation-and-qa` |
| "Is this diff safe?" | `code-review` **and** `security-permissions-review` |
| "Did the deploy actually work?" | `smoke-testing` |
| "Did `fusebase update` break Flow?" | `fusebase-flow-health-check` (or `/fusebase-health`) |

## Installing into an existing project

Do not blindly copy this repository over an existing project.

If the target repo already contains `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.claude/settings.json`, `.mcp.json`, `.cursor/mcp.json`, `.agents/skills/`, `.claude/skills/`, `fusebase.json`, or `skills-lock.json`, use the FuseBase CLI / MCP-safe install path:

- append to `AGENTS.md`
- append to `CLAUDE.md`
- append to `.gitignore`
- add skills into existing skill folders only when no name collision exists
- never replace MCP configuration
- never replace active Claude settings or hooks
- review `.claude/settings.json.example` before merging lifecycle hooks

See [`docs/install-fusebase-cli-project.md`](docs/install-fusebase-cli-project.md). The general existing-repo guide lives at [`docs/install-existing-project.md`](docs/install-existing-project.md).

<details>
<summary><strong>Copy-into-existing-repo commands</strong></summary>

```bash
# From the existing repo's root, copy the framework + the always-on baseline:
SRC=/path/to/fusebase-flow

cp -R $SRC/skills ./
cp -R $SRC/workflows ./
cp -R $SRC/hooks ./
cp -R $SRC/policies ./
cp -R $SRC/templates ./
cp -R $SRC/audit ./
cp -R $SRC/state ./
cp -R $SRC/docs ./
cp $SRC/AGENTS.md ./
cp $SRC/CLAUDE.md ./
cp $SRC/GEMINI.md ./
cp $SRC/FLOW_RULES.md ./
cp $SRC/VERSION ./
cp $SRC/install.sh ./
cp $SRC/.gitattributes ./
cp $SRC/.gitignore ./
cp $SRC/.python-version ./
cp -R $SRC/.github ./

# Copy only the provider/IDE compatibility surfaces you use:
cp -R $SRC/.claude ./       # Anthropic Claude Code
cp -R $SRC/.agents ./       # OpenAI / ChatGPT Codex
cp -R $SRC/.codex ./        # OpenAI / ChatGPT Codex
cp -R $SRC/.cursor ./       # Cursor

# Then run the installer:
bash install.sh
```

</details>

## Health check & recovery

When FuseBase Flow is installed on top of the FuseBase CLI, the two share a repo. Flow's recovery model is **CLI-first, Flow-second**: **Flow never overwrites FuseBase CLI-owned files or instructions.** The health engine classifies every drift by ownership layer and recovers only what Flow owns.

| Layer | Examples | Who restores it |
|---|---|---|
| **CLI-owned** | CLI provider skills, `.claude/hooks/**`, MCP config, `fusebase.json`, `skills-lock.json`, existing CLI instructions | FuseBase CLI refresh/update — Flow **diagnoses only**, never writes |
| **Flow-owned** | Flow skills/agents mirrors, `AGENTS.md`/`CLAUDE.md` overlay blocks, health-check skill + `/fusebase-health` command, Flow-owned hook assets | Flow recovery script |
| **Shared** | `.claude/settings.json` | **Merged**, never replaced |

An ownership manifest backs this split, and a read-only conflict reporter surfaces the per-layer verdict.

| Need | Command |
|---|---|
| Check health + layer verdict (read-only) | `bash hooks/local/fusebase-flow-health-check.sh` <br> or `/fusebase-health` (Claude Code) <br> or *"is FuseBase Flow healthy?"* (any agent) |
| Detailed CLI/Flow ownership & conflict report + drift advisory (read-only) | `bash hooks/local/check-cli-flow-conflicts.sh` |
| Re-stamp CLI vendor provenance (after a `fusebase update` or an intentional CLI asset change) | `bash hooks/local/stamp-cli-provenance.sh` |
| Recover Flow-owned + shared surfaces | `bash hooks/local/post-fusebase-update.sh` <br> or reply `yes` when the skill offers recovery in chat |
| Restore CLI-owned drift | Run the current **FuseBase CLI refresh/update first**, then `post-fusebase-update.sh` for the Flow layer |
| Upgrade engine + recovery to latest upstream | `bash hooks/local/upgrade-engine.sh` (refresh `.fusebase-flow-source/` first) |
| Avoid drift on routine updates | `fusebase update --skip-skills` (preserves FuseBase Flow overlay) |

<details>
<summary><strong>What the health check verifies, verdicts, deferrals & recovery flow</strong></summary>

### What the health check verifies

12 inventory checks per run:

- VERSION file
- AGENTS.md overlay block (`## FuseBase Flow — workflow lifecycle overlay`, appended inside the CLI-preserved custom wrapper)
- CLAUDE.md overlay block (`## FuseBase Flow — additional rules (overlay)`)
- `.claude/settings.json` lifecycle events (auto-discovered count)
- `.claude/skills/` Flow mirror count (auto-discovered set; CLI provider skills may also be present)
- `.claude/agents/` Flow agent mirror count (auto-discovered set; CLI app agents may also be present)
- Health-check skill self-presence
- Recovery script presence + executable
- Overlay templates folder presence
- `preflight.sh` clean
- `hooks/tests/run-tests.sh` passing
- Windows `shell:true` patch on `.claude/hooks/run-typecheck-apps.js` (CVE-2024-27980 mitigation)
- CLI vendor provenance manifest (`audit/cli-vendor-manifest.json`) present + parseable (advisory)

Plus active approval artifacts in `state/approvals/` are surfaced informationally so artifact-attributable test failures don't trigger false BROKEN verdicts.

### CLI vendor provenance & drift advisory (v3.2.0+)

FuseBase Flow vendors a frozen copy of FuseBase CLI-owned assets (19 provider skills + `references/`, 2 app-agents, 4 quality hooks). `bash hooks/local/stamp-cli-provenance.sh` records a per-file sha256 of each in `audit/cli-vendor-manifest.json` (a committed document of record), with `source_cli_version: "unknown"` — the bundling tool cannot know which live CLI bundle a copy came from, so freshness is advisory only.

`check-cli-flow-conflicts.sh` then hashes each **present** CLI asset against that manifest and surfaces two **advisory** findings (informational only — they never change the verdict or exit code):

| Advisory | Meaning | What to do |
|---|---|---|
| `CLI_SNAPSHOT_STALE` | a present CLI asset's sha256 differs from the bundled snapshot (newer or locally modified) — distinct from `MISSING`, which still escalates to `CLI_LAYER_DRIFT` | expected after `fusebase update`; if intentional, re-stamp with `stamp-cli-provenance.sh` |
| `CLI_CUSTOM_AT_RISK` | a CLI-owned skill carries a `CUSTOM:SKILL` block a future CLI refresh may overwrite | back up the block before the next `fusebase update` |

This guards the **two-writer hazard** — `fusebase update` and the Flow snapshot both write the same provider paths. The documented install copy is non-clobbering for CLI-owned paths, and Flow recovery never writes them. See [docs/fusebase-cli-edition.md](docs/fusebase-cli-edition.md) § "Two-writer hazard".

The Claude Code Stop hooks shipped in `.claude/settings.json.example` are the cross-platform **node** hooks (`run-typecheck-apps.js`, `quality-check-apps.js`); the jq/bash duplicates (`run-lint-on-stop.sh`, `run-typecheck-on-stop.sh`) are deprecated and unwired (they fail out-of-the-box on Windows).

### Verdicts (ownership-layer model)

| Verdict | Exit | Meaning | Recovery posture |
|---|:---:|---|---|
| `HEALTHY` | 0 | CLI-owned, Flow-owned, and shared-merge surfaces all intact | No action |
| `CLI_LAYER_DRIFT` | 1 | CLI-owned assets missing or structurally damaged | **Run FuseBase CLI refresh/update first**, then Flow recovery — Flow does not write CLI-owned files |
| `FLOW_LAYER_DRIFT` | 1 | Flow-owned mirrors or overlay files missing/drifted | Flow recovery offered |
| `SHARED_MERGE_DRIFT` | 1 | Shared files missing Flow overlay/merge additions | Flow recovery offered (merge, not replace) |
| `EXCEPTION_IN_EFFECT` | 3 | Drift covered by active approval/deferral artifacts in `state/approvals/` | Surface the artifact; no automatic recovery |
| `BROKEN` | 2 | Preflight, hook tests, manifest parsing, or another critical check failed | Inspect the broken item first; no recovery |

Recovery (`post-fusebase-update.sh`) restores **only** Flow-owned assets and shared Flow additions — Flow skills/agents mirrors, `AGENTS.md`/`CLAUDE.md` overlay blocks, the `fusebase-flow-health-check` skill, and `.claude/commands/fusebase-health.md`, plus a merge into `.claude/settings.json`. It never touches `.claude/hooks/**`, CLI provider skills, MCP config, `fusebase.json`, `skills-lock.json`, or active `.codex/config.toml`.

### Deferral artifacts (v2.4.0+)

When an install brief or operator deliberately omits parts of the canonical FuseBase Flow setup (e.g. lifecycle hooks not wired, Windows patch not applied per protected-paths discipline), file a **deferral artifact** at `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json` listing the check_ids being deferred. Engine reclassifies matching drift items from `LOCAL_DRIFT` → `LOCAL_DEFERRED` (⊘ symbol in the report) and verdict drops to `EXCEPTION_IN_EFFECT` (exit 3).

See [docs/health-check-deferrals.md](docs/health-check-deferrals.md) for the artifact schema, the canonical check_id taxonomy, examples, and operator workflow for adding/removing deferrals.

### Recovery flow (the diagnose-then-offer pattern)

The skill is read-only during diagnosis. When drift is detected and recoverable, the skill **offers** recovery in chat:

```
Run recovery now? It will:
  • Restore AGENTS.md overlay block in the CLI-preserved custom wrapper (if missing)
  • Merge .claude/settings.json lifecycle events (if reduced)
  • Re-apply Windows shell:true patch (if missing)
  • Re-mirror FuseBase Flow skills + sub-agents (no-op if already present)

Reply `yes` / `run it` / `fix it` / `proceed` to execute.
Reply anything else to halt and decide later.
```

On affirmative reply → recovery executes + re-check + report new verdict. On any non-affirmative reply (silence, `no`, a question) → halt. Operator authority preserved (PO.5 from `role-discipline` skill); friction reduced — no terminal context-switch needed for most cases.

The recovery script is **idempotent** — safe to run multiple times. Only re-applies pieces that are actually missing.

### Auto-discovery for upstream upgrades

The engine and the merger auto-discover the canonical sets of skills, agents, lifecycle events, and handler commands from the upstream `.fusebase-flow-source/` clone at runtime. This means:

- **Patch / minor upstream releases** (new skill, new agent, renamed handler, new matcher) → **zero maintenance** to the health check + recovery system.
- **Major upstream releases** (heading marker rename, fundamental restructuring) → manual edits to heading-marker references in 4 files. Documented in the upgrade procedure section of the canonical skill.

### Files involved

```
skills/fusebase-flow-health-check/SKILL.md          ← canonical skill (description-matched)
.claude/skills/fusebase-flow-health-check/SKILL.md  ← Claude Code mirror
.agents/skills/fusebase-flow-health-check/SKILL.md  ← Codex mirror
.claude/commands/fusebase-health.md                 ← /fusebase-health slash command
hooks/local/fusebase-flow-health-check.sh           ← engine (read-only diagnostic)
hooks/local/post-fusebase-update.sh                 ← recovery script (10 idempotent steps)
hooks/local/fusebase-flow-overlays/                 ← overlay templates + canonical skill + slash command source
  ├── agents-md-overlay.md                          ← custom-block-wrapped block to append to AGENTS.md
  ├── claude-md-overlay.md                          ← block to append to CLAUDE.md
  ├── settings-json-merge.py                        ← Python merger (no jq)
  ├── skills/fusebase-flow-health-check/SKILL.md    ← skill template (recovery copies into mirrors)
  └── commands/fusebase-health.md                   ← slash command template
```

</details>

## How enforcement works

| Layer | What it does | Where |
|---|---|---|
| **Always-on rules** | 19 baseline rules every session attests to | `FLOW_RULES.md` |
| **Workflows** | Step-by-step procedures (eight-phase, greenlight-implement, greenlight-deploy, etc.) | `workflows/` |
| **Skills** | On-demand expertise loaded when triggered by description match | `skills/` (canonical) + provider mirrors |
| **Sub-agents** | Role-shaped specialists (Product Owner, AI Developer) with tight tool surfaces and self-attestation | `agents/` (canonical) + `.claude/agents/`, `.codex/agents/` mirrors |
| **Policies** | Machine-readable rule data (deny lists, secret patterns, approval rules) | `policies/` |
| **Hooks** | Deterministic enforcement at lifecycle events (Python; stdin → stdout) | `hooks/handlers/` |
| **Git fallback** | Always-on safety net for any IDE without native hooks | `hooks/git/{pre-commit,commit-msg}` |
| **Local scripts** | Operator-run helpers (preflight, install-git-hooks, mirror-skills, approve-local) | `hooks/local/` |

Hooks read a unified JSON event from stdin (schema at `hooks/flow_hook_event.schema.json`) and emit a JSON decision. They are **local guardrails**, not a complete security boundary; combine with git hooks and operator vigilance.

## Default workflow modes

- **Solo / local default:** direct-to-main with pre-task git checkpoint, one-task-one-commit, lint+typecheck per commit, and verification gate before deploy.
- **Team / shared mode:** feature branches + PR review. Switch via `policies/approval-policy.yml: workflow_mode: branch_pr` (or in a local override at `approval-policy.local.yml`).

The flow rules are identical in both modes; only the git surface changes.

## Validating an installation

```bash
bash hooks/local/preflight.sh    # structure + YAML + frontmatter + mirror drift + action-name consistency
bash hooks/tests/run-tests.sh    # 11 deterministic hook test fixtures
```

Both must pass cleanly:

```
[preflight] preflight finished — errors: 0, warnings: 0
[run-tests] 11/11 PASS
```

CI runs both on every push / PR via `.github/workflows/fusebase-flow-verify.yml`.

## FAQ & troubleshooting

<details>
<summary><strong>Does Flow replace my coding agent?</strong></summary>

No. Flow is repo-local files (rules, skills, workflows, hooks). Your existing agent (Claude Code, Codex, Cursor, Copilot, Gemini) reads them and follows the process. There is no separate runtime, daemon, or SaaS.
</details>

<details>
<summary><strong>Do I have to use the sub-agents?</strong></summary>

No. The Product Owner / AI Developer sub-agents are **opt-in**. The framework is fully usable through the skill-and-workflow pattern alone. The sub-agents just make role boundaries explicit and harder to drift across.
</details>

<details>
<summary><strong>Do I need the Python hooks?</strong></summary>

They're optional guardrails. Nothing runs until you copy `.claude/settings.json.example` → `.claude/settings.json`. The git fallback hooks (`hooks/git/`) provide a safety net even with Claude Code hooks off. The only dependency is PyYAML (~100 KB).
</details>

<details>
<summary><strong>`fusebase update` changed my files — is Flow broken?</strong></summary>

Probably not. Run the read-only health check — it reports a **layer verdict** so you know who restores what:

```bash
bash hooks/local/fusebase-flow-health-check.sh    # or /fusebase-health in Claude Code
```

- **`FLOW_LAYER_DRIFT` / `SHARED_MERGE_DRIFT`** → Flow recovers it idempotently: `bash hooks/local/post-fusebase-update.sh`
- **`CLI_LAYER_DRIFT`** → CLI-owned files. Run the **FuseBase CLI refresh/update first**, then the Flow recovery. Flow never overwrites CLI-owned files.

Avoid drift next time with `fusebase update --skip-skills`. See [Health check & recovery](#health-check--recovery).
</details>

<details>
<summary><strong>Preflight or tests fail after I edited a skill</strong></summary>

Skill files are mirrored across provider folders and tracked by a SHA-256 manifest. Edit the **canonical** under `skills/` (or `agents/`), then re-mirror:

```bash
bash hooks/local/mirror-skills.sh
bash hooks/local/mirror-agents.sh
bash hooks/local/preflight.sh        # should report errors: 0, warnings: 0
```
</details>

<details>
<summary><strong>Solo vs team workflow?</strong></summary>

Default is **solo / direct-to-main** with per-task commits and a verification gate. Switch to **feature branches + PR** by setting `workflow_mode: branch_pr` in `policies/approval-policy.yml` (or `approval-policy.local.yml`). The flow rules are identical in both modes.
</details>

<details>
<summary><strong>How do I uninstall / back out?</strong></summary>

Flow is just files. Remove the framework dirs (`skills/ workflows/ hooks/ policies/ templates/ audit/ state/`), the adapter files (`AGENTS.md CLAUDE.md GEMINI.md FLOW_RULES.md VERSION`), and the provider surfaces you added (`.claude/ .agents/ .codex/ .cursor/ .github/`). To disable just the hooks, delete `.claude/settings.json`; if you installed the git fallback hooks, delete the copied `pre-commit` and `commit-msg` files from `.git/hooks/`. Your agent and code are untouched.
</details>

## What's inside

<details>
<summary><strong>Full repository tree</strong></summary>

```
fusebase-flow/
├── README.md                       ← (this file)
├── PUBLISHING.md                   ← history-hygiene before public publishing
├── LICENSE                         ← MIT
├── install.sh                      ← optional convenience installer
├── AGENTS.md                       ← portable always-on baseline
├── CLAUDE.md                       ← Anthropic Claude Code adapter
├── GEMINI.md                       ← Gemini-style IDE adapter
├── FLOW_RULES.md                   ← FR-01..FR-19 always-on rules
├── VERSION                         ← 3.2.0
├── .gitattributes                  ← LF line endings for shell/python/yaml/md
├── .python-version                 ← 3.12 (recommended)
├── skills/                         ← 14 canonical skills (2 mandatory + 12 on-demand, incl. design-discovery-ideation, smoke-testing, task-delegation, skill-authoring + fusebase-flow-health-check)
├── agents/                         ← 2 canonical sub-agents (product-owner, ai-developer)
├── workflows/                      ← 12 procedures
├── policies/                       ← 6 YAML policies
├── templates/                      ← 13 substrates
├── hooks/
│   ├── README.md
│   ├── flow_hook_event.schema.json
│   ├── handlers/                   ← 8 Python lifecycle handlers
│   ├── shared/                     ← 6 shared utilities
│   ├── git/                        ← pre-commit + commit-msg
│   ├── local/                      ← preflight / verify-gate / approve-local / mirror-skills / mirror-agents / po-investigate
│   │                                  / install-git-hooks / fusebase-flow-health-check / post-fusebase-update / upgrade-engine
│   ├── local/fusebase-flow-overlays/  ← AGENTS.md + CLAUDE.md overlay templates,
│   │                                     settings-json-merge.py, health-check skill + slash command templates
│   ├── tests/                      ← run-tests.sh + 14 fixtures
│   └── requirements.txt            ← pyyaml (only non-stdlib dep)
├── audit/
│   ├── README.md                   ← what does (and does not) live here
│   ├── skill-mirror-manifest.txt   ← sha256 manifest used by preflight + CI
│   └── agent-mirror-manifest.txt   ← sha256 manifest for sub-agent mirrors
├── state/                          ← runtime state (gitignored contents)
├── docs/                           ← public reference docs + per-project artifacts
├── .agents/skills/                 ← Codex skill surface (14 Flow mirrors + 19 CLI provider skills)
├── .claude/skills/                 ← Claude Code skill surface (14 Flow mirrors + 19 CLI provider skills)
├── .claude/agents/                 ← Claude Code agent surface (2 Flow role agents + 2 CLI app agents)
├── .claude/commands/               ← Anthropic Claude Code slash commands (incl. /fusebase-health)
├── .claude/settings.json.example   ← Claude Code hook wiring
├── .codex/agents/                  ← Codex agent surface (2 Flow role agents + 2 CLI app agents)
├── .codex/{config.toml,hooks.json}.example ← Codex hook wiring + project trust note
├── .cursor/rules/                  ← Cursor rules (always + scoped)
└── .github/
    ├── copilot-instructions.md     ← repo-wide Copilot / VS Code instructions
    ├── instructions/               ← scoped Copilot / VS Code instructions
    └── workflows/fusebase-flow-verify.yml ← CI: preflight + tests + mirror drift + public-surface allowlist
```

</details>

## Clean-room, license & publishing

- **Clean-room** — Canonical Flow files are clean-room original. The bundled FuseBase Apps domain skills are provider-scoped assets; see [`docs/clean-room.md`](docs/clean-room.md) and [`docs/fusebase-cli-edition.md`](docs/fusebase-cli-edition.md).
- **License** — MIT. See [`LICENSE`](LICENSE).
- **Publishing** — Before making this repo public, follow the history-hygiene step in [`PUBLISHING.md`](PUBLISHING.md).

### Public reference docs

Public-facing reference material lives in [`docs/`](docs/):

- [`docs/compatibility.md`](docs/compatibility.md) — provider / IDE support detail
- [`docs/hook-coverage.md`](docs/hook-coverage.md) — hook × provider coverage
- [`docs/rail-mapping.md`](docs/rail-mapping.md) — FR-01..FR-19 → enforcement surfaces
- [`docs/clean-room.md`](docs/clean-room.md) — clean-room license attestation
- [`docs/source-map.md`](docs/source-map.md) — generic pattern attribution

### Audit folder

[`audit/`](audit/) is intentionally minimal in the public template:

- `README.md` — what does (and does not) live here
- `skill-mirror-manifest.txt` — SHA-256 manifest used by `preflight.sh` and CI to detect drift

Build-time phase reports, packaging reports, and per-run test output do **not** ship in the template. Generated runtime reports (install report, hook test report) are written to `state/audit/` (gitignored). CI runs upload that directory as the `fusebase-flow-audit` workflow artifact.
