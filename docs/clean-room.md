# License clean-room attestation — Fusebase Flow

## Statement

Canonical Fusebase Flow content is original content. It was designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied into canonical Flow roots.

This Fusebase CLI edition also includes copied Fusebase Apps CLI provider assets. Those assets are edition/domain assets, not canonical Flow framework files. Their boundary is documented in `docs/fusebase-cli-edition.md` and `docs/source-map.md`.

## Scope of canonical Flow attestation

This attestation applies to:

- Root `skills/<slug>/SKILL.md` canonical Flow skills.
- Flow mirrors generated from canonical skills under `.agents/skills/` and `.claude/skills/`.
- Root `agents/<name>/AGENT.md` canonical Flow role agents and generated provider mirrors.
- Flow lifecycle hook handlers and shared utilities under `hooks/handlers/`, `hooks/shared/`, `hooks/git/`, and `hooks/local/`.
- Flow YAML policies, workflows, templates, and framework documentation.
- Provider/IDE compatibility files authored by Flow.

## Out of scope

| Asset | Why out of scope |
|---|---|
| `.claude/skills/<cli-skill>/` and `.agents/skills/<cli-skill>/` | Copied CLI provider skills for Fusebase Apps domain support |
| `.claude/agents/app-*.md` and `.codex/agents/app-*.md` | Copied CLI app agents |
| `.claude/hooks/*` | Copied CLI quality hooks |

## License of original Flow content

This template is published under the MIT License (see `LICENSE`). MIT permits use, copy, modification, merger, publication, distribution, sub-licensing, and sale, subject to inclusion of the copyright notice and the warranty disclaimer.

## What clean-room means here

- No third-party SKILL.md text is copied into canonical Flow `skills/`.
- No third-party hook handler logic is copied into canonical Flow hook roots.
- No prompt text, system prompt, vendor configuration sample, or example file is reproduced verbatim from a third-party source into canonical Flow roots.
- Public protocol shapes are used as specification, not as source code.
- CLI provider assets stay provider-scoped and are not described as clean-room Flow framework skills.

## Evidence

| Evidence | Location |
|---|---|
| Standard attestation wording | Canonical `skills/<slug>/SKILL.md`, Flow mirrors, `templates/skill-template.md`, `hooks/README.md` |
| Edition boundary map | `docs/fusebase-cli-edition.md` |
| Source map | `docs/source-map.md` |
| Mirror manifests | `audit/skill-mirror-manifest.txt`, `audit/agent-mirror-manifest.txt` |

## Trademarks

Provider and IDE names mentioned in this template are the trademarks of their respective owners. Mention is descriptive and does not imply endorsement, partnership, or affiliation.

## Liability

The MIT License's warranty disclaimer applies. Fusebase Flow is provided AS IS, without warranty of any kind.

## Last amended

```
2026-05-27 - Fusebase CLI edition attestation scope clarified.
```
