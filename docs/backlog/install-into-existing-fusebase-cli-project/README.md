# Install into existing Fusebase CLI / MCP project

**Status:** parked
**One-liner:** Build a safer installer for repos that already have Fusebase CLI and MCP configuration.

## Goal

Create a safer installer for repos that already have Fusebase CLI and MCP configuration.

## Proposed script

`install-into-existing.sh` (or equivalent), invoked from the cloned `.fusebase-flow-source/` against the target repo root.

## Required behavior

Detection:

- detect existing `AGENTS.md`
- detect existing `CLAUDE.md`
- detect existing `.gitignore`
- detect existing `.claude/settings.json`
- detect existing `.codex/config.toml`
- detect existing `.cursor/mcp.json`
- detect existing `.mcp.json`
- detect existing `fusebase.json`
- detect existing `.agents/skills/`
- detect existing `.claude/skills/`

Merge:

- append a Fusebase Flow section to `AGENTS.md` rather than overwriting
- append a Fusebase Flow section to `CLAUDE.md` rather than overwriting
- append Fusebase Flow patterns to `.gitignore`

Copy:

- copy additive folders only (`skills/`, `workflows/`, `policies/`, `templates/`, `hooks/`, `audit/`, `state/`)
- copy skills only when no name collision exists
- stop and report if skill name collisions exist

Protections:

- never replace existing MCP files (`.mcp.json`, `.cursor/mcp.json`, `fusebase.json`, `skills-lock.json`)
- never replace an active `.claude/settings.json`
- never overwrite an active `.codex/config.toml`
- produce a conflict report before changing anything
- support a dry-run mode before any write

## Status

Planned for v0.1.1 or v0.2.

## Related

- [docs/install-fusebase-cli-project.md](../../install-fusebase-cli-project.md) — the manual safe-install procedure this script will automate.
- [docs/install-existing-project.md](../../install-existing-project.md) — the generic existing-project install path.
