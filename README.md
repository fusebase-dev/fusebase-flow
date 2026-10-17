# Fusebase Flow 6.0 core (6.0.0-m2 pre-release)

The lifecycle core a project carries: the three git hooks and their modules, the 8 rules (`FLOW_RULES.md`), three agents (planner, builder, reader), six skills, one lifecycle page (`workflows/lifecycle.md`) and four document templates.

## Install

Needs git, bash and Python 3.10+ with PyYAML (`pip install -r hooks/requirements.txt`).

```
python maintainer/flow.py install --target <project> --providers claude,codex
```

It copies the core, writes the provider mirrors (`.claude/`, `.agents/skills/`, `.codex/agents/`), merges the Flow block into `AGENTS.md` and `CLAUDE.md`, records `audit/flow-install.json`, and installs the git hooks. It never overwrites a file you edited and never touches CLI-owned paths. Re-run it to upgrade within 6.0. Committing the installed files is a protected commit: see `workflows/lifecycle.md`.

## Moving a project from Flow 5.x

Run `python maintainer/flow.py migrate --target <project> --providers claude,codex`: a dry run that changes nothing. Then add `--apply --go-ahead` after the operator's go-ahead; it checks everything that could stop it before it changes a file, and lands the migration as one commit. Do not run `install` over a 5.x tree. `maintainer/release-notes/v6.0.0-m2.md` has the steps.

## 6.0.0-m2 limits

The six scripts (reader, slicer, DONE check, checks, validator, gate) and provider hook wiring are not in this pre-release; the lifecycle page says which steps are done by hand. Codex: unproven.
