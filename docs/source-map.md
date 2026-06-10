# Source map — Fusebase Flow

This document records source boundaries for the Fusebase CLI provider layer. Canonical Fusebase Flow files remain clean-room original. CLI provider assets are copied as Fusebase Apps CLI provider assets and are intentionally kept outside canonical Flow roots.

## Standard attestation

> Designed after reviewing public AI coding workflow patterns. No third-party code, prompts, skill files, or hook scripts are copied.

This wording is used in:

- All 28 canonical SKILL.md `Clean-room note` sections (`flow-skills/<slug>/SKILL.md`).
- All 56 mirror SKILL.md files (regenerated from canonical via `mirror-skills.sh`).
- `templates/skill-template.md` (substrate for future skills).
- `hooks/README.md` (hook framework attestation).

## Edition-specific copied assets

| Asset family | Source | Destination | Boundary |
|---|---|---|---|
| CLI provider skills | Fusebase Apps CLI project template | `.claude/skills/<cli-skill>/`, `.agents/skills/<cli-skill>/` | Provider/domain assets; not canonical Flow skills |
| CLI app agents | Fusebase Apps CLI project template | `.claude/agents/app-*.md`, `.codex/agents/app-*.md` | Provider/domain agents; not canonical Flow role agents |
| CLI quality hooks | Fusebase Apps CLI project template | `.claude/hooks/*` | Claude Code provider hooks; separate from Flow `hooks/handlers/*` |

These copied assets are documented in `docs/fusebase-cli-edition.md`. Do not cite the standard Flow clean-room attestation as applying to the copied CLI provider assets.

## Pattern categories considered (generic descriptions only)

The following design patterns are common to public AI coding workflow discussion. Fusebase Flow implements them as **original content**; specific vendor names are not advertised in the public template.

| Pattern category | How Fusebase Flow implements it |
|---|---|
| Always-on repository instructions | `AGENTS.md` (portable baseline) + provider-specific compatibility files |
| Skill catalogs | `flow-skills/<slug>/SKILL.md` with frontmatter + predictable section structure |
| Rules / Skills / Workflows / Hooks separation | This repo's directory layout under `` |
| Plan-before-edit discipline | FR-02 + `implementation-planning` skill + `architect-escalation` workflow |
| Repo-map / context-map onboarding | `repo-onboarding-context-map` skill |
| Lint / typecheck loop | FR-13 + `pre-commit` git hook |
| Lifecycle hooks | 8 Python handlers under `hooks/handlers/` reading a unified event schema |
| Pre-commit secret scanning | `hooks/git/pre-commit` + `policies/secret-patterns.yml` |
| Project-trust gating | Documented in `.codex/config.toml.example` and noted in `hooks/README.md` |
| Direct-to-main vs branch + PR mode | `approval-policy.yml: workflow_mode` |

## What is NOT copied

- No SKILL.md prose from any third-party project is copied into canonical Flow `flow-skills/`.
- No hook handler code or shell scripts from any third-party project are copied into canonical Flow `hooks/handlers/`, `hooks/shared/`, `hooks/git/`, or `hooks/local/`.
- No vendor configuration examples reproduced verbatim; all examples (`.claude/settings.json.example`, `.codex/config.toml.example`, etc.) are written from the public protocol shape, not copied from any vendor sample repo.
- No prompt text, system prompt, or skill description from any third-party project.

## Verification

The clean-room property is validated by:

1. Original wording check — the public-template tree is verified against a word-boundary search for non-target tool names; expected result is zero matches.
2. Standard wording presence - `preflight.sh` is configured to inspect skill frontmatter; manual review of clean-room notes confirms the standard wording in all 28 canonical + 56 Flow mirror SKILL.md files.
3. Edition boundary check - CLI provider assets remain under provider surfaces and are not added to `flow-skills/` or canonical Flow mirror manifests.
4. License attestation - see [`docs/clean-room.md`](clean-room.md) for the explicit clean-room statement for canonical Flow files.

## Internal research notes (not published)

Any internal research notes that reference specific external projects belong **outside** this GitHub template. They live in operator-private notebooks or internal company docs, not in the public template tree. The published template uses generic wording only.

## Last amended

```
2026-05-27 - Fusebase CLI edition source map; distinguishes canonical Flow clean-room files
              from copied CLI provider/domain assets.
```
