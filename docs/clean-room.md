# License clean-room attestation — Fusebase Flow Local v0.1

## Statement

Fusebase Flow Local is original content. Designed after reviewing public AI coding workflow patterns; **no third-party code, prompts, skill files, or hook scripts are copied** into this template.

## Scope of this attestation

This attestation applies to every file in the public template tree, including but not limited to:

- All canonical and mirrored SKILL.md files
- All Python lifecycle hook handlers and shared utilities
- All shell scripts (git fallback hooks + local scripts)
- All YAML policy files
- All workflow and template documents
- All provider / IDE compatibility files
- All audit and documentation files

## License of original content

This template is published under the MIT License (see `LICENSE`). MIT permits use, copy, modification, merger, publication, distribution, sub-licensing, and sale, subject to inclusion of the copyright notice and the warranty disclaimer.

## What "clean-room" means here

- No SKILL.md text was copied from any third-party project's skill catalog.
- No hook handler logic was copied from any third-party hook system.
- No prompt text, system prompt, vendor configuration sample, or example file was reproduced verbatim from a third-party source.
- Public protocol shapes (e.g., the structure of provider settings JSON or hook event schemas) were used as **specification**, not as **source code**. The example files in `.claude/`, `.codex/`, etc. are written from the public protocol shape, not copied from any vendor sample repo.

## Evidence

| Evidence | Location |
|---|---|
| Standard attestation wording | `skills/<slug>/SKILL.md` (× 7), mirrors (× 14), `templates/skill-template.md`, `hooks/README.md` |
| Public-surface guard | `.github/workflows/fusebase-flow-verify.yml` runs an allowlist check on every push and PR; tracked top-level entries that are not on the approved list fail CI |
| Build phase reviews | retained outside the public template; available with the release-audit bundle for the corresponding tagged release |
| Pattern attribution | [`docs/source-map.md`](source-map.md) (generic pattern categories; no vendor-specific copying) |

## Trademarks

Provider and IDE names mentioned in this template (e.g., the names of compatibility surfaces that Fusebase Flow Local explicitly supports) are the trademarks of their respective owners. Mention is descriptive — it identifies the surface a compatibility file targets — and does not imply endorsement, partnership, or affiliation.

## Liability

The MIT License's warranty disclaimer applies. Fusebase Flow Local is provided **AS IS**, without warranty of any kind.

## Last amended

```
2026-05-08 — initial Phase 4 attestation; consolidates the clean-room
              property documented across earlier phases.
```
