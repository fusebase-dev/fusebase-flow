# Spec — onboarding-keystone

**Status:** DONE
**Created:** 2026-05-31
**Linked decisions:** D1..D9
**Deploy hash:** N/A — framework/template change
**Closure:** project-onboarding + north-star skills, /onboard + /product-owner commands, templates/north-star.md, AGENTS "Active project context", session_start.py scan all shipped; mirrored 19 canonical / 38 manifest. Verified preflight 0/0, run-tests PASS, health HEALTHY, mirror drift 0, plugin validate clean, absent-by-default confirmed. Released VERSION 3.4.0.

## Problem

Input-dependent skills (north-star, client-vs-internal, product-docs, business-logic-guardian, product→apps) need the user's project vision to function, but Flow has no mechanism to (a) capture that vision, or (b) discover the resulting artifacts in a fresh, memory-less session — especially across surfaces where hooks don't run (Codex/Cursor/Copilot/Gemini). Without this keystone, those skills can't ship usefully.

## Why now

Operator instruction (2026-05-31): proceed with implementation. The generic skills (v3.3.0) are done; this keystone unlocks the input-dependent batch.

## In scope (v1)

- **G1 `project-onboarding` skill** — PO-owned interviewer: discovery questions → writes `docs/north-star.md` (+ fills AGENTS project-values, ingests user research). Re-runnable. Absent-by-default (creates nothing unless run).
- **G2 `north-star` skill** — flagship artifact-gated skill: reads `docs/north-star.md` if present, steers every task/fix toward it; silent no-op if absent.
- **3-layer universal discovery (D7):** AGENTS.md "Active project context" instruction (+ mirrors); `session_start.py` scan; per-skill existence-guard.
- **`/onboard` + `/product-owner` slash commands** (`.claude/commands/`).
- **`templates/north-star.md`** scaffold (what onboarding writes).
- Version → 3.4.0; changelog; release notes.

## Out of scope

- G5 client-vs-internal, G6 product-docs-first, G9 business-logic-guardian, G11 product→apps (follow-up slice; identical pattern).
- Regenerating `docs/constitution.md` (D1 — stays Flow-owned).
- Checksum change-detection (D8 — presence + last_updated only).
- Domain-expert skill files (authoring mode already in skill-authoring v3.3.0; project-local output).

## Acceptance criteria

1. **AC1 (G1)** — `skills/project-onboarding/SKILL.md`: PO-owned; runs a chat-text discovery interview (FR-19); writes `docs/north-star.md` from `templates/north-star.md`; fills AGENTS project-values; ingests `docs/**/research/` if present; re-runnable; creates nothing without operator content. Mirrored.
2. **AC2 (G2)** — `skills/north-star/SKILL.md`: **first step = existence check** on `docs/north-star.md`; absent → silent no-op, never auto-create; present → steer tasks/fixes + flag drift; description gated so it doesn't fire spuriously when absent. Mirrored.
3. **AC3 (discovery L1)** — `AGENTS.md` gains "## Active project context — read first" telling every agent to check for project artifacts at session start; mirrored to CLAUDE.md/GEMINI.md (+ cursor/copilot where the baseline is referenced).
4. **AC4 (discovery L2)** — `hooks/handlers/session_start.py` scans for known artifacts (glob `docs/north-star.md`, `docs/*/product.md`) and surfaces them; hook-off changes nothing (Layers 1+3 cover it).
5. **AC5 (discovery L3)** — the existence-guard pattern (AC2) is the universal floor; documented as the required pattern for all input-dependent skills.
6. **AC6 (commands)** — `.claude/commands/onboard.md` + `.claude/commands/product-owner.md` exist and launch the right skill/agent.
7. **AC7 (template)** — `templates/north-star.md` with `last_updated` frontmatter + sections (vision, audience, in/out scope, success, constraints).
8. **AC8** — VERSION 3.4.0; CHANGELOG + `docs/release-notes/v3.4.md`.
9. **AC9** — preflight 0/0; run-tests PASS; health HEALTHY; mirror drift 0; no competitor names; absent-by-default verified (fresh clone has no `docs/north-star.md`).

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed | none (template repo) |
| Mixed-fleet | N/A |
| Migration | no migration; additive |
| Auth model | N/A |
| Quality bar | skills per template; mirrors+manifest refreshed; hook change additive |

## Risks

- **session_start.py regression** → change is additive (scan + surface only); hook tests must still pass. If risk, keep scan read-only and non-blocking.
- **north-star skill firing when absent** → description explicitly gates on artifact presence/explicit ask; first body step is existence check.
- **AGENTS.md edit near health markers** → add a NEW section; do not touch the `## Fusebase Flow — workflow lifecycle overlay` / baseline marker lines the engine greps.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Constitution regenerate? | No — stays Flow-owned; vision → north-star.md (D1) | 2026-05-31 |
| Hook universal? | No — 3-layer hook-independent design (D7) | 2026-05-31 |
| Build all input-skills now? | No — keystone + north-star v1, rest follow-up (D9) | 2026-05-31 |

## Related

- `docs/specs/onboarding-keystone/decisions.md`
- `internal/2026-05-31-project-optimization-backlog.md` (source; local-only)
