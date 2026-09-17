---
description: "Run /step-out for an explicit absence request: I'm stepping out, run this unattended, I'll be away, or complete end to end while I'm away. Continue authorized work within Flow gates. Do NOT use for ordinary attended work, planning-only/read-only requests, or complete end to end without an absence/unattended instruction. (FuseBase Flow)"
---

# /step-out

Scheduling only. Every lifecycle rule stays with its owner; this command adds no exception to any of them.

**Three limits. State them back before you start.**

- The grant you were invoked with is recorded **verbatim** into the run-ledger and dies with this run. A later session inherits the ledger, never the grant.
- The grant satisfies "the operator asked". It does **not** clear an unmet Flow gate — that slice returns `BLOCKED-AT-<gate>` and the run continues elsewhere.
- A question you cannot settle read-only is recorded with its options and clearing condition, and parks **only** its dependency chain. Silence is never a decision.

1. **Grant.** Record it verbatim (secrets masked) in `docs/tmp/handoff.md` § Constraints and Guardrails: run id · session · product · repo/environment · approved scope and actions · exclusions · expiry or end condition. Absent → `none supplied`, and do only already-authorized local work and safe verification. This record is evidence of the conversation, not an approval artifact — `policies/approval-policy.yml` § TRUST MODEL and the owning role's approval contract still gate every side effect.
2. **Ledger.** `flow-skills/handoff` `Mode: run-ledger` is the one running state; read it at every slice boundary and at final acceptance. No second notes file.
3. **Ceremony.** `flow-skills/lightweight-lane` · `flow-skills/implementation-planning` · `flow-skills/documentation-budget` decide the lane, the slice plan and which artifacts exist.
4. **Dispatch.** `flow-skills/task-delegation` §§ Model routing · Correction ownership · Unattended scheduling; bounds and retries are `flow-skills/liveness-discipline`.
5. **Review.** `flow-skills/code-review` § Review depth and severity; security findings route to `flow-skills/security-permissions-review`.
6. **Verify and deploy.** `flow-skills/validation-and-qa` · `flow-skills/smoke-testing` · `flow-skills/release-deploy-reporting`.
7. **Platform findings.** `workflows/knowledge-curation.md` decides whether one is worth an entry.
8. **Report.** Per slice and once at the end: done · verified live vs not · commits · deploy id + rollback · open items — plus the consolidated count of parked items and, for each, its clearing condition. Shape and budget: `task-delegation` § Delegated return shape.

Blocked is not finished. Name what you personally verified and what you did not.
