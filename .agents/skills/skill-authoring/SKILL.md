---
name: skill-authoring
description: Use when the operator asks to create, update, import, analyze, or preserve a reusable skill or recurring instruction pattern. Do NOT use for one-off ticket work, ordinary code implementation, problem-catalog incidents, or copying external skill text verbatim.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.1
risk_level: medium
invocation: automatic
expected_outputs:
  - skill classification: framework skill vs project skill vs problem-catalog entry vs no skill
  - clean-room skill brief with role applicability and non-overlap analysis
  - canonical SKILL.md updates when implementation is approved
  - mirror / manifest / source-leak validation notes for framework skills
related_workflows:
  - knowledge-curation.md
  - eight-phase-flow.md
hook_dependencies:
  - none
---

# Skill Authoring

> **Style:** Mode-B-lite. Clean-room, Fusebase-specific procedure for deciding, writing, wiring, and validating reusable skills.

## Purpose

Create or update skills without skill sprawl, role drift, mirror drift, or license contamination. This skill governs reusable instruction capture: what deserves a skill, where it belongs, which role uses it, and what validation proves it was authored cleanly.

## When to invoke

- Operator asks to create, update, install, import, compare, or analyze a skill.
- Operator provides an external skill, prompt, guide, or workflow and asks to reproduce similar capability in Fusebase Flow.
- A recurring pattern should become durable reusable expertise.
- Existing skill behavior needs tightening after a missed bug, failed handoff, or repeated role drift.
- A framework skill is added or changed and provider mirrors/manifests must stay in sync.

## Do not invoke when

- The request is normal per-ticket implementation covered by `implementation-planning`, `validation-and-qa`, or another domain skill.
- The issue is a one-off failure with a concrete cause; file `docs/problem-catalog/<slug>/problem.md` instead.
- The operator wants to copy external text verbatim. Refuse copying and offer clean-room capability extraction.
- The topic is already covered by an existing skill and only needs normal use, not authoring or update.
- A provider mirror is the only target. Canonical skill edits start in `skills/` or `docs/skills/`; mirrors are generated or deliberately promoted.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Operator request | chat | Stop; skill purpose depends on requested reuse |
| Candidate source material | attachment, repo file, operator summary, or observed repeated pattern | Proceed only from available concepts; do not invent missing domain rules |
| Existing skill catalog | `skills/`, `.agents/skills/`, `.claude/skills/`, `docs/skills/README.md` | Search before adding; avoid duplicate skills |
| CLI edition map, for CLI provider assets | `docs/fusebase-cli-edition.md` | Treat provider assets as domain support, not canonical Flow skills |
| Skill substrate | `templates/skill-template.md` | Stop; use the canonical section order |
| Role boundaries | `FLOW_RULES.md`, `skills/role-discipline/SKILL.md`, `agents/*/AGENT.md` | Stop if role ownership cannot be assigned |
| Clean-room constraints | `docs/source-map.md`, `docs/clean-room.md` | Treat external material as concept-only |
| Mirror process | `hooks/local/mirror-skills.sh`, `audit/skill-mirror-manifest.txt` | Required for framework skill changes |

## Procedure

### 1. Classify the reusable knowledge

| If the pattern is... | Destination | Owner |
|---|---|---|
| Useful to every Fusebase Flow project and description-matchable by agents | `skills/<slug>/SKILL.md` | Framework change; PO defines, AI Developer implements |
| Fusebase Apps CLI runtime/domain guidance already present in provider assets | `.agents/skills/<slug>/` and `.claude/skills/<slug>/` | Provider asset; reference from Flow artifacts, do not duplicate |
| Specific to one target project after 3+ repeated uses | `docs/skills/<slug>/SKILL.md` | Product Owner / project team |
| A one-off incident, outage, or diagnostic lesson | `docs/problem-catalog/<slug>/problem.md` | Product Owner |
| A one-ticket design or architecture choice | `docs/specs/<slug>/decisions.md` | Product Owner / Architect |
| Already covered by an existing skill | Update that skill or leave unchanged | Depends on owning role |

Default to updating an existing skill when overlap is material. Add a new framework skill only when the trigger, procedure, failure modes, and role boundary are distinct.

### 2. Extract capability clean-room

For external material:

1. Read only to identify capabilities, triggers, constraints, failure modes, and reusable checks.
2. Do not copy paragraphs, example blocks, proprietary labels, vendor-specific paths, or exact output formats.
3. Replace product/tool-specific assumptions with Fusebase Flow concepts: role, phase, artifact path, workflow, skill, policy, hook, mirror.
4. Remove prohibited or irrelevant brand terms before writing repo files.
5. Write a short comparison table: existing Fusebase skill overlap, new capability, recommended role.

### 3. Assign role applicability

| Role | Allowed authoring responsibility |
|---|---|
| Product Owner | Decide whether a skill is needed; classify framework vs project skill; define trigger, purpose, acceptance criteria, role applicability, and non-overlap |
| Architect | Review skill design when it changes role boundaries, workflows, hooks, provider compatibility, or broad framework semantics |
| AI Developer | Implement approved skill edits; update canonical files; regenerate mirrors; run validation; report evidence |
| Deploy phase | No skill authoring; may surface post-deploy lessons for PO curation |

