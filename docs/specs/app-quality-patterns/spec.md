# Spec — app-quality-patterns (v3.19.0)

**Status:** DONE (shipped 2026-06-11, framework v3.19.0, tag `v3.19.0`)
**Tier:** 3 · **Lane:** Full (new canonical skill + 4 skill-integration edits)
**Deploy hash:** `8174da0`. Independent pre-ship review: 12/12 seeds sound, 1 count blocker + nits fixed, +2 reviewer patterns (QP-14/QP-24 — final library 14 patterns). All gates green.

## Problem

Recurring behavioral defects across consumer projects (operator-observed): view state not encoded in URL (refresh/share loses filters/reports), UI polish defects (chevron misalignment), deletes leaving orphaned records. LLMs know these requirements but don't apply them unless they're in context at the right lifecycle moment. No Flow surface carries cross-project behavioral quality requirements today; the list will grow.

## Decisions (locked)

| ID | Decision | Rejected |
|---|---|---|
| Q1 | New 29th canonical skill `flow-skills/app-quality-patterns/` = thin router SKILL.md + `references/<category>.md` library (lazy-load; same pattern as role-discipline/communication references). Patterns are ID'd (QP-01..) with: Trigger · Requirement · Verify (concrete smoke recipe) · Anti-pattern. | Inline in requirements-specification (bloats every spec session; can't grow); always-on digest line (feature-domain, not write-time-universal — token-audit lesson); deterministic gate (behavioral requirements aren't regex-able — FR-25 lesson). |
| Q2 | **Enforcement = AC-injection**: `requirements-specification` scans the category index; matching patterns become spec ACs by ID. ACs then flow through the EXISTING machinery (tasks → gate → smoke → review) — no new gates. Reinforced: `implementation-planning` design brief cites QP IDs; `code-review` one dimension line; `smoke-testing` notes QP verify-recipes are copy-ready S<n> sources. | New hook/gate (semantic); review-only delivery (misses build time). |
| Q3 | Seed 12 patterns / 3 categories: state-and-navigation (QP-01..04), data-integrity (QP-10..13), ui-polish (QP-20..23) — incl. the 3 operator-observed (URL-state, orphaned deletes, chevron alignment). | Seed-3-only (structure wouldn't earn its keep). |
| Q4 | Growth: new pattern = one table row (+ category file if new) via `skill-authoring`/knowledge-curation route; upstream via normal releases; project-specific patterns live in the project's `docs/skills/`, never in canonical. Boundary: CLI skills (`app-ui-design` etc.) own HOW (stack specifics); QP owns WHAT must be true (behavior). | Editing CLI-owned skills (ownership violation). |

## ACs

1. AC1 — Skill + 3 reference files exist, mirrored (incl. references), manifest updated; preflight frontmatter check passes.
2. AC2 — 12 seeded patterns each carry Trigger/Requirement/Verify/Anti-pattern; the 3 operator examples present (QP-01 URL-state, QP-10 delete-cascade/orphans, QP-20 chevron alignment).
3. AC3 — `requirements-specification` has the QP scan→AC-injection step; `implementation-planning` design-brief line; `code-review` dimension line; `smoke-testing` recipe note. All pointer-style (no pattern bodies duplicated).
4. AC4 — Counts updated repo-wide: 29 skills, 58 = 29×2 SKILL mirrors, 76 mirrored files (58 SKILL.md + 18 references), catalog rows (README/AGENTS overlay), compatibility/audit/source-map/cli-edition/PUBLISHING/ROADMAP.
5. AC5 — preflight 0/0; run-tests 24/24; `--all` green; sweep clean; overlay inline re-spliced byte-identical after canonical list edit.

## Out of scope

Retroactive QP audits of existing consumer apps (project-local tickets); CLI skill edits; deterministic QP gates.

## Related

Precedent: comment-policy (carrier skill), FR-24 (delivery lessons), references/ lazy-load pattern. Operator examples: paperclip-class consumer projects.
