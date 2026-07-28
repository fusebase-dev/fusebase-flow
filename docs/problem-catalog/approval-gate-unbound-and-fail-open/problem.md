# Problem: a fail-open defect class survived the sweep that believed it had closed it

**Slug:** `approval-gate-unbound-and-fail-open`
**Filed:** 2026-07-28
**Severity:** high
**Status:** resolved (`approval-binding-and-upgrade-classification`, v4.7.0)
**Filed by:** PO per FR-15

## Symptom

A consumer who had wired `PreToolUse` — the consumer actually relying on enforcement — reported that
the FR-12 command gate was replayable, and that a Flow upgrade had silently reverted their local
hardening of it. They measured **98** `production_deploy` artifacts on one project, **22** with no
`expires_at`, every one of them still authorizing deploys.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Place any `production_deploy-*.json` in `state/approvals/` with no `expires_at` | `evaluate("fusebase deploy")` returns `allow`, indefinitely |
| 2 | Give an artifact a body `action` unrelated to its filename | still `allow` — only the filename prefix was read |
| 3 | Introduce a typo in a `deny` pattern | the rule is silently skipped; the command falls through to `default: allow` |

Reproduces: 3/3 (file:line evidence in the originating Codex review; not re-reproduced during
implementation per FR-10, which only requires reproduction for undiagnosed reports).

## Root cause

The **v3.30.5 fail-closed sweep** (`security-check-fail-open-class`) hardened `path_policy.py`,
`hooks/git/pre-commit` and the secret scanner — and left `hooks/shared/command_policy.py`, a sibling
enforcement carrier, untouched. The same defect class therefore survived a remediation that believed
it was complete: unparsed expiry compared as a string (so missing = valid forever), approval bound to
nothing but a filename prefix, and `re.error` swallowed with `continue`.

`policies/approval-policy.yml` compounded it by documenting `approval_authors` as hook-enforced
operator-only authorship — a control no code implemented, contradicted twelve lines away in the same
file.

## Why it matters

- A security gate whose failure mode is **allow** is not a gate. Every defect above fails open.
- Documentation that describes an unimplemented control is worse than an absent control, because
  readers trust it and stop looking.
- The remediation-completeness failure is the reusable lesson: the sweep's own tests were green.

## Mitigation / workaround

Superseded by the permanent fix. For an installation still on ≤4.6.1:
`bash hooks/local/approve-local.sh --inventory` (4.7.0+) lists which artifacts a strict cutover
rejects; deleting expiry-less artifacts is safe and immediate.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | `approval-binding-and-upgrade-classification` (v4.7.0) — one canonical `hooks/shared/approval_artifact.py` consumed by every carrier; parsed UTC expiry; body/filename action agreement; `command_digest`/`repo_id` binding; fail-closed regex + empty policy; truthful trust model |
| Filed as ticket | `docs/backlog/approval-single-use-consumption/README.md` (K11 — the deliberately deferred half) |

## Recurrence triggers (so future sessions recognize this)

- A remediation ticket names the carriers **the report mentioned** rather than enumerating every
  carrier of the defect class. **This is the lesson**: when closing a defect class, enumerate every
  carrier and assert each one — do not fix the carriers the report happened to name.
- A grep for the defect's shape (here: `if expires and expires < now`) returns more hits than the
  ticket touched.
- A policy/config key is documented as enforced but no code reads it.
- A security check's failure branch is `continue`, `pass`, or `return True`.

## Related

- `docs/problem-catalog/security-check-fail-open-class/problem.md` — the v3.30.5 sweep this recurred
  inside. Same class, different carrier; that entry holds the class definition and is not restated here.
- `docs/problem-catalog/live-enforcement-inertness/problem.md` — the adjacent failure where tests are
  green and enforcement is inert. Both entries are about **believing a control works**; this one is
  about believing a *remediation* was complete.
- `docs/specs/approval-binding-and-upgrade-classification/decisions.md` — K1 (one canonical loader,
  chosen precisely so the three carriers cannot diverge again), K3, K4, K7