If role ownership is unclear, stop and ask in chat text with 2-3 options; do not use popup / clickable menus.

### 4. Author the skill

Use `templates/skill-template.md` section order. Keep the body Mode-B-lite:

| Section | Requirement |
|---|---|
| Frontmatter | `name`, trigger-rich `description`, `source_inspiration: conceptual-only`, `license_status: clean-room-original`, version, risk, invocation, outputs, workflows, hooks |
| Purpose | 1-3 sentences; why this exists separately |
| When to invoke | concrete triggers the matcher/operator can recognize |
| Do not invoke when | negative triggers to prevent sprawl |
| Required inputs | table with location and fallback |
| Procedure | numbered or role-scoped steps |
| Output artifacts | paths and chat/artifact mode |
| Failure cases | detection and response |
| Escalation path | next skill/workflow/operator question |
| Anti-patterns | things the skill must not do |
| Clean-room note | standard Fusebase attestation |

Move long examples or variant-specific detail into `references/` only when needed. Do not create README, quick-reference, changelog, or other auxiliary files inside a skill folder.

### 5. Wire framework skills

For `skills/<slug>/SKILL.md` changes, check whether each surface needs an update:

| Surface | Update when |
|---|---|
| `skills/role-discipline/SKILL.md` | role don't-list or refusal phrasing changes |
| `agents/product-owner/AGENT.md` | PO / Architect should load or invoke the skill |
| `agents/ai-developer/AGENT.md` | AI Developer / Deploy phase should load or invoke the skill |
| `workflows/*.md` | a workflow creates, consumes, or validates the skill |
| `templates/*.md` | generated artifacts need fields from the skill |
| `README.md`, `docs/framework.md`, `docs/compatibility.md`, `docs/source-map.md` | skill counts, catalog, compatibility, or attestation counts change |
| `CHANGELOG.md`, `docs/release-notes/<version>.md` | release-visible capability changes |

Then run `hooks/local/mirror-skills.sh` and, if agent files changed, `hooks/local/mirror-agents.sh`.

### 6. Validate

Minimum validation for framework skill changes:

| Check | Expected |
|---|---|
| Mirror integrity | canonical skill hash matches `.agents/skills/` and `.claude/skills/`; manifest regenerated |
| Agent mirror integrity | canonical agent hash matches `.claude/agents/` and `.codex/agents/` if agents changed |
| Source-leak scan | no external/prohibited names, copied phrases, or vendor-specific paths introduced |
| Count scan | no stale skill-count references after adding/removing framework skills |
| CLI provider boundary | provider CLI assets remain outside root `skills/` unless separately approved as clean-room Flow framework skills |
| Format check | `git diff --check` clean except known line-ending warnings |
| Scope review | no unrelated refactors or duplicated skill responsibilities |

If validation cannot run, report the exact missing check and treat the change as incomplete until the operator accepts that gap.

## Output artifacts

| Artifact | Path or location | Mode |
|---|---|---|
| Skill analysis / recommendation | chat | Mode A |
| Framework skill | `skills/<slug>/SKILL.md` | Mode-B-lite |
| Project skill | `docs/skills/<slug>/SKILL.md` | Mode-B-lite |
| Problem-catalog alternative | `docs/problem-catalog/<slug>/problem.md` | Mode B |
| Mirror manifest | `audit/skill-mirror-manifest.txt` | generated |
| Agent mirror manifest | `audit/agent-mirror-manifest.txt` | generated when agents change |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Duplicate skill | Existing skill has same trigger/procedure | Update existing skill or recommend no change |
| External text copied | Source-leak scan or review finds copied prose/examples | Replace with clean-room rewrite before claiming done |
| Wrong location | Project-specific skill added under `skills/`, or framework skill placed only under `docs/skills/` | Move to correct surface and update references |
| Mirror drift | Preflight/hash check finds mirror mismatch | Run mirror script and re-check |
| Role drift | PO writes production code via skill, or AI Developer changes product direction | Stop; apply `role-discipline` refusal and re-scope |
| Overlong skill | SKILL.md grows toward large reference-guide size | Split variant detail into `references/` and keep SKILL.md procedural |

## Escalation path

- If the operator wants a new framework skill but overlap is unclear, ask for approval in chat text with an options table: update existing skill, create new skill, or file project skill.
- If the skill changes hooks, policies, or workflow semantics, escalate to Architect review before implementation.
- If implementation touches provider mirrors or manifests, hand to AI Developer for canonical edit + mirror regeneration.
- If clean-room status cannot be established, stop and request a concept summary instead of using the source text.

## Anti-patterns

- Do not copy external skill prose, example blocks, or proprietary labels.
- Do not write directly to `.agents/skills/` or `.claude/skills/` as the source of truth.
- Do not promote CLI provider assets into root `skills/` without a separate clean-room proposal and non-overlap analysis.
- Do not add a new skill when a narrow update to an existing skill covers the behavior.
- Do not use a skill for a one-off bug that belongs in the problem catalog.
- Do not make Product Owner sessions implement code or AI Developer sessions lock product decisions.
- Do not ask skill-authoring questions through popup / clickable menus; use chat text per FR-19.
- Do not leave mirrors, manifests, counts, or release docs stale after adding a framework skill.

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
