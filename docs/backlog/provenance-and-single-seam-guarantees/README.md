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

**Action:** before any future ticket claims a gate-wide property, enumerate every carrier of that property and give each an explicit disposition. Candidate seams to enumerate now: every reader of `state/approvals/**` (currently `command_policy.py`, `path_policy.py`, `active-approvals.sh`, `approval_inventory.py`, `write-bootstrap-approval.sh`), and every writer of a protected path. `hooks/local/rule-inventory.sh` may be the right home for a mechanical carrier census.

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
