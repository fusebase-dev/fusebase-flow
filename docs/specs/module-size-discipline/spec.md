# Spec — module-size-discipline (FR-25)

**Status:** LOCKED (operator-approved 2026-06-10, all recommended options)
**Created:** 2026-06-10
**Lands in:** framework v3.16.0
**Tier:** 4 (new always-on rule + policy + gate script + multi-skill + template) per FR-23
**Lane:** Full
**Linked decisions:** (none yet — drafted at Plan)
**Deploy hash:** (at DRAFT → DONE flip)

## Problem

Consumer report (paperclip+hermes-v1, 2026-06-10): source files accreted to 19,026 / 14,202 / 10,434 / 5,363 lines under full Flow discipline. Root cause is a structural blind spot, not a broken rule:

- Tasks say WHAT to build, never WHERE → implementer's path of least resistance is appending to the existing big file.
- Every gate (verification, smoke, code-review, phase-audit) is behavioral — none is structural.
- One-task-one-commit + FR-21 make mid-task extraction look like scope creep → no agent ever splits.
- Monolith = integral of N individually-reasonable diffs; no single diff is ever flagged.

Cost is framework-core: per FR-22/FR-24 audience principle, source is AI-read. A 19k-line file cannot be loaded in one pass — every future session pays degraded slice-reads on the hottest files.

## Why now

Second consumer-reported structural-debt class in two releases (FR-22 comments → v3.10–3.11; FR-23 doc bloat → v3.12). Same delivery arc: downstream feedback → upstream rule. Key asymmetry vs FR-22: line count is **objective and deterministic** — this write-time rule CAN be a gate, so Flow can ship a real safety net, not just steering prose.

## In scope

- **FR-25 (module-size ratchet)** row + implication in `FLOW_RULES.md`.
- **`policies/module-size.yml`** — `ceiling` (default: clarify Q-B), `source_globs`, `exempt_globs` (generated / vendored / data-as-code / lockfiles), `baseline` path, `enforcement: warn|block`.
- **Baseline + check script** (`hooks/local/`) — ratchet semantics: over-ceiling file may not grow past committed baseline; new files must be under ceiling; baseline only ratchets down automatically (raising requires operator exemption). Missing baseline → warn-only + generation instruction (adoption-safe on legacy repos).
- **Enforcement wiring** — git `pre-commit` fallback (always-on floor across all IDEs) + optional Claude Code hook wiring (clarify Q-C). Cross-platform (Windows git-bash) required.
- **Plan-time integration** — `implementation-planning` skill + `templates/tasks.md`: every task names target file(s); a task targeting an over-ceiling file must extract into a new module or carry a one-line exemption with reason.
- **FR-21 interplay clause** — extraction-to-satisfy-the-ratchet is in-scope for the task, NOT scope creep.
- **Review-time** — one `code-review` dimension line ("did this diff grow an over-ceiling file without extraction?").
- **FR-24 digest registration** — one pointer line in role-discipline's write-time discipline digest.
- Carrier home for full rule detail (clarify Q-E: new small skill vs policy+docs only).

## Out of scope

- Retroactive decomposition of any consumer's existing monoliths (project-local Full tickets; ratchet stops the bleeding without forced refactor).
- Project-specific exemption lists (downstream edits to their own `module-size.yml`).
- Single-file plugin bundle constraints / adding build steps (CLI-domain, project-local decisions).
- Any regex/lint gate for split QUALITY (seam-vs-mechanical is semantic → review-time only, mirroring FR-22's reasoning).

## Acceptance criteria

1. **AC1** — `FLOW_RULES.md` has FR-25 row + implication; Status bump + amendment entry; FR range swept to FR-01..FR-25.
2. **AC2** — `policies/module-size.yml` ships with documented defaults; check script enforces ratchet semantics (grow-blocked over ceiling, new-over-ceiling blocked, exempt globs honored, baseline-absent → warn).
3. **AC3** — git pre-commit fallback runs the check; deterministic fixture tests added to `hooks/tests/` (pass + fail + exempt + no-baseline cases).
4. **AC4** — `implementation-planning` + `templates/tasks.md` carry the target-file rule; FR-21 interplay clause present in FR-25 implication and `lightweight-lane` cross-ref.
5. **AC5** — `code-review` dimension line added; role-discipline digest registers FR-25 (one line, pointer only).
6. **AC6** — mirrors regenerated; version v3.16.0; `sync-version-strings.sh` swept.
7. **AC7** — preflight 0/0; run-tests all-pass (16 existing + new fixtures).

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths | none touched |
| Mixed-fleet considerations | gate lives in git fallback → works on all 5 surfaces; Claude hook wiring stays opt-in |
| Migration approach | no migration; baseline generation is additive + warn-first |
| Auth model | N/A |
| Quality bar | new hook-test fixtures; preflight + run-tests must pass |

## Risks

- **Mechanical-split gaming** (`utils2.ts`) — gate can't judge seam quality; mitigated by code-review dimension + gate message instructing responsibility-seam extraction.
- **Adoption friction on legacy repos** — over-ceiling files everywhere at install; mitigated by ratchet-only + warn-without-baseline.
- **Windows execution** — pre-commit is bash; must run under git-bash (existing precedent: current `hooks/git/` already does); add no new runtime deps.
- **Default ceiling wrong for a domain** — policy-configurable; exempt_globs for data-as-code.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Q-A scope | Full 3-layer package (gate + plan-time + steering) | 2026-06-10 |
| Q-B default ceiling | 800 lines (policy-configurable) | 2026-06-10 |
| Q-C enforcement floor | git pre-commit fallback (universal) + opt-in Claude Code hook wiring | 2026-06-10 |
| Q-D no-baseline behavior | warn-only + generation instruction; ratchet engages once baseline committed | 2026-06-10 |
| Q-E carrier home | new `module-size-discipline` skill (digest line points to it) | 2026-06-10 |

## Related

- `docs/specs/module-size-discipline/decisions.md` (after clarify)
- `docs/specs/module-size-discipline/tasks.md` (after decisions)
- Precedent: `docs/specs/write-time-discipline-delivery/spec.md` (FR-24), `docs/specs/comment-policy-fr22-write-time-delivery/` (FR-22 delivery)
