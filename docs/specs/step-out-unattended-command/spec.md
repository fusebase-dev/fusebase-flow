# Outcome — step-out-unattended-command

**Status:** DONE (local commit; not released)
**Process:** `docs/maintainer-execution.md` § One outcome, one implementation pass — one record, no spec/decisions/tasks/gate bundle.
**Baseline:** v5.3 @ `fcfd907`
**Task:** T113 (next free T-number; live record is git history, max was T112 @ `test(T112)`)
**Source:** operator working text `C:/tmp/step-out-source.md`; packaging plan by independent review (GPT-6 Astra), `C:/tmp/step-out-plan-out.md:5273-5459`.

## Scope

Add `/step-out`: a scheduling-only command for an explicit operator absence. It continues every authorized, unblocked slice, records the invocation grant into the run-ledger, and parks what it cannot clear. It opens no gate and grants no authority.

| Boundary | Disposition |
|---|---|
| Command body | `hooks/local/fusebase-flow-overlays/commands/step-out.md` → `.claude/commands/step-out.md` (recovery writer, `--surface command`) · Codex via existing `install-codex-prompts.sh` discovery |
| Reusable review discipline | `flow-skills/code-review` § Review depth and severity |
| Routing / dispatch / scheduling | `flow-skills/task-delegation` §§ Model routing · Correction ownership · Unattended scheduling |
| Model tiers | `policies/model-routing.yml`, five rows, all selectors `null` |
| NOT created | `step-out` skill · orchestrator agent · `docs/plan/` · second run ledger · `FLOW_RULES.md` edit · plugin `commands` field |

## Decision — bounded authorization (the load-bearing one)

The source text carried a blanket "full authorization for this product … stop only for something outside this product". That is not shippable as written. Locked semantics:

| Question | Resolution |
|---|---|
| What does the grant buy? | It satisfies the "operator asked" trigger and is recorded VERBATIM in `docs/tmp/handoff.md` § Constraints and Guardrails as evidence of the conversation — not an approval artifact. |
| Does it cross an unmet gate? | No. The owning role still satisfies the existing approval contract with its sanctioned writer. An unmet gate returns `BLOCKED-AT-<gate>`; the run continues on independent slices. Never synthesize a DP.6 phrase. |
| Is it inherited? | No — instruction-level, not a mechanical session-isolation guarantee. Existing artifacts remain reusable until `expires_at` (`policies/approval-policy.yml`); `/step-out` requires the CURRENT invocation grant before using them. A later session inherits the ledger, never the grant. |
| No grant supplied? | Record `none supplied`; do only already-authorized local work and safe verification; mark the blocked action and continue. |
| Unresolvable question? | Record question + evidence + options + affected dependents + clearing condition; park that chain only. Silence is never a decision. |

Model tier selects a model, never authority. Family diversity reduces correlated blind spots; it is never proof of correctness.

## Success / failure examples

| Input | Expected outcome |
|---|---|
| "I'm stepping out — finish the three staging slices, don't touch production." | `/step-out`; grant recorded verbatim; staging slices run; a production step returns `BLOCKED-AT-deploy-approval`; final report lists it with its clearing condition. |
| "Complete this end to end." (operator present, no absence phrase) | NOT `/step-out`. Ordinary attended work. |
| "Review the plan and tell me what you'd do." | NOT `/step-out`. Planning-only/read-only. |
| `policies/model-routing.yml` absent or a selector unreachable | Recorded fallback on the host model; run continues. Never a stop. |
| Only a same-family reviewer reachable | Review runs; reported as a same-family review. Independence is never claimed. |
| Delegate retry envelope exhausted | Record state, dispatch the next independent authorized slice, return when the clearing condition is met. No sleeping, no waiting. |
| Review round 2 leaves a BLOCKER | Stays blocked with its evidence. A successor agent does not reset the counter; the declaring actor does not extend its own bound. |

## FR-07

`policies/*.yml` is protected (`policies/protected-paths.yml:89`, `fusebase_flow_internals`). `policies/model-routing.yml` was committed under a digest-bound `write-bootstrap-approval.sh` artifact minted on the operator's authorization for this change, then consumed. `hooks/local/**` and `hooks/tests/**` are not protected paths.

## Verification

`mirror-skills.sh --check` · `verify-hook-manifest.sh --json` · `verify-managed-content-manifest.sh --json` · `preflight.sh` (§§3-5, 5d, 6b, 8) · `FF_ONLY=codex-parity,codex-plugin run-tests.sh` · `git diff --check`. Parity tests extended to cover `/step-out` itself: positive absence triggers, negative attended/read-only triggers, the three limits, missing grant, absent config, same-family fallback, blocked-dependency continuation, round-cap exhaustion, and all-null tier rows. No release profile, no version bump, no tag, no push.
