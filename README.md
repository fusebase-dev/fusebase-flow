# Fusebase Flow Local

**A GitHub template / repo-local workflow framework for AI coding agents and IDEs.**

Fusebase Flow Local installs durable rules, skills, workflows, hooks, policies, and templates into a project so your existing IDE / agent can follow a consistent multi-phase ticket lifecycle — from spec through deploy.

It works by shaping the agent's behavior through **repo files**, not by replacing the agent. There is no SaaS, no daemon, no proprietary runtime to install.

## What this is — and isn't

| Is | Isn't |
|---|---|
| Repo-local discipline (rules, skills, workflows, hooks, policies, templates) | A coding agent or chat product |
| A GitHub template you copy into projects | A SaaS or external service |
| Tool-portable across multiple AI coding surfaces | Tied to one vendor |
| Stdlib-first Python + bash + git | Requires heavy frameworks (FastAPI, daemons, servers) |
| Local-only hooks | Network webhooks |

## Supported public targets

Fusebase Flow Local provides compatibility files for:

- **Anthropic Claude Code** — `CLAUDE.md`, `.claude/skills/`, `.claude/settings.json.example`
- **OpenAI / ChatGPT Codex** — `AGENTS.md`, `.agents/skills/`, `.codex/config.toml.example`, `.codex/hooks.json.example`
- **Cursor** — `.cursor/rules/*.mdc`, `AGENTS.md`
- **GitHub Copilot / VS Code** — `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `AGENTS.md`
- **Gemini / Antigravity-style IDE agents** — `GEMINI.md`, `AGENTS.md`
- **Generic local repo workflows** — `AGENTS.md` + root-level framework dirs (`skills/`, `workflows/`, `policies/`, `templates/`, `hooks/`) + git fallback hooks + local scripts

The full surface support breakdown lives at [`docs/compatibility.md`](docs/compatibility.md).

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

## Installing into an existing Fusebase CLI / MCP project

Do not blindly copy this repository over an existing project.

If the target repo already contains `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.claude/settings.json`, `.mcp.json`, `.cursor/mcp.json`, `.agents/skills/`, `.claude/skills/`, `fusebase.json`, or `skills-lock.json`, use the Fusebase CLI / MCP-safe install path.

In that case:

- append to `AGENTS.md`
- append to `CLAUDE.md`
- append to `.gitignore`
- add skills into existing skill folders only when no name collision exists
- never replace MCP configuration
- never replace active Claude settings or hooks
- review `.claude/settings.json.example` before merging lifecycle hooks

See [`docs/install-fusebase-cli-project.md`](docs/install-fusebase-cli-project.md). The general existing-repo guide lives at [`docs/install-existing-project.md`](docs/install-existing-project.md).

## Quick start (copy into existing repo)

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

## Filing your first ticket

1. Tell the agent: *"Let's ship `<feature description>`."*
2. The agent invokes the `requirements-specification` skill, drafts `docs/specs/<slug>/spec.md`, and runs clarify questions.
3. After clarify resolves, the agent invokes `implementation-planning` to produce `decisions.md`, `tasks.md`, `verification-gate.md`, plus a saved handoff at `docs/handoff/<YYYY-MM-DD>-<slug>-implement.md`.
4. Open a fresh agent session, paste the handoff, and the AI Developer executes the task chain — stopping at the verification gate.
5. Paste the gate report back to the originating session. Run `code-review` and `security-permissions-review`.
6. If clean, the operator says *"prepare deploy"* — the `release-deploy-reporting` skill drafts the deploy handoff, you paste it into the AI Developer session, deploy runs, probes verify.

The full eight-phase lifecycle lives at [`workflows/eight-phase-flow.md`](workflows/eight-phase-flow.md).

## Using sub-agents (v2.1+)

Two role-shaped sub-agents cover the full eight-phase lifecycle. They are **opt-in** — the framework remains fully usable via the skill-and-workflow pattern alone — but they make role boundaries explicit and harder to drift across.

| Sub-agent | Owns | Skills it invokes |
|---|---|---|
| **Product Owner** | Specify, Clarify, Plan, Decisions, Tasks, draft-verification-gate, post-implement code-review and security-permissions-review, deploy-handoff drafting, spec DRAFT→DONE flip, **plus Architect responsibilities inline on escalation** (>10 files / cross-cutting refactor / platform blocker / blocked migration) | `requirements-specification`, `implementation-planning`, `code-review`, `security-permissions-review`, `release-deploy-reporting` |
| **AI Developer** | Run gate, Implement T-chain (one task = one commit; stops at gate), Run deploy command (gated on approval artifact, captures hash, runs probes) | `validation-and-qa`, `repo-onboarding-context-map` |

Both sub-agents always load the mandatory `communication` and `role-discipline` skills.

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

## Health check & recovery (v2.2+)

Fusebase Flow ships a built-in **health check skill** + **recovery script** that diagnose and repair overlay drift. The most common cause of drift is `fusebase update` (Fusebase CLI), which regenerates `AGENTS.md`, `.claude/settings.json`, and `.claude/hooks/` from CLI templates and evicts the Fusebase Flow overlay. Other causes include manual edits, foreign frameworks installed on top, or partial pulls.

### Quick reference

| Need | Command |
|---|---|
| Check overlay state (read-only) | `bash hooks/local/fusebase-flow-health-check.sh` <br> or `/fusebase-health` (Claude Code) <br> or *"is Fusebase Flow healthy?"* (any agent) |
| Recover the overlay | `bash hooks/local/post-fusebase-update.sh` <br> or reply `yes` when the skill offers recovery in chat |
| Upgrade engine + recovery to latest upstream | `bash hooks/local/upgrade-engine.sh` (v2.3.0+; refresh `.fusebase-flow-source/` first) |
| Avoid drift on routine updates | `fusebase update --skip-skills` (preserves Fusebase Flow overlay) |

### What the health check verifies

12 inventory checks per run:

- VERSION file
- AGENTS.md overlay block (`## Fusebase Flow — workflow lifecycle overlay`)
- CLAUDE.md overlay block (`## Fusebase Flow — additional rules (overlay)`)
- `.claude/settings.json` lifecycle events (auto-discovered count)
- `.claude/skills/` mirror count (auto-discovered set)
- `.claude/agents/` mirror count (auto-discovered set)
- Health-check skill self-presence
- Recovery script presence + executable
- Overlay templates folder presence
- `preflight.sh` clean
- `hooks/tests/run-tests.sh` passing
- Windows `shell:true` patch on `.claude/hooks/run-typecheck-features.js` (CVE-2024-27980 mitigation)

