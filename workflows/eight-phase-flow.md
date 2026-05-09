# Workflow: eight-phase-flow

> **Style:** Mode-B-lite. The canonical end-to-end ticket lifecycle.

## Phases

| # | Phase | Producer | Output | Skill / workflow |
|---|---|---|---|---|
| 1 | Specify | Product Owner | `docs/backlog/<slug>/README.md` (filing) OR `docs/specs/<slug>/spec.md` (DRAFT) | `requirements-specification` skill |
| 2 | Clarify | Product Owner ↔ operator | `docs/specs/<slug>/clarify-conversation.md` | `requirements-specification` skill |
| 3 | Plan | Product Owner | `docs/specs/<slug>/spec.md` filled out | `requirements-specification` skill |
| 4 | Decisions | Product Owner ↔ operator | `docs/specs/<slug>/decisions.md` (LOCKED after operator confirms) | `implementation-planning` skill |
| 5 | Tasks | Product Owner | `docs/specs/<slug>/tasks.md` (T-numbered chain) | `implementation-planning` skill |
| 6 | Verify | Product Owner → Implementer → Product Owner | `docs/specs/<slug>/verification-gate.md` + gate report | `implementation-planning` (drafts gate) → `validation-and-qa` (verifies) |
| 7 | Implement | Implementer (separate session) | task chain commits | `workflows/greenlight-implement.md` handoff |
| 8 | Deploy | Implementer (separate session) → Product Owner | deploy hash + probe results + spec DRAFT→DONE | `release-deploy-reporting` skill + `workflows/greenlight-deploy.md` handoff |

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
| `smoke-verification.md` | When `verification-gate.md` specifies numbered smoke prompts |

## Role hand-offs across sessions

| From | To | Handoff file |
|---|---|---|
| Product Owner | Architect (escalation) | `docs/handoff/<date>-<slug>-architect.md` |
| Product Owner | Implementer | `docs/handoff/<date>-<slug>-implement.md` |
| Product Owner | Deploy phase | `docs/handoff/<date>-<slug>-deploy.md` |

Handoffs are saved to disk BEFORE being shown in chat (FR-04).

## Failure recovery

| Failure | Recovery |
|---|---|
| Implementer reports gate failure | `validation-and-qa` reports specifics; operator decides redirect (revise spec/decisions) or fix-forward (file follow-up task) |
| Deploy probe fails | Per FR-DP-4 / `greenlight-deploy.md`: do not flip spec DONE; surface rollback (`git revert`) or fix-forward; operator decides |
| Constitution invariant violated mid-implementation | STOP; redirect via `decisions.md` update OR amend project-specific rules in `AGENTS.md` |

## Related

- `FLOW_RULES.md` — the rules that govern each phase
- All skills in `skills/`
- All other workflows in `workflows/`
