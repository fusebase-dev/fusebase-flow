---
name: security-permissions-review
description: Use when changes touch auth, permissions, secrets, env files, deploy config, external messages, data export/import, production DB writes, or customer-visible behavior; surfaces sensitive-path findings + approval-required list. Do NOT use as general code review.
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: 2.1
risk_level: high
invocation: manual
expected_outputs:
  - security review summary (chat or docs/verification/<slug>-security.md)
  - sensitive-path findings list
  - approval-required list (operations needing approval artifact)
  - mitigation steps
related_workflows:
  - verification-gate.md
hook_dependencies:
  - permission_request
  - pre_tool_use
---

# Security & Permissions Review

## Purpose

Targeted review for changes that touch security-sensitive surfaces. Distinct from general `code-review` because the failure modes (credential leak, auth bypass, customer data exposure) have different response thresholds — even non-blocking findings here may require approval gates.

## When to invoke

- Diff touches: auth middleware, permission checks, role/scope code, login/logout flows
- Diff touches: `.env`, secrets handling, credential storage, encryption code
- Diff adds: outbound external messages (email, SMS, webhooks, public posts), customer-facing notifications
- Diff adds: data export, bulk import, customer data movement
- Diff adds: production DB writes outside the established repository pattern
- Diff modifies: deploy config, CI/CD pipeline, infra-as-code
- Operator says "security review" / "is this safe re: auth?" / "check for secret leaks"

## Do not invoke when

- Diff is purely UI/styling/copy with no auth/data surface
- Diff is in-test-only changes
- Diff is a documentation-only commit
- A higher-priority skill is mid-flight and the operator wants this as a follow-up — file a backlog ticket

## Required inputs

| Input | Where it lives | If missing |
|---|---|---|
| Diff | `git diff <baseline>..HEAD` | Stop; ask which diff to review |
| Sensitive paths config | `policies/protected-paths.yml` (auth + secrets sections) | Use built-in defaults from policy template; flag policy as needing customization |
| Secret patterns | `policies/secret-patterns.yml` | Use built-in defaults; flag policy as needing customization |
| Approval policy | `policies/approval-policy.yml` (+ optional `.local.yml` override) | Stop; FR-12 cannot enforce without policy |
| CLI edition map, for Fusebase Apps work | `docs/fusebase-cli-edition.md` | Continue with generic security review, but mark app-domain auth/secret assumptions unknown |
| App access + permission grants (Fusebase Apps diffs) | deploy handoff / `fusebase app list` / registration step in ticket | Ask operator for current grants; never assume the app is org-only — an inherited `visitor` principal changes every finding's severity |

## Procedure

1. Scan diff for files matching auth/secrets/data patterns from `policies/protected-paths.yml`.
2. For Fusebase Apps diffs, load relevant CLI provider skills (`app-secrets`, `handling-authentication-errors`, `fusebase-gate`, `fusebase-dashboards`) as runtime-specific security context.
3. Run secret-pattern check against added lines: API keys, session cookies, private keys, OAuth tokens, cloud credentials. NEVER print detected values; redact in any output.
4. Auth surface: if endpoints added/modified, verify each has explicit auth gate matching project's auth model from `AGENTS.md`. Flag missing gates as blocker.
5. Permission surface: if role checks added/modified, verify scope is least-privilege; flag overly broad scopes.
6. **Fusebase-native permission surfaces** (Fusebase Apps diffs; skip for non-app repos — the CLI provider skills from step 2 give runtime context):
   - **App access principals (public-access flag).** `fusebase app create/update --access`: `visitor` = any unauthenticated user; `--access=""` = ALL org roles (NOT lockdown). `--access` REPLACES the entire principal list — principals are `type` or `type:id` — `visitor`, or `orgRole:<id>` with ids `guest`, `client`, `member`, `manager`, `owner` — verify the change neither silently widens (adds `visitor`, or adds more org roles than the feature needs; the widest grants are all-org-roles or a `visitor` principal) nor drops a restriction the operator relies on. Any widening → approval-required list; verify every surface the app exposes (dashboard views, backend endpoints, gate stores) is safe for the widest principal granted.
   - **Dashboard permission scopes.** `--permissions="dashboardView.<dashboardId>:<viewId>.<privileges>"`: least-privilege — `write` only on views the runtime actually mutates (`batchPutDashboardData` / `addRelationRows`); read-only SDK usage (`getDashboardViewData`) gets `read`. Flag write-everywhere grants and grants with no matching SDK call in runtime code.
   - **Gate token scopes.** Apps using `@fusebase/fusebase-gate-sdk`: `fusebase app update --sync-gate-permissions` must run after Gate-SDK call changes — Gate soft mode silently DEGRADES tokens to the allowed subset, so unsynced grants surface as 403s / missing data in smoke, not as deploy failures. Flag any user-facing flow that falls back to service-token auth on Gate 401/403 (blocker per fusebase-gate security rule — service tokens live only in explicit system/admin endpoints with audit logging).
   - **SDK / gate-store writes.** Isolated SQL/NoSQL store access (`isolated_store.*` permissions from `fusebase env create`): verify writes are org/tenant-scoped and requested store permissions match the operations the runtime performs — no broader store grant than the feature needs.
   - **Data export/import.** Bulk dashboard reads (`getDashboardViewData` fan-out, CSV/JSON dumps) or bulk imports: (a) export scope = minimum views/columns needed; (b) enumerate the PII fields crossing the boundary (names, emails, phones, client identifiers) in the review summary; (c) tenant isolation — exported/imported rows respect the org/workspace boundary, and import paths validate ownership before write. `approval-policy.yml` defines no data-export key — flag bulk export/import in the review summary as requiring explicit operator go-ahead before deploy; map to real approval keys only where the same diff genuinely triggers one (`auth_or_permission_change`, `database_migration`, `secret_file_write`).
