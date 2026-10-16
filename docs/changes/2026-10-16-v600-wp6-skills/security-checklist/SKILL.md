---
name: security-checklist
description: Load only when a backlog item's risk tag is auth, data or production, or the diff touches secrets, permissions, deploy config or outbound messages.
---

# Security checklist

Run it on the slice's diff, never the whole repository. Never print a secret: redact every value you find.

## Before you start

- No diff named: ask which one. `policies/approval-policy.yml` missing: stop; approvals cannot be checked without it.
- FuseBase app diff with the current app access and grants unknown: ask the operator for them. Never treat the app as org-only: an inherited `visitor` principal changes the severity of every finding.

| # | Check | When it fails |
|---|---|---|
| 1 | Added lines carry no key, token, cookie or private key (`policies/secret-patterns.yml`) | Blocker. Redact it; recommend `git reset --soft HEAD~1` and rotation |
| 2 | Every new or changed endpoint has the project's auth gate | Blocker, naming the endpoint and the pattern to apply |
| 3 | Role and scope checks are least-privilege | Finding; a blocker when it spans client data |
| 4 | Production writes go through the project's repository or transaction pattern | Blocker for a direct connection or raw SQL outside it |
| 5 | Outbound messages (email, SMS, webhooks, public posts) cannot send twice and have an `external_customer_visible_message` approval | Blocker without the approval |
| 6 | Export and import: minimum views and columns; every PII field crossing the boundary is listed; rows stay inside the org or workspace; imports check ownership before writing | Blocker; needs the operator's explicit go-ahead, since the approval policy has no export key |
| 7 | Deploy config, CI or infrastructure changed | Goes on the approval list |

## FuseBase app surfaces

The CLI skills `app-secrets`, `handling-authentication-errors`, `fusebase-gate` and `fusebase-dashboards` give the runtime detail.

- App access (`--access`): `visitor` is any unauthenticated user; an empty list is every org role, not a lockdown; the flag replaces the whole list. Any widening goes on the approval list, and every exposed surface must be safe for the widest principal granted.
- Dashboard scopes: `write` only on views the runtime changes; read-only use gets `read`.
- Gate tokens: after Gate-SDK call changes, `fusebase app update --sync-gate-permissions` runs before the deploy. A user-facing flow that falls back to a service token on 401 or 403 is a blocker.
- Isolated stores: writes are scoped to the org; store grants match the operations used.

## Approval list

Every operation in the diff that `policies/approval-policy.yml` gates and that lacks an acceptable artifact. Run `bash hooks/local/approve-local.sh --inventory` and read the `verdict(strict)` column:

| Verdict | Meaning |
|---|---|
| `VALID` | satisfied |
| `MISSING_EXPIRY` | accepted until `strict_approvals` is on; flag it for reissue |
| `EXPIRED`, `MALFORMED`, `ACTION_MISMATCH`, `BINDING_MISMATCH` | not satisfied; treat it as missing |

Never write that the operator approved something. Write: "an approval artifact exists and is VALID".

## Output

In chat: blockers; findings as file:line, concern and mitigation; the approval list; the next actions.

- A suspected live exploit: stop all work and tell the operator at once.
- A compliance question (PII handling, GDPR): a blocker until the operator obtains the compliance reviewer's signoff.
- A vendor security advisory that affects the diff: file a new backlog item and name it as a known limitation in the output.
