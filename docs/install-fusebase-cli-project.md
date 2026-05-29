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

## CLI-first, Flow-second recovery model

Ownership is explicit:

- `cli-owned`: current FuseBase CLI or the project runtime owns the file. Flow diagnoses only.
- `flow-owned`: Fusebase Flow owns the file and recovery may restore it from Flow source.
- `shared-merge`: both layers contribute; Flow may append or merge only the Flow-owned addition.

The maintained ownership map is `hooks/local/fusebase-flow-overlays/agent-surface-ownership.json`. To produce a no-write collision report before or after install:

```bash
bash hooks/local/check-cli-flow-conflicts.sh
```

If that report or the health check says `CLI_LAYER_DRIFT`, restore CLI-owned files with the current FuseBase CLI first. Then run Flow recovery. Flow must never restore CLI provider skills, CLI hooks, MCP config, `fusebase.json`, `skills-lock.json`, or active `.codex/config.toml` from this repository's bundled copy.

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

Append this to the bottom of the existing `AGENTS.md`. **The heading marker must be exactly `## Fusebase Flow — workflow lifecycle overlay`** — the health-check engine and recovery script grep for this string verbatim.

Minimal block:

```md
---

## Fusebase Flow — workflow lifecycle overlay

This repository also uses Fusebase Flow. Read `FLOW_RULES.md` for the always-on workflow rules, `workflows/` for lifecycle procedures, and `skills/` for on-demand workflow guidance.

Existing Fusebase CLI, MCP, SDK, provider, and project-specific rules remain authoritative for runtime behavior. Fusebase Flow governs workflow lifecycle: specification, planning, implementation, verification, review, and deploy readiness.
```

For the **recommended fuller block** (mandatory + on-demand skills lists, sub-agent references, state-announcement footer, project-specific values table, plus the maintenance posture / recovery section), use the canonical template that ships with this release:

```bash
cat hooks/local/fusebase-flow-overlays/agents-md-overlay.md >> AGENTS.md
```

That same template is what `bash hooks/local/post-fusebase-update.sh` uses to restore AGENTS.md if it ever loses the overlay block (e.g. after `fusebase update`).

### CLAUDE.md append section

Append this to the bottom of the existing `CLAUDE.md`. **The heading marker must be exactly `## Fusebase Flow — additional rules (overlay)`**.

Minimal block:

```md
## Fusebase Flow — additional rules (overlay)

This repository includes Fusebase Flow as a workflow overlay. The canonical workflow files are in `FLOW_RULES.md`, `workflows/`, `skills/`, `policies/`, and `templates/`.

Do not replace existing Claude instructions, hooks, or project-specific rules. Merge Fusebase Flow guidance as an overlay.
```

Recommended fuller block:

```bash
cat hooks/local/fusebase-flow-overlays/claude-md-overlay.md >> CLAUDE.md
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

## Health check & recovery (v2.2+)

After install, you can verify the overlay is healthy at any time:

```bash
bash hooks/local/fusebase-flow-health-check.sh
```

Or, in Claude Code, type `/fusebase-health` (or ask any AI agent: *"is Fusebase Flow healthy?"*).

The health check is **read-only**. It produces a structured report with these verdicts: `HEALTHY`, `CLI_LAYER_DRIFT`, `FLOW_LAYER_DRIFT`, `SHARED_MERGE_DRIFT`, `EXCEPTION_IN_EFFECT`, `BROKEN`.

### When `fusebase update` changes shared agent files

The Fusebase CLI's `fusebase update` command can refresh CLI-owned agent assets such as provider skills, provider agents, Claude hook helper files, MCP/IDE config, and shared files like `AGENTS.md` and `.claude/settings.json`.

Recovery order is always:

1. Current FuseBase CLI restores CLI-owned files.
2. Fusebase Flow restores only Flow-owned files and shared Flow additions.

Recovery is bundled into a single idempotent script:

```bash
bash hooks/local/post-fusebase-update.sh
```

This restores Flow skills, Flow agents, AGENTS/CLAUDE overlay blocks, Flow lifecycle settings merge, the Flow health skill mirrors, and the `/fusebase-health` command. It does not patch `.claude/hooks/**` or restore CLI provider text.

When triggered through the chat skill, the agent will **offer** to run recovery for you — reply `yes` (or `run it` / `fix it` / `proceed`) and the agent executes the script and re-checks. The skill never runs recovery without an explicit affirmative reply.

### Avoiding drift on routine CLI updates

```bash
fusebase update --skip-skills
```

The `--skip-skills` flag tells the CLI to skip the AGENTS.md / `.claude/*` regeneration entirely, so your Fusebase Flow overlay stays intact. Use the full CLI refresh only when you actively want current CLI-side skill, agent, hook, or settings updates, then run Flow recovery.

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
