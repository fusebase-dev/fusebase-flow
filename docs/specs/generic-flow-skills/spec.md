# Spec — generic-flow-skills

**Status:** DONE
**Created:** 2026-05-31
**Linked decisions:** C1..C5
**Deploy hash:** N/A — framework/template change, no production deploy
**Closure:** FR-20 added; skills/zoom-out, skills/phase-audit, skills/git-history-diagnostic created; skill-authoring + design-discovery-ideation extended; mirrored (16 canonical / 32 manifest). Verified: preflight 0/0, run-tests 14/14, health HEALTHY 16/16, mirror drift 0. Released as VERSION 3.3.0.

## Problem

Gap analysis of `internal/FuseBase positioning raw dump.txt` surfaced AI-development failure modes FuseBase Flow does not yet address. The subset that needs **no user input** (generic engines, deliverable now) is: patch-myopia / no zoom-out, reinventing the wheel (no domain-expert authoring path), no independent phase audit, no pre-build prototype gate, and regression archaeology limited to rollback. These ship first; input-dependent skills (north-star, client-vs-internal, product-docs, business-logic-guardian, product→apps) wait for the onboarding keystone.

## Why now

Operator instruction (2026-05-31): implement the generic skills first. They harden the framework for everyone immediately and are independent of the onboarding mechanism.

## In scope (the generic batch)

- **G3 — FR-20 + `zoom-out` skill:** anti-patch discipline. New always-on rule (FR-20) + a skill that operationalizes "step back, see the bigger picture before patching."
- **G4 — extend `skill-authoring`:** add a "domain-expert skill" authoring mode (create a skill that is expert in an industry/product area and knows market solutions, to avoid reinventing the wheel). No new skill file.
- **G7 — new `phase-audit` skill:** spawn an independent sub-agent to audit ALL slices of a completed phase (orchestrates `task-delegation` + `code-review`).
- **G8 — extend `design-discovery-ideation`:** add a "prototype-before-build" mode (ASCII/markdown mockup, optional HTML screen → operator feedback → then implement). No new skill file.
- **G10 — new `git-history-diagnostic` skill:** regression archaeology — compare commits to locate where a regression entered (complements `validation-and-qa` repro-before-fix).

## Out of scope

- All input-dependent skills: G2 north-star, G5 client-vs-internal, G6 product-docs-first, G9 business-logic-guardian, G11 product→apps.
- G1 project-onboarding (keystone slice).
- Any Column-B artifacts (north-star.md, product docs, regenerated constitution, etc.).
- Downstream/CLI provider skills (untouched).

## Acceptance criteria

1. **AC1 (C1)** — `FLOW_RULES.md` defines **FR-20** (zoom-out / anti-patch); the self-attestation line + status updated to FR-01..FR-20; amendment log entry added. Health-engine markers that grep FR ranges still pass.
2. **AC2 (C1)** — new canonical `skills/zoom-out/SKILL.md` operationalizes FR-20; mirrored to `.claude`/`.agents`; manifest refreshed.
3. **AC3 (C2)** — `skills/skill-authoring/SKILL.md` gains a "domain-expert skill" authoring section (when to make one, what it must contain, market-awareness, clean-room/no-competitor-names); mirrored.
4. **AC4 (C3)** — new canonical `skills/phase-audit/SKILL.md` (independent sub-agent audits all slices of a phase); mirrored; references `task-delegation` + `code-review`.
5. **AC5 (C4)** — `skills/design-discovery-ideation/SKILL.md` gains a "prototype-before-build" section (ASCII mockup / optional HTML prototype → feedback → build); mirrored.
6. **AC6 (C5)** — new canonical `skills/git-history-diagnostic/SKILL.md` (regression archaeology); mirrored; references `validation-and-qa`.
7. **AC7** — Flow skill count 14 → **16**; `audit/skill-mirror-manifest.txt` 28 → **32** lines (16 × 2 mirrors); `preflight.sh` 0/0; `run-tests.sh` PASS; health check HEALTHY; `mirror-skills.sh` drift 0.
8. **AC8** — No regression: existing FR-01..FR-19 text intact; no competitor names; clean-room note in every new/edited skill.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths | none (template repo) |
| Mixed-fleet | N/A (additive) |
| Migration | no migration; additive skills + one new FR |
| Auth model | N/A |
| Quality bar | new skills follow `templates/skill-template.md`; mirrors+manifest refreshed |

## Risks

- **FR-20 ripples** → self-attestation, status header, amendment log, and any health-engine FR-range reference must update together. Mitigation: C1 task updates FLOW_RULES + re-runs health check; FR-19→FR-20 is additive (engine greps presence of markers, not an exact max).
- **Overlap with existing skills** → G4/G8 are *extensions* not new skills (avoids sprawl); G7/G10 verified non-duplicative (orchestration + diagnosis niches).
- **Mirror drift** → each task runs `mirror-skills.sh` + preflight before commit.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| FR-20 or skill-only for G3? | FR-20 + skill (operator: go with recommendations) | 2026-05-31 |
| G4/G8 new vs extend? | extend skill-authoring + design-discovery-ideation | 2026-05-31 |
| Batch shape? | one slice, per-skill tasks | 2026-05-31 |

## Related

- `docs/specs/generic-flow-skills/decisions.md`
- `internal/2026-05-31-project-optimization-backlog.md` (source; local-only)
