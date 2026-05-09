# Installing Fusebase Flow into an Existing Project

Fusebase Flow is designed to install **into** an existing repository, not to replace one. The primary workflow assumes you already have a project under version control, an IDE you like, and one or more coding agents (Claude Code, Codex, Cursor, Copilot, Gemini, etc.). Fusebase Flow adds a repo-local workflow layer — rules, workflows, hooks, policies, templates, and validation — without altering your project's source layout, build, or runtime.

Your existing development setup keeps working exactly as before. Fusebase Flow becomes infrastructure that sits alongside your code and is read by whichever agent or IDE you use.

## Existing Fusebase CLI / MCP projects

If your repository was already initialized by Fusebase CLI, has MCP configuration, or already contains `AGENTS.md`, `.claude/settings.json`, `.agents/skills/`, `.claude/skills/`, `.mcp.json`, `.cursor/mcp.json`, `fusebase.json`, or `skills-lock.json`, do not use the generic bulk copy commands below without review.

Use the safe install guide:

[`docs/install-fusebase-cli-project.md`](install-fusebase-cli-project.md)

The generic install on this page is for repositories that do not already have overlapping agent, MCP, provider, or workflow configuration. Running the bulk copy over a Fusebase CLI / MCP project will overwrite runtime rules, MCP setup, Claude hooks, and existing skills.

## Supported environments

Fusebase Flow is provider- and IDE-neutral. It works with any tool that reads files from the repository.

| Surface | Configuration files | Hooks support | Skills support | Notes |
|---|---|---|---|---|
| Claude Code | `CLAUDE.md`, `.claude/settings.json.example`, `.claude/skills/` | Yes, when project hooks are enabled | Yes, via `.claude/skills/` | First-class provider surface. Claude Code loads project memory from `CLAUDE.md`. |
| OpenAI / ChatGPT Codex | `AGENTS.md`, `.agents/skills/`, `.codex/` | Codex config/hooks where enabled + git fallback | Yes, via `.agents/skills/` | Reads repo-local instructions and skill metadata. |
| Cursor | `.cursor/rules/`, `AGENTS.md` | Git fallback hooks | Repo-file guidance | Uses repo-local rules and instructions. |
| GitHub Copilot / VS Code | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `AGENTS.md` | Git hooks + GitHub Actions | Repository instructions | Uses repository-wide and path-specific instructions. |
| Gemini / Antigravity-style IDE agents | `GEMINI.md`, `AGENTS.md` | Git fallback hooks | Repo-file guidance | Any agent that reads repo files can follow the workflow. |
| Generic local Git workflow | `AGENTS.md`, `FLOW_RULES.md`, `hooks/git/` | Git hooks | Manual | Works without an IDE agent. |

The git fallback hooks in `hooks/git/` provide a safety net for surfaces that don't expose lifecycle hooks of their own.

## Recommended installation workflow

1. Open your existing repository in VS Code (or your editor of choice).
2. Clone Fusebase Flow into `.fusebase-flow-source` inside or next to your repo (see commands below).
3. Copy or merge the framework directories you want from `.fusebase-flow-source/` into your repo root — for example: `hooks/`, `workflows/`, `policies/`, `templates/`, `skills/`, plus `AGENTS.md`, `FLOW_RULES.md`, and any provider configs you use (`.claude/`, `.codex/`, `.cursor/`, `.agents/`, `.github/`).
4. Install the one runtime dependency: `pip install -r hooks/requirements.txt`.
5. Run `bash .fusebase-flow-source/install.sh` from your repo root. The installer is interactive and opt-in. It installs git fallback hooks, runs preflight, and mirrors skills into provider folders.
6. Remove `.fusebase-flow-source` when finished.
7. Commit the staged changes as a single setup commit.

Your existing project continues to build, test, and run normally. Nothing in your source tree is rewritten.

## Example installation

### SSH clone

```bash
git clone git@github.com:fusebase-dev/fusebase-flow.git .fusebase-flow-source
```

### HTTPS clone

```bash
git clone https://github.com/fusebase-dev/fusebase-flow.git .fusebase-flow-source
```

