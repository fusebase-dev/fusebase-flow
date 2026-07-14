---
applyTo: "**/auth/**, **/middleware/**, **/permissions/**, **/.env*, **/secrets/**, **/migrations/**, **/*.sql, **/deploy/**, .github/workflows/**"
---

# Fusebase Flow — security & permissions instructions for GitHub Copilot / VS Code

These instructions apply when changes touch auth, permissions, secrets, env files, deploy config, external messages, data export/import, or production DB writes.

## Hard prohibitions

- Never print secret values (FR-12). Redact in any output. Patterns at `policies/secret-patterns.yml`.
- Never `git add` `.env`, credentials, private keys (FR-06).
- Never write a customer-visible external message without `external_customer_visible_message` approval artifact (FR-12).
- Never use a session key / cookie without `session_key_or_cookie_use` approval artifact (FR-12).
- Never modify auth / permission code without `auth_or_permission_change` approval artifact (FR-12).

## Approval artifacts

If an action requires approval per `policies/approval-policy.yml`, an approval artifact must exist on disk. **The agent authors it on the operator's approval — never the operator by hand at a terminal.** For a Full-lane deploy, on the DP.6 phrase `approve deploy now` (forgiving — any case/spacing; legacy `APPROVE-DEPLOY-NOW` also passes) — the operator types only the phrase, never a composed sentence (Lightweight lane: a plain chat go-ahead, recorded via `approve-local.sh lightweight_deploy` — DP.12); for any other approval-gated action (protected-path edit, FR-25 baseline adoption, database migration, auth/permission change), once the operator OKs that specific action in chat. Authoring with NO operator authorization is self-approval and forbidden:

```
state/approvals/<action>-<slug>-<YYYYMMDD>.json
```

The agent runs this on that approval — the operator types no command: `bash hooks/local/approve-local.sh <action> <slug> "<reason>"`.

Hooks check for an unexpired artifact before allowing the action.

## Categories that trigger this scope

- Auth middleware, permission checks, role / scope code, login / logout flows
- `.env`, secrets handling, credential storage, encryption code
- Outbound external messages (email, SMS, webhooks, public posts)
- Data export, bulk import, customer data movement
- Production DB writes outside the established repository pattern
- Deploy config, CI / CD pipeline, infra-as-code

## Verify before commit

- No new `any` / broad casts on JSON from external APIs.
- No raw connection strings / SQL outside the repository pattern.
- New endpoints carry the project's auth gate (read `AGENTS.md` project-specific section for the pattern).
- New outbound message paths are idempotent or have a "do not send twice" safeguard.

## What this scope does NOT do

- General code review (use the `code-review` skill at `flow-skills/code-review/SKILL.md`)
- Style / formatting concerns
- Performance (out of v0.1 scope)
