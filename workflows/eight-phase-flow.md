# Workflow: eight-phase-flow

> **Style:** Mode-B-lite. The canonical end-to-end ticket lifecycle (the **Full lane**).

## Lane selection (FR-21 — do this first, at Specify)

Before Phase 1, classify the ticket **Full** or **Lightweight** using the eligibility gate in `flow-skills/lightweight-lane/SKILL.md`.

- **Lightweight** (small + reversible + security-neutral + mechanically-verifiable + no decision needed + root cause known) → take `workflows/lightweight-lane.md` instead of the eight phases below: one change-note, one build→verify→deploy agent pass, plain operator go-ahead. The safety floor (live proof, explicit go-ahead, FR-07, rollback, one commit + SHA) is kept.
- **Full** (anything risky/uncertain, or any doubt) → the eight phases below.

In doubt → Full. If a Lightweight change turns non-trivial mid-flight, STOP and promote to Full (`flow-skills/lightweight-lane/SKILL.md` → "Mid-flight promotion").

## Phases (Full lane)

| # | Phase | Producer | Output | Skill / workflow |
|---|---|---|---|---|
| 1 | Specify | Product Owner | `docs/backlog/<slug>/README.md` (filing) OR `docs/specs/<slug>/spec.md` (DRAFT) | `requirements-specification` skill |
| 2 | Clarify | Product Owner ↔ operator | `docs/specs/<slug>/clarify-conversation.md` | `requirements-specification` skill |
| 3 | Plan | Product Owner | `docs/specs/<slug>/spec.md` filled out | `requirements-specification` skill |
| 4 | Decisions | Product Owner ↔ operator | `docs/specs/<slug>/decisions.md` (LOCKED after operator confirms) | `implementation-planning` skill |
| 5 | Tasks | Product Owner | `docs/specs/<slug>/tasks.md` (T-numbered chain) | `implementation-planning` skill |
| 6 | Verify | Product Owner → AI Developer → Product Owner | `docs/specs/<slug>/verification-gate.md` + gate report | `implementation-planning` + `smoke-testing` (draft gate) → `validation-and-qa` (verifies) |
| 7 | Implement | AI Developer (separate session) | task chain commits | `workflows/greenlight-implement.md` handoff |
| 8 | Deploy | AI Developer (separate session) → Product Owner | deploy hash + probe results + spec DRAFT→DONE | `release-deploy-reporting` skill + `workflows/greenlight-deploy.md` handoff |

## Phase transitions

```
Specify → Clarify → Plan → Decisions → Tasks → Verify → Implement → Deploy → DONE
```

Each transition has a state-announcement footer update. The operator can redirect a transition explicitly ("redirect <Letter><n>", "park ticket", "split into two") at any point.

## Cross-cutting workflows that may fire mid-phase

| Workflow | Fires when |
|---|---|
| `architect-escalation.md` | Investigation surface > 10 files / cross-cutting refactor / platform blocker suspected |
| `knowledge-curation.md` | After deploy or mid-investigation when triggers fire (see FR-15) |
| `git-workflow.md` | Pre-task checkpoint, per-commit, pre-deploy verification |
| `smoke-verification.md` | When `verification-gate.md` specifies numbered smoke prompts; execute with `smoke-testing` |

## Role hand-offs across sessions

| From | To | Handoff file |
|---|---|---|
| Product Owner | Architect (escalation) | `docs/handoff/<date>-<slug>-architect.md` |
| Product Owner | AI Developer | `docs/handoff/<date>-<slug>-implement.md` |
| Product Owner | Deploy phase | `docs/handoff/<date>-<slug>-deploy.md` |

Handoffs are saved to disk BEFORE being shown in chat (FR-04).

## Failure recovery

| Failure | Recovery |
|---|---|
| AI Developer reports gate failure | `validation-and-qa` reports specifics; operator decides redirect (revise spec/decisions) or fix-forward (file follow-up task) |
| Deploy probe fails | Per FR-DP-4 / `greenlight-deploy.md`: do not flip spec DONE; surface rollback (`git revert`) or fix-forward; operator decides |
| Constitution invariant violated mid-implementation | STOP; redirect via `decisions.md` update OR amend project-specific rules in `AGENTS.md` |

## Related

- `workflows/lightweight-lane.md` — the Lightweight-lane variant (FR-21) for small/reversible changes
- `flow-skills/lightweight-lane/SKILL.md` — the eligibility gate + change-note + one-pass procedure
- `FLOW_RULES.md` — the rules that govern each phase (FR-21 governs lane selection)
- All skills in `skills/`
- All other workflows in `workflows/`
