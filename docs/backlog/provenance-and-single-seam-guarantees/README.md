# provenance-and-single-seam-guarantees

**Status:** parked
**Filed:** 2026-07-30
**Source:** cross-product. Lessons extracted from a **Paperclip** host report (`paperclip+hermes-v1/docs/upstream-reports/2026-07-25-paperclip-host-findings.md`, findings H5/H9). That report is not about Flow and asks nothing of Flow; these three lessons are the transferable part.
**Severity:** medium — each is a guarantee Flow currently states more strongly than it enforces

## Why this exists

Three defect classes in that report are ones Flow has already hit, is currently deciding about, or would hit next. Filing them together because they share one shape: **a guarantee pinned to a single seam, or to an identity the system cannot actually distinguish.**

## L1 — "operator vs agent" is not distinguishable from provenance we record

Paperclip's `getActorInfo` returns `actorType: "user"` for a board key **and** a human session alike, and `activity_log` never persists the discriminator — so a reader of the audit trail cannot tell an operator's cancel from a script's. Their conclusion: every "operator" row is in fact only "not-an-agent".

**Flow's position is the same, and Flow already says so.** Decision K3 (`docs/specs/approval-binding-and-upgrade-classification/decisions.md`) rules that `approved_by` is audit metadata, never authenticated authority, because the agent and operator write as the same OS principal. The Paperclip report is independent confirmation that this is a *platform-class* problem, not a Flow shortcut.

**What is still worth doing in Flow:** nothing that claims to authenticate. But the *inverse* is cheap and honest — make the artifact record what it actually knows (`created_at` is landing in `upgrade-source-integrity-and-observability` T5) and never let a downstream reader infer more. Audit `hooks/shared/audit_logger.py` and the health-check approval inventory for any place that implies an approval was operator-authored.

## L2 — Do not pin a guarantee to one seam without enumerating every writer

Paperclip shipped a status-authority guard on `issueService.update`, assuming it was the single funnel every status write passes. It was not: `checkout` and `release` wrote `status` directly and never reached the checkpoint, so their own r2 shipped the guarantee **broken** and they found it only on adversarial review. Their remediation was an audit of 57 builder sites, 3 raw-SQL sites and 47 callers.

**Flow has made this exact mistake.** `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` records that the v3.30.5 fail-closed sweep hardened `path_policy.py`, the pre-commit hook and the secret scanner — and **skipped `command_policy.py`**, leaving the same class live in a missed carrier. `docs/backlog/approval-binding-omits-head/` is a second instance: binding was pinned to the command string and not to the change.

**Action:** before any future ticket claims a gate-wide property, enumerate every carrier of that property and give each an explicit disposition. `hooks/local/rule-inventory.sh` may be the right home for a mechanical carrier census. Writers of protected paths are still un-enumerated. The `state/approvals/**` census is DONE below.

### Census A — readers of `state/approvals/**` (AC13, done 2026-08-12, T2 `consumer-escalation-v480`)

Property claimed by T2: *the deploy gate is unchanged; T2 adds committed evidence only.* Every reader therefore needs an explicit "unchanged" or "changed" disposition — an unlisted reader is how L2's defect class recurs.

| Carrier | Role | Disposition |
|---|---|---|
| `hooks/shared/approval_artifact.py` | canonical loader/judge (`evaluate_artifact`, `Verdict`) | UNCHANGED. The receipt emitter calls it rather than re-implementing validation, so there is still one judge. |
| `hooks/shared/command_policy.py` | pre-deploy command gate | UNCHANGED. Still checks schema/action/repo/command/expiry on the live artifact before deploy. |
| `hooks/shared/path_policy.py` | protected-path exception gate | UNCHANGED. |
| `hooks/handlers/permission_request.py` | host permission decision | UNCHANGED (delegates to `command_policy.evaluate`; no direct read). |
| `hooks/local/lib/active-approvals.sh` | health-check active-artifact/deferral discovery | UNCHANGED. |
| `hooks/local/lib/approval_inventory.py` | `approve-local.sh --inventory` strict verdict report | UNCHANGED. |
| `hooks/local/fusebase-flow-health-check.sh` | `health_check_deferral-*` consumption | UNCHANGED. |
| `hooks/local/approve-local.sh` | writer + post-write re-read verification | CHANGED (dispatch only): `--receipt` as first argument execs the emitter. Writing/validation logic untouched. |
| `hooks/local/write-bootstrap-approval.sh` | single-use digest-bound writer | UNCHANGED. |
| `hooks/local/lib/approval-receipt.sh` | NEW reader | Emits/verifies the `fusebase-flow/deploy-approval-receipt/v1` receipt. **Authorizes nothing** — it reads the artifact once, digests and validates the same bytes, and prints evidence. No gate consumes its output. |

