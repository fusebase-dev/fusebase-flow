---
name: <kebab-case-slug>
description: <one to two sentences. Lead with WHEN to invoke and WHEN NOT to invoke. The agent's skill matcher reads this first.>
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: low | medium | high
invocation: automatic | manual | manual-for-side-effects
expected_outputs:
  - <artifact path or short description>
related_workflows:
  - <workflow filename, e.g., eight-phase-flow.md>
hook_dependencies:
  - <hook name, or "none">
---

# <Skill Name>

> **Style:** Mode-B-lite. Concise, structured, trigger-oriented, AI-consumable. No narrative padding. No chat-style ASCII visuals. Predictable section names so skill loaders can navigate.

## Purpose

One to three sentences. What this skill is for. What problem it solves. Why this skill exists separately from rules and workflows.

## When to invoke

Bullet list of concrete triggers. Each trigger should be matchable against operator prompts or repo state.

- Operator says "<short phrase>" / "<short phrase>"
- Repo state shows `<condition>`
- Active workflow phase is `<Phase name>`

## Do not invoke when

Bullet list of negative triggers. Prevent skill sprawl.

- Operator is asking about `<unrelated topic>`
- Required precondition `<X>` is missing (skill would fail silently)
- A higher-priority skill `<other-skill>` already covers this case

## Required inputs

Tabular list of inputs the skill assumes are present.

| Input | Where it lives | If missing |
|---|---|---|
| `<input name>` | `<path or context>` | `<fallback or stop>` |

## Procedure

Numbered steps. Each step is a single action. Use concrete identifiers (T#, sha:abc1234, file:line) where applicable.

1. <Step 1 — what to do, what to check>
2. <Step 2>
3. <Step 3>
4. <Final step — what to produce>

## Worked example

Required when Procedure has 3+ steps or a decision table; otherwise omit this section. Exactly one compact example, ≤12 lines: concrete input → key step outcomes → produced artifact. Not a tutorial; variant detail goes to `references/`.

1. <Input: the operator request or repo state that fires this skill>
2. <Key step outcomes with concrete identifiers>
3. <Produced artifact + evidence recorded>

## Output artifacts

Tabular list of files or chat outputs the skill produces.

| Artifact | Path or location | Mode |
|---|---|---|
| `<artifact name>` | `<path>` | Mode B / Mode A / Mode-B-lite |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| `<failure>` | `<signal>` | `<recovery action>` |

## Escalation path

Bullet list. When the skill cannot complete, where does work go next?

- Stop and ask operator with `<specific question>` in chat text (FR-19); do not use popup / clickable menu tools
- Hand off to skill `<other-skill>` via `<trigger>`
- Park as backlog ticket at `docs/backlog/<slug>/README.md`

## Anti-patterns

What this skill must NOT do. Bullet list of guardrails.

- Do not write production code (FR-01)
- Do not lock decisions on operator's behalf
- Do not bypass the verification gate
- Do not auto-invoke when `invocation: manual`

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.

---

**Authoring checklist (Mode-B-lite):**

- [ ] Frontmatter `description` leads with WHEN to invoke and WHEN NOT
- [ ] Destination classified: `flow-skills/` framework skill vs `docs/skills/` project skill vs problem-catalog entry
- [ ] External sources, if any, transformed conceptually; no copied prose, examples, proprietary labels, or vendor-specific paths
- [ ] Existing skills checked for overlap before adding a new skill
- [ ] Role applicability named: Product Owner / AI Developer / Architect / Deploy phase
- [ ] No human-onboarding preamble in body
- [ ] Tables/bullets dominate prose paragraphs
- [ ] Concrete identifiers (T#, file:line, command names) over vague pointers
- [ ] No chat-style ASCII visuals (visuals belong in chat per FR-08, not in skill files)
- [ ] Predictable sections present in this exact order
- [ ] Procedure-heavy skills: one compact `## Worked example` (≤12 lines) after Procedure
- [ ] Trigger/gate changes: retrofit-hygiene sweep clean — ALL surfaces in `flow-skills/skill-authoring/SKILL.md` § Retrofit-hygiene sweep updated in the SAME edit — and matcher dry-run recorded
- [ ] Body fits in one screen of an 80-col editor when possible
- [ ] Framework skills only: provider mirrors and `audit/skill-mirror-manifest.txt` refreshed
