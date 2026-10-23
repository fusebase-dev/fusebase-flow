# Fusebase Flow 6.0 core (pre-release)

The lifecycle core a project carries: the three git hooks and their modules, the six scripts in `hooks/local/` (reader, DONE check, validator, checks, slicer, gate), the 8 rules (`FLOW_RULES.md`), three agents (planner, builder, reader), six skills, one lifecycle page (`workflows/lifecycle.md`) and four document templates.

## Install

Needs git, bash and Python 3.10+ with PyYAML: `<the interpreter Flow will use> -m pip install -r hooks/requirements.txt`
(`python3` on Linux and macOS, `python` or `py -3` with python.org's Python on Windows). On Debian or Ubuntu, whose
python3 may have no pip or refuse a system-wide install, use `sudo apt install python3-yaml` or a virtual environment.
On macOS: `brew install coreutils` (FR-27's bounded runs need `timeout` or `gtimeout`).
The commands below that start with `bash`, or set a variable before one (`FF_BOOTSTRAP_TTL_MIN=30 bash ...`), run in Git
Bash on Windows (any POSIX shell elsewhere). In PowerShell, set the variable first and call Git's bash by its path:
`$env:FF_BOOTSTRAP_TTL_MIN=30; & "$env:ProgramFiles\Git\bin\bash.exe" hooks/local/write-bootstrap-approval.sh`
(a bare `bash` there can be WSL's).

```
python3 maintainer/flow.py install --target <project> --providers claude,codex
```

It copies the core, writes the provider mirrors (`.claude/`, `.agents/skills/`, `.codex/agents/`), merges the Flow block into `AGENTS.md` and `CLAUDE.md`, records `audit/flow-install.json`, and installs the git hooks. It never overwrites a file you edited and never touches CLI-owned paths. Re-run it to upgrade within 6.0: it adds the new Flow files, replaces the Flow files you have not edited, keeps the ones you edited, rewrites its marked blocks in `.gitattributes` and `.gitignore` and `audit/flow-install.json`, and touches nothing else. `--register-reader` also schedules the heartbeat reader (`hooks/local/reader.py --once` every 5 minutes, `schtasks` or crontab) and records the line; a plain install schedules nothing. `--wire-hooks` merges the two tool handlers (`hooks/handlers/pre_tool_use.py`, `post_tool_use.py`) into `.claude/settings.json` (PreToolUse, PostToolUse, PostToolUseFailure) and `.codex/hooks.json` (PreToolUse, PostToolUse; Codex: unproven), beside the CLI's entries, which it never changes; a plain install writes neither file. Committing the installed files is a protected commit with a `flow:` subject, such as `flow: install Fusebase Flow <version>`: stage them by name (`git add -u` for the files it changed, `git add -- <each file it lists under added:>` for the new ones), mint in Git Bash with `FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh`, commit, then run the script with `--consume`; see `workflows/lifecycle.md`. `python maintainer/flow.py health --target <project>` reports, read-only, what install knows: the version, the files changed or missing since the install, the marked blocks, the git hooks, the wiring per provider, the reader's schedule as the scheduler reports it and `state/status.line`; it exits 0 when healthy and 1 when not. Git keeps one set of hooks per repository, so install and migrate run in its main worktree (a linked one is refused) and list the other branches and worktrees that must merge the installed branch before their next commit.

## Moving a project from Flow 5.x

Run `python maintainer/flow.py migrate --target <project> --providers claude,codex`: a dry run that changes nothing. Then add `--apply --go-ahead` after the operator's go-ahead; it checks everything that could stop it before it changes a file, and lands the migration as one commit. Do not run `install` over a 5.x tree. The release note of the version you install, `maintainer/release-notes/<version>.md`, has the steps.

## Limits

The six scripts (reader, slicer, DONE check, checks, validator, gate) are in `hooks/local/`. Provider hook wiring is opt-in (`install --wire-hooks`), and the 6.0.0 `commit-msg` checks the subject (`workflows/lifecycle.md`). Codex: unproven (`docs/provider-coverage.md`).
