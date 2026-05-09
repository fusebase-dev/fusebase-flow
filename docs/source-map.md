# Source map — Fusebase Flow Local v0.1

This document records that **Fusebase Flow Local was designed after reviewing public AI coding workflow patterns**, and that **no third-party code, prompts, skill files, or hook scripts are copied** into this template.

## Standard attestation

> Designed after reviewing public AI coding workflow patterns. No third-party code, prompts, skill files, or hook scripts are copied.

This wording is used in:

- All 8 canonical SKILL.md `Clean-room note` sections (`skills/<slug>/SKILL.md`).
- All 14 mirror SKILL.md files (regenerated from canonical via `mirror-skills.sh`).
- `templates/skill-template.md` (substrate for future skills).
- `hooks/README.md` (hook framework attestation).

## Pattern categories considered (generic descriptions only)

The following design patterns are common to public AI coding workflow discussion. Fusebase Flow Local implements them as **original content**; specific vendor names are not advertised in the public template.

| Pattern category | How Fusebase Flow Local implements it |
|---|---|
| Always-on repository instructions | `AGENTS.md` (portable baseline) + provider-specific compatibility files |
| Skill catalogs | `skills/<slug>/SKILL.md` with frontmatter + predictable section structure |
| Rules / Skills / Workflows / Hooks separation | This repo's directory layout under `` |
| Plan-before-edit discipline | FR-02 + `implementation-planning` skill + `architect-escalation` workflow |
| Repo-map / context-map onboarding | `repo-onboarding-context-map` skill |
| Lint / typecheck loop | FR-13 + `pre-commit` git hook |
| Lifecycle hooks | 8 Python handlers under `hooks/handlers/` reading a unified event schema |
| Pre-commit secret scanning | `hooks/git/pre-commit` + `policies/secret-patterns.yml` |
| Project-trust gating | Documented in `.codex/config.toml.example` and noted in `hooks/README.md` |
| Direct-to-main vs branch + PR mode | `approval-policy.yml: workflow_mode` |

## What is NOT copied

- No SKILL.md prose from any third-party project.
- No hook handler code or shell scripts from any third-party project.
- No vendor configuration examples reproduced verbatim; all examples (`.claude/settings.json.example`, `.codex/config.toml.example`, etc.) are written from the public protocol shape, not copied from any vendor sample repo.
- No prompt text, system prompt, or skill description from any third-party project.

## Verification

The clean-room property is validated by:

1. Original wording check — the public-template tree is verified against a word-boundary search for non-target tool names; expected result is zero matches.
2. Standard wording presence — `preflight.sh` is configured to inspect skill frontmatter; manual review of clean-room notes confirms the standard wording in all 8 canonical + 16 mirror SKILL.md files.
3. License attestation — see [`docs/clean-room.md`](clean-room.md) for the explicit clean-room statement.

## Internal research notes (not published)

Any internal research notes that reference specific external projects belong **outside** this GitHub template. They live in operator-private notebooks or internal company docs, not in the public template tree. The published template uses generic wording only.

## Last amended

```
2026-05-08 — initial draft (Phase 4); replaces per-skill conceptual-inspiration notes
              with the standard generic attestation; consolidates clean-room evidence
              for the public template tree.
```
