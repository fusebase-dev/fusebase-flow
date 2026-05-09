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
4. Open a fresh agent session, paste the handoff, and the Implementer executes the task chain — stopping at the verification gate.
5. Paste the gate report back to the originating session. Run `code-review` and `security-permissions-review`.
6. If clean, the operator says *"prepare deploy"* — the `release-deploy-reporting` skill drafts the deploy handoff, you paste it into the Implementer session, deploy runs, probes verify.

The full eight-phase lifecycle lives at [`workflows/eight-phase-flow.md`](workflows/eight-phase-flow.md).

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
├── FLOW_RULES.md                   ← FR-01..FR-15 always-on rules
├── VERSION                         ← 0.1.0
├── .gitattributes                  ← LF line endings for shell/python/yaml/md
├── .python-version                 ← 3.12 (recommended)
├── skills/                         ← 8 canonical skills (1 mandatory + 7 on-demand)
├── workflows/                      ← 10 procedures
├── policies/                       ← 6 YAML policies
├── templates/                      ← 13 substrates
├── hooks/
│   ├── README.md
│   ├── flow_hook_event.schema.json
│   ├── handlers/                   ← 8 Python lifecycle handlers
│   ├── shared/                     ← 6 shared utilities
│   ├── git/                        ← pre-commit + commit-msg
│   ├── local/                      ← install / preflight / verify-gate / approve-local / mirror-skills
│   ├── tests/                      ← run-tests.sh + 11 fixtures
│   └── requirements.txt            ← pyyaml (only non-stdlib dep)
├── audit/
│   ├── README.md                   ← what does (and does not) live here
│   └── skill-mirror-manifest.txt   ← sha256 manifest used by preflight + CI
├── state/                          ← runtime state (gitignored contents)
├── docs/                           ← public reference docs + per-project artifacts
├── .agents/skills/                 ← OpenAI / ChatGPT Codex skill mirror (× 8)
├── .claude/skills/                 ← Anthropic Claude Code skill mirror (× 8)
├── .claude/settings.json.example   ← Claude Code hook wiring
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
- [`docs/rail-mapping.md`](docs/rail-mapping.md) — FR-01..FR-15 → enforcement surfaces
- [`docs/clean-room.md`](docs/clean-room.md) — clean-room license attestation
- [`docs/source-map.md`](docs/source-map.md) — generic pattern attribution

## Audit folder

[`audit/`](audit/) is intentionally minimal in the public template:

- `README.md` — what does (and does not) live here
- `skill-mirror-manifest.txt` — SHA-256 manifest used by `preflight.sh` and CI to detect drift

Build-time phase reports, packaging reports, and per-run test output do **not** ship in the template. Generated runtime reports (install report, hook test report) are written to `state/audit/` (gitignored). CI runs upload that directory as the `fusebase-flow-audit` workflow artifact.
