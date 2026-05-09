# Installing Fusebase Flow into a Fusebase CLI / MCP Project

This guide is for repositories that have already been initialized by Fusebase CLI or that already contain MCP configuration. Such repositories already carry runtime rules, MCP configuration, skills, hooks, and provider-specific settings, and you must not overwrite them.

- Fusebase Flow installs as an additive **workflow overlay** on top of an existing Fusebase CLI / MCP project.
- Do not blindly copy files over the repo root. The generic copy commands in [install-existing-project.md](install-existing-project.md) are unsafe for this case.
- Existing Fusebase CLI, MCP, and SDK rules remain authoritative for runtime behavior and integration contracts.
- Fusebase Flow governs the workflow lifecycle only: spec → plan → decisions → tasks → verify → implement → deploy.

## When to use this guide

Use this guide if your repository already contains any of the following:

- `AGENTS.md`
- `CLAUDE.md`
- `.claude/settings.json`
- `.claude/hooks/`
- `.claude/agents/`
- `.agents/skills/`
- `.claude/skills/`
- `.codex/config.toml`
- `.cursor/mcp.json`
- `.mcp.json`
- `fusebase.json`
- `skills-lock.json`

If none of these are present, you can use the generic [install-existing-project.md](install-existing-project.md) flow instead.

## Golden rule

Never overwrite these files blindly:

- `AGENTS.md`
- `CLAUDE.md`
- `.gitignore`
- `.claude/settings.json`
- `.codex/config.toml`
- `.cursor/mcp.json`
- `.mcp.json`
- `fusebase.json`
- `skills-lock.json`
- existing skill folders (`.agents/skills/`, `.claude/skills/`)
- existing GitHub workflows under `.github/workflows/`

When in doubt, copy the Fusebase Flow version into a temporary location, diff against the existing file, and merge by hand.

## Recommended safe workflow

1. Create a branch.

   ```bash
   git checkout -b chore/install-fusebase-flow
   ```

2. Confirm a clean working tree.

   ```bash
   git status --short
   ```

3. Clone Fusebase Flow temporarily.

   ```bash
   git clone git@github.com:fusebase-dev/fusebase-flow.git .fusebase-flow-source
   ```

   or:

   ```bash
   git clone https://github.com/fusebase-dev/fusebase-flow.git .fusebase-flow-source
   ```

4. Copy only additive root framework folders (see below).
5. Append or merge protected files manually (see below).
6. Run validation.
7. Commit as a single setup commit.
8. Remove `.fusebase-flow-source`.

## Safe additive copies

These framework files belong to Fusebase Flow and are unlikely to exist in a Fusebase CLI / MCP repo. They can be copied without review:

- `skills/`
- `workflows/`
- `policies/`
- `templates/`
- `hooks/`
- `audit/`
- `state/`
- `FLOW_RULES.md`
- `VERSION`
- `install.sh`
- `PUBLISHING.md`
- `LICENSE`
- `GEMINI.md`
- `.gitattributes`
- `.python-version`

Bash / zsh:

```bash
cp -R .fusebase-flow-source/skills .
cp -R .fusebase-flow-source/workflows .
cp -R .fusebase-flow-source/policies .
cp -R .fusebase-flow-source/templates .
cp -R .fusebase-flow-source/hooks .
cp -R .fusebase-flow-source/audit .
cp -R .fusebase-flow-source/state .

cp .fusebase-flow-source/FLOW_RULES.md .
cp .fusebase-flow-source/VERSION .
cp .fusebase-flow-source/install.sh .
cp .fusebase-flow-source/PUBLISHING.md .
cp .fusebase-flow-source/LICENSE .
cp .fusebase-flow-source/GEMINI.md .
cp .fusebase-flow-source/.gitattributes .
cp .fusebase-flow-source/.python-version .
```

PowerShell:

```powershell
Copy-Item -Recurse -Force .fusebase-flow-source\skills .
Copy-Item -Recurse -Force .fusebase-flow-source\workflows .
Copy-Item -Recurse -Force .fusebase-flow-source\policies .
Copy-Item -Recurse -Force .fusebase-flow-source\templates .
Copy-Item -Recurse -Force .fusebase-flow-source\hooks .
Copy-Item -Recurse -Force .fusebase-flow-source\audit .
Copy-Item -Recurse -Force .fusebase-flow-source\state .

Copy-Item -Force .fusebase-flow-source\FLOW_RULES.md .
Copy-Item -Force .fusebase-flow-source\VERSION .
Copy-Item -Force .fusebase-flow-source\install.sh .
Copy-Item -Force .fusebase-flow-source\PUBLISHING.md .
Copy-Item -Force .fusebase-flow-source\LICENSE .
Copy-Item -Force .fusebase-flow-source\GEMINI.md .
Copy-Item -Force .fusebase-flow-source\.gitattributes .
Copy-Item -Force .fusebase-flow-source\.python-version .
```

If any of these names already exist in your repo, stop and review by hand before copying.

## Provider and IDE additions that need review

These are generally additive, but require review when similar files already exist:

- `.claude/settings.json.example`
- `.codex/config.toml.example`
- `.codex/hooks.json.example`
- `.cursor/rules/*`
- `.github/copilot-instructions.md`
- `.github/instructions/*`
- `.github/workflows/fusebase-flow-verify.yml`

Guidelines:

