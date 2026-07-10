# Problem: gates still forced the operator to run terminal commands (FR-07 bootstrap, FR-25 adoption) — the deploy fix was not generalized

**Slug:** `gate-command-operator-friction`
**Filed:** 2026-07-10
**Severity:** high
**Status:** resolved
**Filed by:** operator (per FR-15) — follow-up after the deploy-only fix shipped

## Symptom

`deploy-approval-terminal-friction` (v4.3.0) fixed the deploy gate: the operator types `APPROVE-DEPLOY-NOW` in chat and the agent authors the artifacts + deploys. But the SAME "operator, go run these terminal commands" ritual was still baked into **every other gate**, so the friction the operator objected to persisted:

- **FR-25 module-size adoption** — the pre-commit BLOCK printed to stderr: *"operator-run … never agent-initiated: `bash hooks/local/check-module-size.sh --write-baseline`"*, then a hand-run `git commit … && … write-bootstrap-approval.sh --consume` chain (`hooks/shared/module_size.py`, `hooks/local/check-module-size.sh`, the `module-size-discipline` skill, both install guides, `policies/module-size.yml`).
- **FR-07 protected-path bootstrap approval** — `write-bootstrap-approval.sh`'s header said *"OPERATOR-DRIVEN … the operator runs them"*, and `upgrade.sh` / `post-fusebase-update.sh` printed the `mint → git commit → --consume` chain as operator "recommended next steps".
- **FR-12 command gate** — `command_policy.py`'s deny reason said *"Author one with `bash hooks/local/approve-local.sh …`"* with no "the agent does this" framing, reading as an operator instruction.

Operator verdict: *"you didn't fully remove these gates that force users to write some kind of gate commands in terminal. The maximum is Approve Deploy command in LLM chat as it was before; besides that you need to remove those overcomplications."*

## Root cause

The v4.3.0 fix was scoped to the deploy carriers only. The underlying principle — *the operator authorizes in chat; the agent is the hands* — was never stated as a **cross-cutting rule**, so the FR-07 and FR-25 carriers kept their older "operator-run / never agent-initiated" wording. Same conflation as the deploy case (self-approval vs executing the operator's explicit authorization), just in the gates the first fix didn't touch.

## Why it matters

- A human who has clearly approved is still stopped by bookkeeping they don't understand — now on install/upgrade and on the first over-ceiling commit, the two moments a new consumer hits Flow earliest. Repeated friction erodes trust in the whole framework.

## Permanent fix (v4.3.2)

| Status | Detail |
|---|---|
| Shipped | **Generalized the deploy pattern into one governing rule — the Operator Gate Protocol** (`flow-skills/role-discipline/SKILL.md`, a shared protocol every role loads): the operator's only gate action is a chat decision; on that approval the AGENT runs every required command (mint FR-07 approval, run FR-25 `--write-baseline`, `git add`/`commit`, `--consume`, deploy). Reworded every FR-25 carrier (`module_size.py` BLOCK stderr + baseline header, `check-module-size.sh`, `module-size-discipline` SKILL, `merge-module-size-baseline.sh`, `policies/module-size.yml`, both install guides) and FR-07 carrier (`write-bootstrap-approval.sh` header, `upgrade.sh`, `post-fusebase-update.sh`) plus the FR-12 deny reason (`command_policy.py`) and the provider security rules (`.cursor`, `.github/instructions`) from "operator-run / never agent-initiated" to "agent runs it on the operator's chat go-ahead — the operator types no command." |
| Preserved | **Enforcement backstops unchanged (mechanical safety, not operator rituals):** the git-hook FR-07 protected-path BLOCK, the §2 secret scan, and the `--no-verify` deny all still fire. The safety invariant is intact — minting/adopting/authoring with NO operator authorization, or on the agent's own initiative to dodge a block, is self-approval and remains forbidden. |

## Recurrence triggers (so future sessions recognize this)

- A hook prints "operator-run" / "never agent-initiated" and directs the human to a `bash hooks/local/…` command as a gate step.
- The agent tells the operator to run `--write-baseline`, `write-bootstrap-approval.sh`, `approve-local.sh`, `git commit`, or `--consume` after the operator already OK'd the action in chat.
- A NEW gate is added whose remedy text addresses the operator instead of the agent.

## Guardrail (the lesson)

There is exactly ONE human gate keystroke that stays a keystroke: the deploy authorization typed in chat (DP.6 phrase / DP.12 go-ahead). Every other gate is *authorized in chat, executed by the agent*. When adding or editing any gate, write its remedy for the **agent** ("on the operator's go-ahead the agent runs …"), never for the operator ("operator, run …"). Don't overcomplicate the human's path.

## Related

- `docs/problem-catalog/deploy-approval-terminal-friction/problem.md` — the deploy-only precursor this generalizes
- `flow-skills/role-discipline/SKILL.md` § Operator Gate Protocol — the governing rule
- FR-12 · FR-07 · FR-25 (`FLOW_RULES.md`) · `flow-skills/role-discipline/references/deploy.md` (DP.1/DP.6/DP.12 — the reference pattern)
