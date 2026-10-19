# Fusebase Flow 6.0 core (6.0.0-m3 pre-release)

The lifecycle core a project carries: the three git hooks and their modules, the six scripts in `hooks/local/` (reader, DONE check, validator, checks, slicer, gate), the 8 rules (`FLOW_RULES.md`), three agents (planner, builder, reader), six skills, one lifecycle page (`workflows/lifecycle.md`) and four document templates.

## Install

Needs git, bash and Python 3.10+ with PyYAML (`pip install -r hooks/requirements.txt`).

```
python maintainer/flow.py install --target <project> --providers claude,codex
```

It copies the core, writes the provider mirrors (`.claude/`, `.agents/skills/`, `.codex/agents/`), merges the Flow block into `AGENTS.md` and `CLAUDE.md`, records `audit/flow-install.json`, and installs the git hooks. It never overwrites a file you edited and never touches CLI-owned paths. Re-run it to upgrade within 6.0: it adds the new Flow files, replaces the Flow files you have not edited, keeps the ones you edited, rewrites its marked blocks in `.gitattributes` and `.gitignore` and `audit/flow-install.json`, and touches nothing else. `--register-reader` also schedules the heartbeat reader (`hooks/local/reader.py --once` every 5 minutes, `schtasks` or crontab) and records the line; a plain install schedules nothing. `--wire-hooks` merges the two tool handlers (`hooks/handlers/pre_tool_use.py`, `post_tool_use.py`) into `.claude/settings.json` (PreToolUse, PostToolUse, PostToolUseFailure) and `.codex/hooks.json` (PreToolUse, PostToolUse; Codex: unproven), beside the CLI's entries, which it never changes; a plain install writes neither file. Committing the installed files is a protected commit: see `workflows/lifecycle.md`. `python maintainer/flow.py health --target <project>` reports, read-only, what install knows: the version, the files changed or missing since the install, the marked blocks, the git hooks, the wiring per provider, the reader's schedule and `state/status.line`; it exits 0 when healthy and 1 when not.

## Moving a project from Flow 5.x

Run `python maintainer/flow.py migrate --target <project> --providers claude,codex`: a dry run that changes nothing. Then add `--apply --go-ahead` after the operator's go-ahead; it checks everything that could stop it before it changes a file, and lands the migration as one commit. Do not run `install` over a 5.x tree. `maintainer/release-notes/6.0.0-m3.md` has the steps.

## 6.0.0-m3 limits

The six scripts (reader, slicer, DONE check, checks, validator, gate) are in `hooks/local/`. Provider hook wiring is opt-in (`install --wire-hooks`), and the 6.0.0 `commit-msg` checks the subject (`workflows/lifecycle.md`). Codex: unproven (`docs/provider-coverage.md`).
