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

## Procedure

1. Scan diff for files matching auth/secrets/data patterns from `policies/protected-paths.yml`.
2. For Fusebase Apps diffs, load relevant CLI provider skills (`app-secrets`, `handling-authentication-errors`, `fusebase-gate`, `fusebase-dashboards`) as runtime-specific security context.
3. Run secret-pattern check against added lines: API keys, session cookies, private keys, OAuth tokens, cloud credentials. NEVER print detected values; redact in any output.
4. Auth surface: if endpoints added/modified, verify each has explicit auth gate matching project's auth model from `AGENTS.md`. Flag missing gates as blocker.
5. Permission surface: if role checks added/modified, verify scope is least-privilege; flag overly broad scopes.
6. Production data surface: if DB writes added, verify they go through the established repository/transaction pattern; flag direct connection-string writes.
7. External-message surface: if outbound messages added (email, SMS, webhooks), verify they're idempotent or have a "do not send twice" safeguard. Flag missing approval artifact for `external_customer_visible_message` per `approval-policy.yml`.
8. Build approval-required list: every operation in diff that triggers `require_approval` in `approval-policy.yml` and lacks a corresponding artifact in `state/approvals/`.
9. Output security review summary in chat (Mode A):
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
