# Problem: the agent forced the operator to run terminal approval commands even after an explicit chat approval + DP.6 phrase

**Slug:** `deploy-approval-terminal-friction`
**Filed:** 2026-07-10
**Severity:** high
**Status:** resolved
**Filed by:** operator (per FR-15) — surfaced by consumer deploy sessions

## Symptom

An operator authorized a Full-lane production deploy in chat — typed the DP.6 magic phrase `APPROVE-DEPLOY-NOW`, then repeatedly said "you can run them yourself", "i approve, so you can run them" — and the agent still **refused to deploy**, insisting the operator personally run:

```
bash hooks/local/approve-local.sh production_deploy <slug> ...
bash hooks/local/approve-local.sh database_migration <slug> ...
bash hooks/local/approve-local.sh auth_or_permission_change <slug> ...
```

The agent's stated reason: *"I can't run commands that manufacture operator-only approval … that would be approving my own production migration — a circular gate forbidden by FR-12."* The operator's response — *"I don't understand what you need"* — is the whole failure: the human had unambiguously approved and was blocked by a ceremony that added nothing.

## Root cause

The agent **conflated two different things**:

1. **Self-approval** (correctly forbidden) — an agent AUTONOMOUSLY authorizing a deploy with NO operator authorization.
2. **Executing the operator's explicit authorization** (should be routine) — the operator gave the DP.6 phrase; the agent transcribing that decision into the approval artifact(s) is being the operator's hands, not approving its own work.

Three aggravating facts made the refusal pure over-conservatism:
- **The enforcement doesn't even check the author.** `command_policy.py` checks only the artifact filename + `expires_at`; `approve-local.sh` sets `approved_by` from `$USER`; `approval_authors` in `approval-policy.yml` is dead config no hook reads (see `docs/specs/ceremony-efficiency-middle-lane/spec.md`). So "the AI Developer may not author it" was never a technical gate — only skill-text discipline.
- **The Lightweight lane already lets the agent author it** — DP.12: `approve-local.sh lightweight_deploy <slug> 'ship it'` on a plain go-ahead. So the *stronger* Full-lane signal (a typed magic phrase) was held to a *stricter* authoring rule than the weaker Lightweight signal. Inconsistent.
- **DP.6 is the real trust anchor.** The framework already treats the operator typing `APPROVE-DEPLOY-NOW` as the authoritative production-cutover authorization. The separate "operator runs approve-local.sh" was a redundant second human action, not independent enforcement.

## Why it matters

- A human who has clearly approved is stopped by framework bookkeeping they don't understand — the exact opposite of the framework's job. Repeated friction erodes trust in the whole gate.

## Permanent fix (v4.3.0)

| Status | Detail |
|---|---|
| Shipped | **After the DP.6 phrase, the Deploy session AUTHORS every required approval artifact on the operator's behalf** (`production_deploy` + any `database_migration` / `auth_or_permission_change` / `protected_path_edit`) via `approve-local.sh`, then deploys — for ALL tickets, not just the reversible `dp1_waiver: eligible` fast-path. The operator's ONE action is typing the phrase. The agent PRESENTS the full scope in chat BEFORE the phrase so it is informed consent. Updated: `role-discipline/references/deploy.md` (DP.1 + refusal phrasing), `release-deploy-reporting/SKILL.md`, `agents/ai-developer/AGENT.md`, `workflows/greenlight-deploy.md`, `hooks/local/approve-local.sh` header. |
| Preserved | **The safety boundary is unchanged:** authoring an approval WITHOUT the operator's DP.6 phrase (Full) or plain go-ahead (Lightweight) is self-approval and remains forbidden. DP.6 itself, the scope presentation, DP.2 (FR-07 re-check), DP.10 (smoke evidence), DP.11 (no delegated deploy side effects) all stay. |

## Recurrence triggers (so future sessions recognize this)

- The agent asks the operator to run `approve-local.sh` after the operator already typed `APPROVE-DEPLOY-NOW` / said "you run it".
- "I would be approving my own deploy — circular gate / FR-12" cited to refuse an operator's explicit in-chat authorization.
- Operator says "I don't understand what you need" / "I approve, just do it".

## Guardrail (the lesson)

The deploy gate exists to ensure a **human deliberately authorized** the cutover — and the DP.6 typed phrase IS that authorization. Once it's given (with the scope presented), the agent does the mechanical bookkeeping; it must never make the operator run terminal commands to prove an approval they already gave in chat. Distinguish **self-approval** (no operator signal — forbidden) from **transcribing the operator's explicit signal** (routine). Don't overcomplicate the human's path.

## Related

- `flow-skills/role-discipline/references/deploy.md` (DP.1, DP.6, DP.12) · `hooks/local/approve-local.sh` · `policies/approval-policy.yml`
- `docs/specs/ceremony-efficiency-middle-lane/spec.md` — the analysis that `approval_authors` is dead config + the author is not enforced
- FR-12 (`FLOW_RULES.md`) — requires the artifact on disk; never mandated operator-run authoring
