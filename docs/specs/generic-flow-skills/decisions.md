# Decisions — generic-flow-skills

**Letter prefix:** C
**Approval status:** Locked by operator ("proceed with your recommendations") on 2026-05-31
**Linked spec:** `docs/specs/generic-flow-skills/spec.md`

| ID | Title | Decision | Lock |
|---|---|---|---|
| C1 | G3 enforcement | New **FR-20** + `zoom-out` skill | LOCKED |
| C2 | G4 form | **Extend** `skill-authoring` (domain-expert mode), not a new skill | LOCKED |
| C3 | G7 form | **New** `phase-audit` skill | LOCKED |
| C4 | G8 form | **Extend** `design-discovery-ideation` (prototype-before-build mode) | LOCKED |
| C5 | G10 form | **New** `git-history-diagnostic` skill | LOCKED |

## C1. G3 → FR-20 + zoom-out skill
**Reasoning:** Anti-patch/zoom-out is a behavioral default (like FR-17 forward-momentum), not occasional expertise; a skill alone won't fire reliably. FR-20 makes it always-on; the skill operationalizes it. FR-19→FR-20 is additive — the health engine greps for marker presence, not an exact max, so no engine break.
**Alternatives:** skill-only (rejected: won't reliably trigger); rule-only (rejected: no operational steps).
**Lock:** LOCKED

## C2. G4 → extend skill-authoring
**Reasoning:** `skill-authoring` already governs creating skills. A "domain-expert skill" is a *mode* of that, not a separate concern. Extending avoids skill sprawl (the template's own anti-pattern).
**Alternatives:** new `domain-expert` skill (rejected: duplicates skill-authoring's purpose).
**Lock:** LOCKED

## C3. G7 → new phase-audit skill
**Reasoning:** Independent multi-slice audit is a distinct orchestration (spawn sub-agent, examine every slice of a phase) not covered by `code-review` (single diff) or `task-delegation` (generic delegation). New skill that composes both.
**Alternatives:** extend code-review (rejected: code-review is single-diff scoped).
**Lock:** LOCKED

## C4. G8 → extend design-discovery-ideation
**Reasoning:** That skill already produces divergent options and mentions ASCII mockups. "Prototype-before-build" (mockup/HTML → feedback → build) is the same pre-lock visual-exploration family. Extend, don't duplicate.
**Alternatives:** new prototype skill (rejected: overlaps ideation).
**Lock:** LOCKED

## C5. G10 → new git-history-diagnostic skill
**Reasoning:** Regression archaeology (bisect-style commit comparison to locate where a regression entered) is distinct from `validation-and-qa` (repro-before-fix) and `git-workflow` (commit hygiene/rollback). New skill, references both.
**Alternatives:** extend validation-and-qa (rejected: different activity — locating vs reproducing).
**Lock:** LOCKED

## Lock confirmation
All C1..C5 LOCKED 2026-05-31 (operator delegated). Implementation authorized.
