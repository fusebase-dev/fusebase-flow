---
name: app-quality-patterns
description: Use when drafting a spec/ACs for an app feature, planning or building UI views with filters/search/reports, implementing delete/mutation flows, or reviewing feature work — routes to the cross-project behavioral quality patterns (QP-xx) that recurring consumer-app defects proved necessary (URL reflects view state; deletes define cascade/orphan policy; empty/loading/error states; chevron alignment; double-submit guards...). Patterns become spec ACs by ID and carry copy-ready smoke recipes. Do NOT use for process/lifecycle questions (FLOW_RULES owns those), for stack-specific HOW guidance (CLI skills like app-ui-design own that), or to gate semantically by regex.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: "3.19"
risk_level: low
invocation: automatic
expected_outputs:
  - spec ACs citing applicable QP IDs (via requirements-specification)
  - design-brief QP citations (via implementation-planning)
  - S<n> smoke prompts copied from pattern Verify recipes
  - review findings citing QP IDs
related_workflows:
  - eight-phase-flow.md
  - smoke-verification.md
hook_dependencies:
  - none
---

# App Quality Patterns (QP library)

> **Style:** Mode-B-lite router. The patterns live in `references/<category>.md` — load ONLY the categories the feature touches. Each pattern: ID · Trigger · Requirement · Verify (copy-ready smoke recipe) · Anti-pattern.

## Purpose

Cross-project behavioral "definition of done" requirements that LLM-built apps repeatedly miss. They are not stack guidance (CLI skills own HOW) and not process rules (FLOW_RULES owns those) — they are WHAT must be true of the built feature. Distilled from recurring consumer-project defects; the library grows one table row at a time.

## Category index (load on trigger match)

| Category | File | Load when the feature involves | IDs |
|---|---|---|---|
| State & navigation | `references/state-and-navigation.md` | views with filters / search / sort / pagination / tabs / reports / deep links / browser navigation | QP-01..QP-04 |
| Data integrity | `references/data-integrity.md` | create / update / delete flows, related records, caching, retries | QP-10..QP-14 |
| UI polish | `references/ui-polish.md` | any user-facing UI: lists, forms, dropdowns, dates | QP-20..QP-24 |

## Integration contract (how patterns reach the lifecycle)

| Phase | What happens | Owner |
|---|---|---|
| Specify | `requirements-specification` scans this index; every matching pattern becomes a spec **AC citing the QP ID** (e.g., "AC4 — filter/report state encoded in URL; refresh restores exact view (QP-01)"). The AC then flows through tasks → gate → smoke → review on the existing machinery — no new gates. | PO |
| Plan | design brief lists the applicable QP IDs (one line) | PO |
| Implement | the AI Developer reads the cited reference category before building the touching surface | AI Developer |
| Gate/Smoke | the pattern's **Verify** line is a copy-ready S<n> smoke recipe | PO defines, Deploy executes |
| Review | `code-review` checks QP-cited ACs were honored (semantic, by reading) | reviewer |

## Growth rule

A defect observed across ≥2 projects (or once with clear generality) → add ONE row to the matching category file (new category file only when none fits) via `skill-authoring`; ship in the next release. Project-specific patterns go in that project's `docs/skills/`, never here. Keep rows dense — this library is loaded mid-spec.

## Anti-patterns

- Do NOT paste pattern bodies into specs/handoffs — cite the QP ID (FR-23; the AC text carries the requirement one line).
- Do NOT turn QPs into regex/lint gates — behavioral requirements verify at smoke/review (FR-25 lesson, inverse case).
- Do NOT load all categories for every feature — the index exists to scope the read.
- Do NOT use QPs to override stack-specific CLI guidance — QP says WHAT, CLI skills say HOW.

## Clean-room note

Original Fusebase Flow content. The patterns codify widely-known web/app engineering practice observed failing in LLM-generated apps; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