## Copy Fusebase Flow files into your repo

After cloning `.fusebase-flow-source`, copy the framework files you want into your repository root.

Before copying, make sure your working tree is clean:

```bash
git status --short
```

For existing projects, install on a branch:

```bash
git checkout -b chore/install-fusebase-flow
```

If your repo already contains `AGENTS.md`, `CLAUDE.md`, `.github/`, `.claude/`, `.codex/`, `.cursor/`, or `.agents/`, do not blindly run the copy commands. Copy into a temporary staging folder first, compare the files, and manually merge the parts you want.

Bash / zsh:

```bash
cp -R .fusebase-flow-source/.agents . 2>/dev/null || true
cp -R .fusebase-flow-source/.claude . 2>/dev/null || true
cp -R .fusebase-flow-source/.codex . 2>/dev/null || true
cp -R .fusebase-flow-source/.cursor . 2>/dev/null || true
cp -R .fusebase-flow-source/.github . 2>/dev/null || true

cp -R .fusebase-flow-source/hooks .
cp -R .fusebase-flow-source/policies .
cp -R .fusebase-flow-source/skills .
cp -R .fusebase-flow-source/templates .
cp -R .fusebase-flow-source/workflows .

cp .fusebase-flow-source/AGENTS.md .
cp .fusebase-flow-source/FLOW_RULES.md .
cp .fusebase-flow-source/CLAUDE.md . 2>/dev/null || true
cp .fusebase-flow-source/GEMINI.md . 2>/dev/null || true
```

PowerShell:

```powershell
Copy-Item -Recurse -Force .fusebase-flow-source\.agents . -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force .fusebase-flow-source\.claude . -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force .fusebase-flow-source\.codex . -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force .fusebase-flow-source\.cursor . -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force .fusebase-flow-source\.github . -ErrorAction SilentlyContinue

Copy-Item -Recurse -Force .fusebase-flow-source\hooks .
Copy-Item -Recurse -Force .fusebase-flow-source\policies .
Copy-Item -Recurse -Force .fusebase-flow-source\skills .
Copy-Item -Recurse -Force .fusebase-flow-source\templates .
Copy-Item -Recurse -Force .fusebase-flow-source\workflows .

Copy-Item -Force .fusebase-flow-source\AGENTS.md .
Copy-Item -Force .fusebase-flow-source\FLOW_RULES.md .
Copy-Item -Force .fusebase-flow-source\CLAUDE.md . -ErrorAction SilentlyContinue
Copy-Item -Force .fusebase-flow-source\GEMINI.md . -ErrorAction SilentlyContinue
```

The commands above are fastest for repos that do not already have these files. In mature repos, prefer manual merge for instruction files, provider config folders, and `.github/` workflows.

Then check the working tree:

```bash
git status --short
```

Review `git status` before running the installer. If the target repository already has `AGENTS.md`, `CLAUDE.md`, `.github/`, or provider config directories, review the diff carefully before staging.

## Run the installer

Run the installer only after the framework files have been copied into the target repository.

```bash
bash .fusebase-flow-source/install.sh
```

The installer is interactive and opt-in. Pass `--auto-yes` (or `-y`) to accept all default steps non-interactively. It does not copy framework directories itself — that is the previous step. It installs git fallback hooks, runs preflight, and mirrors skills into provider folders.

- No SaaS dependency.
- No server or daemon.
- No telemetry.
- No external API calls.
- All execution is local, in your shell, against your working tree.

## Validate the installation

Run:

```bash
bash hooks/local/preflight.sh
bash hooks/tests/run-tests.sh
```

Expected result:

- preflight finishes with 0 errors and 0 warnings
- hook tests pass

If either step reports failures, resolve them before continuing — the framework's guardrails depend on a clean preflight.

## Installing from a private Fusebase Flow repository

If the `fusebase-flow` repository is private, authenticate to GitHub before cloning. The instructions below assume your GitHub account has access to the repository.

### SSH

Verify your SSH key is registered with GitHub:

```bash
ssh -T git@github.com
```