### Census B — writers of committed output that cite approval evidence (AC13)

Distinction the census enforces: an **evidence citation** ("this deploy was authorized — see `<local path>`") is banned in committed output, because the path is gitignored and dangles on a fresh clone. An **instruction** naming the file to author, or a **requirement** statement, keeps the path — the path is the target, not the proof.

| Writer | Kind | Disposition |
|---|---|---|
| `templates/deploy-report.md` | evidence | CHANGED. Header citation + relay-block citation replaced by the receipt (§ 1a) + digest/verdict/expiry in the relay block. Zero local paths remain. |
| `templates/gate-report.md` | — | NO CHANGE, verified: it cites no approval artifact, path, or expiry. It is a pre-deploy gate report; the receipt belongs to the deploy report. |
| `templates/handoff-deploy.md` | instruction | RETAINED. Names the path the Deploy session must author on the DP.6 phrase. |
| `templates/tasks.md` | requirement | RETAINED. States the FR-12 pre-deploy requirement. |
| `flow-skills/release-deploy-reporting/SKILL.md` | instruction | RETAINED. Tells the Deploy session which artifacts to author; produces no committed evidence itself. |
| `flow-skills/role-discipline/references/deploy.md` · `workflows/greenlight-deploy.md` · agent mirrors | instruction | RETAINED. Same reason. |
| `policies/gate-contracts.yml: deploy_report` | contract | DEFERRED — protected path, outside the T2 target list. Adding an `approval_receipt` required field would make the receipt machine-required, not just template-carried. Follow-up ticket. |
| `policies/gate-contracts.yml: security_review_report.approvals_required.artifact_path` | requirement | RETAINED. Pre-deploy "where the artifact would land", not post-hoc evidence. |
| Historical committed reports (e.g. `docs/handoff/2026-06-06-…-deploy.md`) | evidence | NOT REWRITTEN. Past records stay as shipped; git history is the audit trail (FR-18). The contract binds new reports. |

**Not claimed:** the receipt does not authenticate the operator (K3 stands) and cannot prove the artifact was not fabricated by whoever ran the deploy. It is evidence that *a* validated approval existed at `observed_at` and what it bound.

## L3 — A green aggregate that hides a missing component

Paperclip's loader logs `loadAll complete {total:1, succeeded:1, failed:0}` while an installed plugin is silently skipped, and the container health check keeps reporting `healthy`. A deploy passes every byte-level check and lands on an engine that is not running.

**Flow's catalogued equivalent:** `docs/problem-catalog/live-enforcement-inertness/problem.md` — hooks passed every test while being structurally inert in production, because the fixtures fabricated an event shape the host never sends. Same shape: the aggregate says fine, the component is absent.

**Action:** treat "N/N PASS" and "HEALTHY" as claims about *what was measured*, not about what exists. Where a count is emitted, assert the denominator is the expected population — Flow already does this in one place (`run_hook_tests.py`'s `EXPECTED_HANDLER_FIXTURES`) and that guard is the pattern to spread, not an anomaly.

## Explicitly NOT in scope

- Any Paperclip fix. Different product, different repo, no access. H1–H9 belong to the Paperclip team.
- Any attempt to authenticate operator identity in Flow — ruled out by K3 as unenforceable under the current host model, and nothing in the Paperclip report changes that.

## Related

- `docs/specs/approval-binding-and-upgrade-classification/decisions.md` K3 (trust model stated, not faked)
- `docs/problem-catalog/approval-gate-unbound-and-fail-open/problem.md` (L2's Flow instance)
- `docs/problem-catalog/live-enforcement-inertness/problem.md` (L3's Flow instance)
- `docs/backlog/approval-single-use-consumption/` · `docs/backlog/approval-binding-omits-head/`