- Copy `.example` files as examples only. Do not let them overwrite active settings or config files.
- Do not overwrite `.claude/settings.json`, `.codex/config.toml`, or `.cursor/mcp.json` if they exist.
- Review GitHub workflow filenames before adding new ones — collisions can replace working CI.

## Skill folders

Skill folders are additive. Names must not collide.

1. Check existing skill names:

   ```bash
   find .agents/skills .claude/skills -maxdepth 2 -name SKILL.md 2>/dev/null
   ```

2. Copy Fusebase Flow skill mirrors only if there are no name collisions:

   ```bash
   mkdir -p .agents/skills .claude/skills
   cp -R .fusebase-flow-source/.agents/skills/* .agents/skills/
   cp -R .fusebase-flow-source/.claude/skills/* .claude/skills/
   ```

3. If a skill folder with the same name already exists, stop and compare manually.

4. After copying, refresh provider mirrors from the canonical `skills/`:

   ```bash
   bash hooks/local/mirror-skills.sh
   ```

Notes:

- Canonical Fusebase Flow skills live in `skills/`.
- Provider mirrors live in `.agents/skills/` and `.claude/skills/`.
- Existing project skills must remain intact.

## Manual merge files

Do not copy these from Fusebase Flow over the existing project files. Append the additions below by hand.

### AGENTS.md append section

Append this to the bottom of the existing `AGENTS.md`:

```md
---

# Fusebase Flow Local — workflow discipline overlay

This repo also uses Fusebase Flow Local. Read `FLOW_RULES.md` for the always-on workflow rules, `workflows/` for procedures, and `skills/` for task-specific guidance.

Existing Fusebase CLI, MCP, SDK, and project-specific rules above remain authoritative for runtime behavior and integration contracts.

Fusebase Flow governs the workflow lifecycle:

spec → plan → decisions → tasks → verify → implement → deploy

When a runtime rule and a workflow rule both apply, obey both. If they conflict, stop and ask the operator before proceeding.
```

### CLAUDE.md append section

Append this to the bottom of the existing `CLAUDE.md`:

```md
## Fusebase Flow Local

This repository includes Fusebase Flow Local as a workflow overlay.

- `FLOW_RULES.md` contains the always-on workflow rules.
- `skills/` contains canonical Fusebase Flow skills.
- `.claude/skills/` contains Claude Code skill mirrors.
- `workflows/` contains lifecycle procedures.
- `hooks/` contains optional local guardrails.

If `.claude/settings.json` already contains project hooks, do not replace it with `.claude/settings.json.example`. Merge lifecycle hooks only after review.
```

### .gitignore append section

Append this to `.gitignore`:

```gitignore
# Fusebase Flow runtime state
state/audit.log.jsonl
state/context-summary.md
state/*.tmp
state/approvals/*
!state/approvals/.gitkeep
!state/.gitkeep
state/audit/*
!state/audit/.gitkeep

# Fusebase Flow local policy overrides
policies/approval-policy.local.yml
policies/command-policy.local.yml
policies/protected-paths.local.yml
policies/required-artifacts.local.yml
policies/gate-contracts.local.yml
policies/secret-patterns.local.yml
```

## Merging `.claude/settings.json`

Never replace an active `.claude/settings.json` automatically.

If the existing project already has `.claude/settings.json`:

- Keep existing hooks.
- Keep existing permissions.
- Keep existing project-specific behavior.
- Open `.claude/settings.json.example` as a reference.
- Manually merge Fusebase Flow lifecycle hooks only if desired.
- Test after merging.

Existing Stop hooks such as lint, typecheck, and quality checks must remain in place. Fusebase Flow hooks should be added alongside existing hooks, not replace them.

## MCP and Fusebase CLI files

Never modify or replace these during a Fusebase Flow install:

- `.mcp.json`
- `.cursor/mcp.json`
- `fusebase.json`
- `skills-lock.json`
- Fusebase CLI-generated SDK or runtime rules
- existing MCP server configuration

Fusebase Flow is a workflow overlay, not an MCP or runtime replacement.

## Post-install validation

Run:

```bash
pip install -r hooks/requirements.txt
bash hooks/local/preflight.sh
bash hooks/tests/run-tests.sh
bash hooks/local/mirror-skills.sh
git status --short
```

Expected result:

- preflight: 0 errors and 0 warnings
- hook tests pass
- mirror skills completes without destructive overwrite
- `git status` shows only intended changes

## Commit

Commit as one setup commit:

```bash
git add .
git commit -m "chore: install Fusebase Flow workflow overlay"
```

## Cleanup

Remove the temporary source clone.

Bash / zsh:

```bash
rm -rf .fusebase-flow-source
```

PowerShell:

```powershell
Remove-Item -Recurse -Force .fusebase-flow-source
```

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `AGENTS.md` already exists | Fusebase CLI or project rules already installed | Append the Fusebase Flow section instead of replacing |
| `.claude/settings.json` already exists | Project has active Claude hooks | Merge settings manually; keep existing hooks and permissions |
| Skill folder already exists | Project has existing skills | Check for name collisions before copying |
| MCP config exists | Project already has MCP runtime setup | Do not modify MCP files |
| Preflight fails | Missing copied folder or policy issue | Recheck the additive-copy list and rerun |

## Summary

Fusebase CLI / MCP projects should receive Fusebase Flow as an additive workflow overlay. Keep existing runtime rules and MCP configuration intact. Add Fusebase Flow rules, workflows, policies, hooks, templates, and skills around the existing project rather than replacing the project's active configuration.
