# Decisions — input-dependent-skills

**Letter prefix:** E
**Approval status:** Locked by operator ("proceed with your recommendations") on 2026-05-31
**Linked spec:** `docs/specs/input-dependent-skills/spec.md`

| ID | Title | Decision | Lock |
|---|---|---|---|
| E1 | Pattern | Clone the proven `north-star` artifact-gated pattern (existence-guard first; absent → silent no-op; never auto-create) | LOCKED |
| E2 | Artifacts | G5→`docs/audience.md`; G6/G11→`docs/<app>/product.md`; G9→`docs/<app>/business-logic.md` (existing template) | LOCKED |
| E3 | G11 form | A skill that gives generic decomposition guidance always, but steers to the product breakdown when present | LOCKED |
| E4 | Onboarding | `project-onboarding` offers these artifacts (offer-once), never auto-creates | LOCKED |

## E1. Reuse the proven pattern
north-star (v3.4.0) verified the artifact-gated mechanism end-to-end. These four reuse it verbatim — lowest risk, consistent behavior, graceful degradation guaranteed.

## E3. G11 is partly generic
"Break a product into focused apps" is useful generic guidance even with no artifact, so this skill degrades to generic advice (not full no-op) when `docs/<app>/product.md` is absent — but only *steers to the specific breakdown* when present. This is the one skill that is generic-with-enhancement rather than pure no-op.

## E4. Onboarding stays additive
`project-onboarding` may offer to capture audience / product docs (offer-once, FR-19) but never auto-creates them. Absent-by-default preserved.

## Lock confirmation
All E1..E4 LOCKED 2026-05-31 (operator delegated). Implementation authorized.
