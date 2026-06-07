---
name: project-onboarding
description: Use when the operator wants to set up / optimize THIS project for their vision — onboard the project, capture the North Star, define audience, or run the discovery interview. Triggers on "/onboard", "onboard my project", "set up my project", "capture my vision", "set my north star". Product-Owner-owned. Creates project artifacts (docs/north-star.md, fills AGENTS project-values). Do NOT use for ordinary ticket work, for writing application code, or to auto-run on install — it is operator-triggered only.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 3.4
risk_level: medium
invocation: manual
expected_outputs:
  - docs/north-star.md (the project's vision/focus anchor)
  - filled AGENTS.md § Project-specific values
  - ingested summary of any operator-provided research
related_workflows:
  - eight-phase-flow.md
  - session-initiation.md
hook_dependencies:
  - none
---

# Project Onboarding

> **Style:** Mode-B-lite. Product Owner role.

## Purpose

Capture the operator's project vision once, into durable artifacts that steer every later session. This is the engine that creates the Column-B artifacts the input-dependent skills read. Onboarding is **operator-triggered and optional** — if never run, Flow operates generically with zero project artifacts (no clutter).

## When to invoke

- Operator runs `/onboard` or says "onboard my project", "set up my project for my vision", "capture my North Star".
- Operator drops research into `docs/**/research/` and asks the PO to build project docs from it.
- Re-run any time the vision evolves ("update my North Star").

## Do not invoke when

- Ordinary ticket work (use `requirements-specification`).
- Writing application code (FR-01).
- On install / automatically — onboarding never auto-runs.

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Operator answers to discovery questions | chat | ask in chat text (FR-19); do not invent |
| Optional research | `docs/**/research/` | proceed without; note it |
| Artifact scaffold | `templates/north-star.md` | stop; template missing |

## Procedure

1. **Adopt Product Owner role**; self-attest (FR-01..FR-23). Do not write code.
2. **Adoption level — ask the operator (FR-19):** (a) one-line North Star, (b) full discovery interview, (c) skip. Respect "skip" — create nothing.
3. **Discovery interview** (chat text, one topic at a time): Who are you / your edge? · Audience: internal team vs external clients? · Product vision / the apps to build? · Domain / industry? · What does success look like? · Hard constraints?
4. **Ingest research** if present in `docs/**/research/` — summarize, cite; never invent domain facts.
5. **Write `docs/north-star.md`** from `templates/north-star.md`, populated with the operator's answers + `last_updated:` today. Only write content the operator actually provided.
6. **Fill `AGENTS.md` § Project-specific values** (`<placeholder>` fields) where the operator gave concrete values.
7. **Register for discovery:** confirm `docs/north-star.md` is at a path the session-start scan globs (it is). No separate registry needed in v1.
8. **Offer next** (FR-17): "North Star captured — want to define audience surfaces, or start a ticket?" Do not over-create artifacts unprompted.

## Output artifacts

| Artifact | Path | Mode |
|---|---|---|
| North Star | `docs/north-star.md` | Mode B |
| Project values | `AGENTS.md` § Project-specific values | Mode B |
| Interview record (optional) | chat or `docs/specs/<slug>/clarify-conversation.md` | Mode A/B |

## Failure cases

| Failure | Detection | Response |
|---|---|---|
| Operator skips | answer (c) at step 2 | create nothing; Flow stays generic |
| Vague vision | can't fill a section | leave it out; capture only what's given (no fabrication) |
| Template missing | step 5 | stop; report missing `templates/north-star.md` |

## Escalation path

- Ambiguous vision → ask operator in chat (FR-19).
- Domain-expert skill needed → `skill-authoring` (domain-expert mode), project-local output.

## Anti-patterns

- Do not auto-run on install.
- Do not create empty/placeholder artifacts — only operator-provided content.
- Do not write application code.
- Do not invent domain facts the operator didn't supply.

## Clean-room note

Original Fusebase Flow content. See `docs/source-map.md`. No third-party code, prompts, or skill files copied.