# Spec — input-dependent-skills

**Status:** DONE
**Created:** 2026-05-31
**Linked decisions:** E1..E4
**Deploy hash:** N/A — framework/template change
**Closure:** client-vs-internal, product-docs-first, business-logic-guardian, product-apps-decomposition skills + templates/audience.md + templates/product.md shipped; session_start scan extended; mirrored 23 canonical / 46 manifest. Verified preflight 0/0, run-tests PASS, health HEALTHY, mirror drift 0, plugin validate clean, absent-by-default confirmed. Released VERSION 3.5.0.

## Problem

The onboarding keystone (v3.4.0) proved the artifact-gated pattern with `north-star`. The remaining input-dependent skills from the gap analysis still need shipping: they are complete engines that stay dormant until their project artifact exists.

## Why now

Operator instruction (2026-05-31): proceed. These are mechanical clones of the verified `north-star` pattern.

## In scope

- **G5 `client-vs-internal`** — optimizes surfaces differently (client-facing = simple; internal = robust). Reads `docs/audience.md` (B5).
- **G6 `product-docs-first`** — ingest research → design product docs per app before code. Reads/writes `docs/<app>/product.md` (B2).
- **G9 `business-logic-guardian`** — protect documented business logic during fixes. Reads `docs/<app>/business-logic.md` (B3; template already exists).
- **G11 `product-apps-decomposition`** — guide "a product is composed of focused apps" for reliability + token economy. Reads the apps breakdown in `docs/<app>/product.md` (B2).
- New templates: `templates/audience.md`, `templates/product.md`.
- `project-onboarding` updated to also offer/create these artifacts.
- VERSION → 3.5.0; changelog; release notes.

## Out of scope

- New FRs. Checksum change-detection (still presence + last_updated).
- Regenerating constitution.

## Acceptance criteria

1. **AC1 (G5)** — `skills/client-vs-internal/SKILL.md`: first step = existence check on `docs/audience.md`; absent → silent no-op; present → apply simple-for-client / robust-for-internal. Mirrored.
2. **AC2 (G6)** — `skills/product-docs-first/SKILL.md`: gated on `docs/<app>/product.md` (and operator research); guides design-docs-before-code; absent → no-op. Mirrored.
3. **AC3 (G9)** — `skills/business-logic-guardian/SKILL.md`: gated on `docs/<app>/business-logic.md`; protects documented logic during fixes (pairs with FR-20 zoom-out); absent → no-op. Mirrored.
4. **AC4 (G11)** — `skills/product-apps-decomposition/SKILL.md`: gated on a product breakdown in `docs/<app>/product.md`; guides splitting a product into focused apps; absent → generic guidance only. Mirrored.
5. **AC5** — `templates/audience.md` + `templates/product.md` created (with `last_updated` frontmatter + absent-by-default note).
6. **AC6** — `project-onboarding` references the new artifacts/templates (offer-once, never auto-create).
7. **AC7** — `session_start.py` already globs `docs/*/product.md`; extend scan to surface `docs/audience.md` too.
8. **AC8** — VERSION 3.5.0; CHANGELOG + `docs/release-notes/v3.5.md`; plugin manifest bumped.
9. **AC9** — Flow skills 19 → **23**; manifest 38 → **46**; preflight 0/0; run-tests PASS; health HEALTHY; mirror drift 0; absent-by-default verified; no competitor names.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed | none |
| Mixed-fleet | N/A |
| Migration | no migration; additive |
| Auth model | N/A |
| Quality bar | skills per template; mirrors+manifest refreshed |

## Risks

- **Skill firing when artifact absent** → every skill's description is gated + first body step is the existence check (proven in north-star).
- **session_start.py change** → additive scan only (one more glob/path); hook tests must still pass.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Same pattern as north-star? | Yes — artifact-gated, absent-by-default | 2026-05-31 |
| New artifacts? | `docs/audience.md`, `docs/<app>/product.md` (+ existing business-logic.md) | 2026-05-31 |

## Related

- `docs/specs/input-dependent-skills/decisions.md`
- `docs/specs/onboarding-keystone/` (the proven pattern)
- `internal/2026-05-31-project-optimization-backlog.md`