A successful response looks like:

```
Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

Then clone using SSH:

```bash
git clone git@github.com:fusebase-dev/fusebase-flow.git .fusebase-flow-source
```

### HTTPS

Authenticate using the GitHub CLI (recommended) or a personal access token, then clone:

```bash
gh auth login
git clone https://github.com/fusebase-dev/fusebase-flow.git .fusebase-flow-source
```

If your account does not have access to the private repository, GitHub returns a 404 or authentication error.

GitHub authentication is per-machine. Each new computer where you clone Fusebase Flow needs SSH key registration or `gh auth login` performed once.

## Cleaning up the cloned source

Once `install.sh` finishes (or you have copied the framework directories you need), the `.fusebase-flow-source` clone is no longer required.

Bash / zsh:

```bash
rm -rf .fusebase-flow-source
```

PowerShell:

```powershell
Remove-Item -Recurse -Force .fusebase-flow-source
```

Re-clone the source if you need to update Fusebase Flow later (see [Updating Fusebase Flow later](#updating-fusebase-flow-later)).

## What gets installed

A typical post-install layout:

```text
my-existing-project/
├── .agents/                 # Generic agent provider config
├── .claude/                 # Claude Code skills + settings
├── .codex/                  # Codex provider config
├── .cursor/                 # Cursor provider config
├── .github/                 # Workflow validation Action(s)
├── hooks/                   # Lifecycle + git fallback handlers
├── policies/                # YAML policies read by hooks
├── skills/                  # Canonical provider-neutral skills
├── templates/               # Spec, plan, decision, handoff templates
├── workflows/               # Phase definitions and verification gates
├── AGENTS.md                # Always-on baseline rules
├── FLOW_RULES.md            # FR-01..FR-15 rule set
└── ...your existing project files, untouched...
```

Your application code, build config, lockfiles, tests, infra, and docs stay where they are. Fusebase Flow becomes infrastructure that lives inside the repo.

## What the installer changes

The bundled `install.sh` is intentionally small and interactive. It does not rewrite your application code, and it does not perform an automatic backup/merge pass on existing files. Each step is an opt-in y/N prompt; pass `--auto-yes` to accept all defaults non-interactively.

Steps the installer performs:

- **Install git fallback hooks** — runs `hooks/local/install-git-hooks.sh`, which writes `pre-commit` and `commit-msg` into `.git/hooks/`. Existing hook files at those paths are overwritten by the underlying script. Back them up first if you have custom hooks there.
- **Run preflight** — runs `hooks/local/preflight.sh` to validate framework structure, policies, and skill mirrors. Read-only.
- **Mirror skills** — copies `skills/` into `.agents/skills/` and `.claude/skills/`.

What the installer does **not** do automatically:

- Copy framework directories (`hooks/`, `policies/`, `workflows/`, `templates/`, `skills/`, provider configs) into your project. You stage those yourself before running the installer.
- Merge `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md` with files you already have. If those files exist in your repo, review the diffs by hand before staging the framework versions.
- Modify `.github/workflows/` files in repos that already have GitHub Actions configured.

If your repository already contains custom `.git/hooks/`, custom GitHub Actions, or repo-local instruction files, review the framework's versions side-by-side and stage them deliberately. Use `git diff` and `git status` after each step.

## Git workflow

Fusebase Flow does not impose a branching model.

- **Direct-to-main** is acceptable for solo developers and local-only workflows. The verification gates still run before commit.
- **Branch + PR** is recommended for shared repos, regulated environments, or higher-risk changes.
- Either way, hooks and verification gates apply: spec → plan → decisions → tasks → verify → implement → deploy.

You opt into the level of ceremony your team needs. The framework does not force a workflow on you.

## Updating Fusebase Flow later

To pick up newer rules, hooks, or templates:

1. Re-clone the source: `git clone <fusebase-flow-url> .fusebase-flow-source`.
2. Diff the framework directories against your repo (for example `diff -r .fusebase-flow-source/hooks ./hooks`) and stage updates deliberately.
3. Re-run `bash .fusebase-flow-source/install.sh` to refresh git hooks, preflight, and skill mirrors.
4. Review provider configs (`.claude/`, `.codex/`, `.cursor/`, `.agents/`, `.github/`) before committing — these are the most likely to have local customization.
5. Commit the upgrade as a single, isolated commit so the diff is easy to audit.
6. Remove `.fusebase-flow-source` when finished.

## Removing Fusebase Flow

Fusebase Flow is removable. Delete the framework directories and provider configs and your project is back to its pre-install state:

- `hooks/`
- `workflows/`
- `policies/`
- `skills/`
- `templates/`
- `.claude/`, `.codex/`, `.cursor/`, `.agents/` (or just the Fusebase Flow subset)
- The Fusebase Flow section appended to `AGENTS.md` / `CLAUDE.md`
- `FLOW_RULES.md`

Your application code, history, and existing tooling are untouched.

## Runtime requirements

- **Python 3.11+** required for hook handlers. Use whichever interpreter your OS exposes as `python3`.
- **Stdlib-first** — handlers are written against the standard library wherever possible.
- **One non-stdlib dependency** — `PyYAML` is the only third-party package the hooks require. It is used to parse `policies/*.yml`.
- **No framework runtime** — there is no app server, scheduler, or background process to manage.
- **No server or daemon** — hooks fire on lifecycle events from your IDE/agent or from git.

Install the dependency once after staging the framework files:

```bash
pip install -r hooks/requirements.txt
```

`hooks/requirements.txt` pins only `PyYAML`. Use a virtual environment or your project's existing Python environment if you would rather not install globally.

## Important architecture note

Fusebase Flow is **not** an agent. The agents you already use — Claude Code, Codex, Cursor, Copilot, Gemini — remain the actual coding agents. Fusebase Flow does not generate code, talk to model APIs, or replace your IDE.

The framework works because agents read files from the repository. Specifically:

- `AGENTS.md` and `FLOW_RULES.md` — always-on rules every agent reads at session start
- Provider configs (`.claude/`, `.codex/`, `.cursor/`, `.agents/`) — surface-specific entry points
- `skills/` — task-scoped guidance the agent loads when relevant
- `workflows/` — phase definitions and verification gates the operator and agent share
- `hooks/` — lifecycle and git handlers that enforce policy locally
- `policies/` — declarative rules the hooks read

Because every artifact is a plain file in your repo, the framework is transparent, diffable, and version-controlled like the rest of your code.

## Security and privacy

- **Local execution only** — hooks and policies run on your machine, in your shell.
- **No external SaaS** — Fusebase Flow has no hosted component.
- **No telemetry** — no usage events, no analytics, no phone-home.
- **No cloud runtime** — no managed orchestrator, no remote queue.
- **No hidden API calls** — handlers are short Python files you can read end-to-end.
- **Policies stay in the repo** — your guardrails live in `policies/*.yml`, version-controlled and reviewable in PRs.

If your repo is air-gapped, Fusebase Flow still works. If your repo is public, nothing about Fusebase Flow leaks data.

## Best practices

- Commit immediately after install so the framework's first state is reviewable.
- Run the preflight / verification gate once right after install to confirm the wiring.
- Review provider configs (`.claude/`, `.codex/`, `.cursor/`, `.agents/`) before sharing the repo.
- Keep hook scripts executable (`chmod +x` on POSIX; verify line endings on Windows).
- Do not bypass validation hooks (`--no-verify` and equivalents). If a hook fails, fix the cause.
- If you staged workflow files under `.github/workflows/` and Actions are enabled for the repository, verify the validation workflow passes on the first push. If you did not stage workflow files or Actions are disabled, this step does not apply.
- Treat `AGENTS.md` and `FLOW_RULES.md` as the source of truth — when an agent and a memory disagree, the file wins.

## Summary

Fusebase Flow installs **into** repositories rather than forcing teams onto a separate platform, IDE, or hosted service. Your existing development workflow stays intact; you gain specification-driven phases, validation gates, repo-local hooks, and explicit guardrails that every agent in the repo can read and follow.