Plus active approval artifacts in `state/approvals/` are surfaced informationally so artifact-attributable test failures don't trigger false BROKEN verdicts.

### Verdicts

| Verdict | Exit | Meaning |
|---|:---:|---|
| `HEALTHY` | 0 | All checks pass; upstream in sync |
| `EXCEPTION_IN_EFFECT` | 3 | All drift attributable to active approval artifacts in `state/approvals/` (either v2 hook-test `protected_path_edit-*.json` or v2.4.0+ `health_check_deferral-*.json`) |
| `FUSEBASE_UPDATE_AFTERMATH` | 1 | Canonical `fusebase update` aftermath (AGENTS.md overlay missing AND settings.json reduced) |
| `DRIFTED` | 1 | Drift detected but doesn't match a known pattern |
| `BROKEN` | 2 | Genuine failure NOT attributable to operator-authored exceptions |

### Deferral artifacts (v2.4.0+)

When an install brief or operator deliberately omits parts of the canonical Fusebase Flow setup (e.g. lifecycle hooks not wired, Windows patch not applied per protected-paths discipline), file a **deferral artifact** at `state/approvals/health_check_deferral-<slug>-<YYYYMMDD>.json` listing the check_ids being deferred. Engine reclassifies matching drift items from `LOCAL_DRIFT` → `LOCAL_DEFERRED` (⊘ symbol in the report) and verdict drops to `EXCEPTION_IN_EFFECT` (exit 3).

See [docs/health-check-deferrals.md](docs/health-check-deferrals.md) for the artifact schema, the canonical check_id taxonomy, examples, and operator workflow for adding/removing deferrals.

### Recovery flow (the diagnose-then-offer pattern)

