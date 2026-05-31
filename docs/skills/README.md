# `docs/skills/` — project-internal (project-learned) skills

This folder holds **project-specific** skills that capture patterns the operator + AI teams discovered while working on this project. They are distinct from the **framework skills** that ship with Fusebase Flow.

## Two kinds of skills

| Type | Location | Lifetime | Source |
|---|---|---|---|
| **Framework skills** | `skills/<name>/SKILL.md` | Lives with Fusebase Flow versions | Shipped with the template; mirrored to `.agents/skills/` (OpenAI/ChatGPT Codex) and `.claude/skills/` (Anthropic Claude Code) for provider consumption |
| **CLI provider skills** | `.agents/skills/<name>/SKILL.md` and `.claude/skills/<name>/SKILL.md` | Lives with the Fusebase CLI provider layer | Copied from Fusebase Apps CLI provider assets; supports app/runtime domain work; not tracked as canonical Flow skills |
| **Project skills** | `docs/skills/<slug>/SKILL.md` (this folder) | Lives with the project | Authored by the operator + AI when a pattern recurs across 3+ tickets |

Project skills are NOT auto-loaded by provider skill matchers. They are loaded by reference: the operator says "load skill `<slug>`" or the Product Owner cites them during investigation. CLI provider skills are auto-visible only on provider surfaces that read `.agents/skills/` or `.claude/skills/`; see `docs/fusebase-cli-edition.md`.

## When to file a project skill

Per FR-15 + `workflows/knowledge-curation.md`, a project skill is the right artifact when:

- A pattern emerges across **3+ tickets** ("we always do X")
- A whole **area of non-obvious expertise** would help future sessions
- An **operator convention** ("we always X") needs codifying
- A **vendor/platform quirk** affects how this project does things

If the trigger is a **specific incident** (one bug, one outage, one platform surprise), file a `docs/problem-catalog/<slug>/problem.md` instead.

## Filing a project skill

Invoke `skills/skill-authoring/SKILL.md`, then use `templates/skill-template.md` as substrate. Fill out:

- frontmatter (`name`, trigger-oriented `description`, etc.)
- Purpose, When to invoke, Do not invoke when
- Required inputs, Procedure, Output artifacts
- Failure cases, Escalation path, Anti-patterns

Project skills MUST be Mode-B-lite (concise, structured, trigger-oriented, AI-consumable; no narrative padding; no chat-style visuals). They are loaded by AI sessions to apply the captured pattern.

## Index format

```markdown
# Skills Index (project-internal)

| Slug | Triggers | One-line summary |
|---|---|---|
```

## Skill vs problem-catalog vs framework skill — quick decision

| If... | Then... |
|---|---|
| It's a one-off incident with a specific cause | `docs/problem-catalog/<slug>/problem.md` |
| It's a recurring pattern (3+ tickets) in this project | `docs/skills/<slug>/SKILL.md` (here) |
| It's a domain that EVERY Fusebase Flow project would benefit from | invoke `skill-authoring`, then propose upstream into `skills/` as a separate framework change |
| It's Fusebase Apps CLI runtime/domain guidance already present in provider assets | keep it in `.agents/skills/` / `.claude/skills/`; do not duplicate it under root `skills/` |
| It's a one-off architectural choice for the current ticket | that goes in `docs/specs/<slug>/decisions.md`, not a skill |

## Loading project skills in provider / IDE sessions

- **Cursor:** reference path explicitly in chat or add to `.cursor/rules/` if it's truly always-on for the project.
- **Anthropic Claude Code / OpenAI ChatGPT Codex:** these match against `description` for skills under their own skills/ surfaces. Project skills here are NOT mirrored automatically; if a project skill becomes load-bearing for a provider, use `skill-authoring` to decide whether to promote it to a framework skill or add an explicit project mirror procedure.
- **GitHub Copilot / VS Code:** reference the SKILL.md path explicitly in chat, or add a focused `.github/instructions/<slug>.instructions.md` if the project skill is always-on.
- **Gemini-style IDE agents / generic local:** reference path explicitly in chat or cite from `AGENTS.md`.

## Style

Mode-B-lite. The skill body is read by AI sessions to apply the pattern; it is NOT a human onboarding doc. Predictable section names per `templates/skill-template.md`.