7. Production data surface: if DB writes added, verify they go through the established repository/transaction pattern; flag direct connection-string writes.
8. External-message surface: if outbound messages added (email, SMS, webhooks), verify they're idempotent or have a "do not send twice" safeguard. Flag missing approval artifact for `external_customer_visible_message` per `approval-policy.yml`.
9. Build approval-required list: every operation in diff that triggers `require_approval` in `approval-policy.yml` and lacks a corresponding artifact in `state/approvals/`.
10. Output security review summary in chat (Mode A):
   - Blockers (must fix or get approval before deploy)
   - Sensitive-path findings (file:line + concern + mitigation)
   - Approval-required list (operations + missing artifacts)
   - Mitigation steps (concrete next actions)

## Output artifacts

| Artifact | Path / location | Mode |
|---|---|---|
| Security summary | chat output | Mode A |
| Optional persistent record | `docs/verification/<slug>-security.md` | Mode B (full) |
| Approval-required list | embedded in summary | Mode B (full, table) |

## Failure cases

| Failure mode | Detection | Response |
|---|---|---|
| Detected secret in diff | regex match on `policies/secret-patterns.yml` | BLOCK deploy. Redact value in output. Recommend `git reset --soft HEAD~1` + rotation. Per FR-12, log incident in `docs/problem-catalog/<slug>/`. |
| Missing approval artifact for `require_approval` op | scan `state/approvals/` against `approval-policy.yml: require_approval` | BLOCK deploy. Surface which artifact is missing and how to author it. |
| Auth gate missing on new endpoint | endpoint added without matching auth middleware import/decorator | BLOCK deploy. Surface specific endpoint + project auth pattern to apply. |
| Customer-visible message added without approval | outbound message API call in diff + no `external_customer_visible_message` approval artifact | BLOCK deploy. Per FR-12 + approval-policy. |
| Production DB write outside repository pattern | direct connection / raw SQL outside `*Repository.ts` / `*_repository.py` | BLOCK deploy. Surface migration path through repository layer. |
| App access widened without approval | `--access` gains `visitor` (public), or `--access=""` (empty = EVERY org role incl. `guest`/`client`; NOT visitors, NOT lockdown — broad internal exposure) in diff/deploy notes, no approval artifact | BLOCK deploy. `visitor` = any unauthenticated user → confirm every reachable surface is public-safe; empty access → confirm org-wide exposure is intended. Require explicit approval either way. |
| Dashboard write scope broader than SDK usage | `--permissions` grants `write` on views the runtime only reads (no mutation SDK calls) | Finding (non-blocking): narrow to `read` per least-privilege; blocker if the grant spans client data views. |
| Gate permissions out of sync with runtime Gate-SDK calls | Gate-SDK calls changed in diff, no `--sync-gate-permissions` in deploy steps | BLOCK deploy until sync runs — soft mode masks the gap by silently degrading tokens. |
| Implicit service-token fallback | user-facing flow catches Gate 401/403 and retries with service-token auth | BLOCK. Explicit system/admin endpoints + audit logging only (fusebase-gate security rule). |
| Export crosses tenant boundary / leaks PII | export path reads without org/workspace filter, or dumps PII columns not needed downstream | BLOCK deploy. Require scoped query + PII field list in summary + explicit operator go-ahead (`approval-policy.yml` has no data-export key; `auth_or_permission_change` applies only if the diff also changes auth/permission code). |

## Escalation path

- Live exploit suspected → STOP all flow work, create `docs/problem-catalog/incident-<date>/problem.md`, alert operator immediately
- Compliance question (PII handling, GDPR, etc.) → flag as blocker; ask operator for compliance reviewer signoff before proceeding
- Vendor security advisory affects diff → file backlog ticket; surface as known limitation in this review

## Anti-patterns

- Do NOT print secret values, ever (FR-12 + secret-patterns)
- Do NOT silently approve missing approval artifacts ("operator probably has it")
- Do NOT downgrade blockers to non-blockers under deploy pressure
- Do NOT scan beyond the ticket's diff in v0.1 (full repo audits are out of scope)
- Do NOT bypass `permission_request` hook — if it's wired, it's part of the contract

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. See `docs/source-map.md`.