The skill is read-only during diagnosis. When drift is detected and recoverable, the skill **offers** recovery in chat:

```
Run recovery now? It will:
  • Restore AGENTS.md overlay block (if missing)
  • Merge .claude/settings.json lifecycle events (if reduced)
  • Re-apply Windows shell:true patch (if missing)
  • Re-mirror Fusebase Flow skills + sub-agents (no-op if already present)

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
  ├── agents-md-overlay.md                          ← block to append to AGENTS.md
  ├── claude-md-overlay.md                          ← block to append to CLAUDE.md
  ├── settings-json-merge.py                        ← Python merger (no jq)
  ├── skills/fusebase-flow-health-check/SKILL.md    ← skill template (recovery copies into mirrors)
  └── commands/fusebase-health.md                   ← slash command template
```

## What's inside

```
fusebase-flow/
├── README.md                       ← (this file)
├── PUBLISHING.md                   ← history-hygiene before public publishing
├── LICENSE                         ← MIT
├── install.sh                      ← optional convenience installer
├── AGENTS.md                       ← portable always-on baseline
├── CLAUDE.md                       ← Anthropic Claude Code adapter
├── GEMINI.md                       ← Gemini-style IDE adapter
├── FLOW_RULES.md                   ← FR-01..FR-17 always-on rules
├── VERSION                         ← 2.2.0
├── .gitattributes                  ← LF line endings for shell/python/yaml/md
├── .python-version                 ← 3.12 (recommended)
├── skills/                         ← 10 canonical skills (2 mandatory + 8 on-demand, incl. fusebase-flow-health-check)
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
├── .agents/skills/                 ← OpenAI / ChatGPT Codex skill mirror (× 10)
├── .claude/skills/                 ← Anthropic Claude Code skill mirror (× 10)
├── .claude/agents/                 ← Anthropic Claude Code sub-agent mirror (× 2)
├── .claude/commands/               ← Anthropic Claude Code slash commands (incl. /fusebase-health)
├── .claude/settings.json.example   ← Claude Code hook wiring
├── .codex/agents/                  ← OpenAI / ChatGPT Codex sub-agent mirror (× 2)
├── .codex/{config.toml,hooks.json}.example ← Codex hook wiring + project trust note
├── .cursor/rules/                  ← Cursor rules (always + scoped)
└── .github/
    ├── copilot-instructions.md     ← repo-wide Copilot / VS Code instructions
    ├── instructions/               ← scoped Copilot / VS Code instructions
    └── workflows/fusebase-flow-verify.yml ← CI: preflight + tests + mirror drift + public-surface allowlist
```

## How enforcement works

| Layer | What it does | Where |
|---|---|---|
| **Always-on rules** | 15 baseline rules every session attests to | `FLOW_RULES.md` |
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

## Clean-room

Designed after reviewing public AI coding workflow patterns. **No third-party code, prompts, skill files, or hook scripts are copied.** See [`docs/clean-room.md`](docs/clean-room.md).

## License

MIT. See [`LICENSE`](LICENSE).

## Publishing as a public GitHub template

Before making this repo public, follow the history-hygiene step in [`PUBLISHING.md`](PUBLISHING.md).

## Public reference docs

Public-facing reference material lives in [`docs/`](docs/):

- [`docs/compatibility.md`](docs/compatibility.md) — provider / IDE support detail
- [`docs/hook-coverage.md`](docs/hook-coverage.md) — hook × provider coverage
- [`docs/rail-mapping.md`](docs/rail-mapping.md) — FR-01..FR-17 → enforcement surfaces
- [`docs/clean-room.md`](docs/clean-room.md) — clean-room license attestation
- [`docs/source-map.md`](docs/source-map.md) — generic pattern attribution

## Audit folder

[`audit/`](audit/) is intentionally minimal in the public template:

- `README.md` — what does (and does not) live here
- `skill-mirror-manifest.txt` — SHA-256 manifest used by `preflight.sh` and CI to detect drift

Build-time phase reports, packaging reports, and per-run test output do **not** ship in the template. Generated runtime reports (install report, hook test report) are written to `state/audit/` (gitignored). CI runs upload that directory as the `fusebase-flow-audit` workflow artifact.
