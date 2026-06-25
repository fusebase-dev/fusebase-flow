# Workflow: lightweight-lane

> **Style:** Mode-B-lite. The FR-21 variant of the lifecycle for small / reversible / low-risk changes. One change-note, one agent pass, a plain operator go-ahead. The full safety floor is kept.

## When to run

Chosen at Specify when the eligibility gate in `flow-skills/lightweight-lane/SKILL.md` passes (ALL of): small implementation + single concern · reversible · mechanically-verifiable acceptance · no new security surface · no public-contract decision · root cause understood. **In doubt → Full lane** (`workflows/eight-phase-flow.md`).

## Procedure (single AI Developer session — no two-agent split)

1. **Confirm tier.** Re-check the eligibility gate. If any condition fails or there is doubt → STOP, use the Full lane.
2. **Pre-task checkpoint.** Git checkpoint per `workflows/git-discipline.md` (so revert is clean).
3. **Write the change-note** from `templates/change-note.md` (problem · change · verified · rollback · `change_tier: lightweight`). Inline in the commit body for the smallest changes, or `docs/changes/<date>-<slug>.md`.
4. **Make the change.** Single coherent concern. If scope grows past a couple files / surfaces a risk / needs a decision / reveals a deeper bug → STOP and promote (see below).
5. **Lint + typecheck** (FR-13).
6. **Build once.**
7. **Live-verify** — run the probe/measurement; apply the `validation-and-qa` 3-question empirical test to the acceptance criterion (did it run on a real input · observed vs expected · reproducible from the note). This is the safety floor; never skip it.
8. **Commit** — one commit (FR-03). Record the SHA in the change-note.
9. **FR-07 re-check** — `git diff` against `policies/protected-paths.yml`. Must be clean.
10. **Operator deploy go-ahead (FR-19, chat text).** Ask for an explicit plain go-ahead ("ship it" / "deploy it" / "go"). **Never auto-deploy.** No DP.6 magic phrase, no DP.1 hand-authored JSON, no separate deploy session. (Hook-wired projects: record the go-ahead with `bash hooks/local/approve-local.sh lightweight_deploy <slug> 'ship it'` — one command. Hooks are opt-in; in the default off setup the chat go-ahead is the gate.)
11. **Deploy** (exact command from `AGENTS.md`). Capture the deploy hash.
12. **Report in 1–3 lines:** what changed · live-proof result (observed vs expected) · deploy SHA/hash · one-line rollback.
13. **Record the tier** — `change_tier: lightweight` + the SHA live in the change-note/commit body (durable; git carries it). If the project keeps a consolidated ledger, append one line (`<date> · <slug> · lightweight · <SHA>`); its path is configurable (default `docs/changes/index.md`) and the file is opt-in — never assume a repo-root ledger.

## Self-attestation

The same role attestation as any AI Developer session (per `FLOW_RULES.md` § Self-attestation, FR-01..FR-27), naming the AI Developer role and `flow-skills/role-discipline/SKILL.md`. Add one line: "Running the Lightweight Lane (FR-21): one change-note, one build→verify→deploy pass, plain operator go-ahead; safety floor (live proof, explicit go-ahead, FR-07, rollback, one commit) kept; I will STOP and promote to Full if this turns non-trivial."

## Mid-flight promotion (mandatory)

Triggers, procedure, and the kept-vs-dropped safety floor are canonical in `flow-skills/lightweight-lane/SKILL.md` (§ Mid-flight promotion, § What LL KEEPS / DROPS). On any trigger: **STOP**, promote to Full, record the promotion.

## State announcement (every output)

```
---
📍 Phase: Lightweight (build→verify→deploy, single pass)
🎯 Ticket: <slug>
⏭️ Next: <step — e.g. "awaiting your go-ahead to deploy">
```

## Related

- `flow-skills/lightweight-lane/SKILL.md` — eligibility gate, change-note, promotion (single source of truth)
- `templates/change-note.md` — the LL artifact
- `workflows/eight-phase-flow.md` — the Full lane (lane selection happens there)
- `workflows/git-discipline.md` — pre-task checkpoint + per-commit discipline
- `flow-skills/validation-and-qa/SKILL.md` — live-proof / 3-question empirical test (LL mode)
- `flow-skills/release-deploy-reporting/SKILL.md` — LL deploy mode (plain go-ahead)
- `policies/approval-policy.yml` — `lightweight_deploy` (one-command stamp) vs `production_deploy`
- `policies/protected-paths.yml` — FR-07 worker-undisturbed list