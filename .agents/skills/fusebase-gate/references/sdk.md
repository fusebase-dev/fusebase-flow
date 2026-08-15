---
version: "1.6.8"
mcp_prompt: sdk
last_synced: "2026-08-04"
title: "Fusebase Gate SDK"
category: meta
---
# Fusebase Gate SDK

> **MARKER**: `mcp-sdk-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `sdk` for latest content.

---
## Fusebase Gate SDK

Use the Gate SDK for runtime integration code. Use MCP tools for discovery, explanations, and one off execution during the conversation.

## Package

npm: `@fusebase/fusebase-gate-sdk`. For development, install from public npm:
`npm install @fusebase/fusebase-gate-sdk` (or the equivalent in your package manager).

## Discovery Workflow

1. Use sdk_search to find relevant methods by intent or keywords.
2. Use sdk_describe to inspect the exact client, method, and input or output schemas.
3. Use the generated SDK client for application code.

## Peer App API Workflow

If the task is to integrate with another Fusebase app in the same org, do not treat it like an unknown third-party API.
Start with published app API discovery through Gate:
- searchAppApiOperations
- listAppApiOperations
- getAppApiOperation
Only then move to callAppApi or direct runtime probing if behavior still needs verification.
Do not start by asking for raw OpenAPI export, manual endpoint lists, local source code, or dashboard/storage schema spelunking when a published app API exists.
For security-sensitive app API operations, use contract-level policy: `x-fusebase-allowed-callers` for caller identity and `x-fusebase-required-permissions` for caller capability.
`x-fusebase-required-permissions` must use the app API namespace `app_api.<namespace>.<capability>.<action>` (for example `app_api.client_portal.provision.write`), not built-in Gate permissions such as `isolated_store.read`. Spell every segment lowercase: `app_api.clientPortal.provision.write` cannot be granted to any caller, and the operation is rejected with a 400 naming it.
A required permission is only satisfied if the **calling** app was granted that exact capability (`fusebase app update <appId> --permissions app_api.<namespace>.<capability>.<action>`). Grant it before relying on the guard: declaring a permission no caller holds locks the operation out. These extensions were ignored at runtime until NIM-42740, so an operation that has always been callable may start returning `403 app_api_missing_permissions` once your environment enforces them.
Those guards are evaluated against the **calling identity**. A browser `fbsfeaturetoken` embeds a Gate service token carrying `client:<productId>`, so it satisfies `x-fusebase-allowed-callers` for its own product and any end user can replay it from devtools. Only `x-fusebase-required-permissions` is browser-proof (`app_api.*` is backend-only and stripped from the browser mint) — pair the two guards on anything sensitive.
To run a guarded operation for an end user, call `callAppApi` from the app backend with its service token and pass the user's `fbsfeaturetoken` as `onBehalfOfUserToken` in the body. Gate verifies it fail-closed (401 `obo_user_token_invalid`, 403 `obo_user_token_org_mismatch`) and forwards `X-Fusebase-Verified-User-Id` / `X-Fusebase-Verified-User-Source: obo` to the provider runtime — read the user id from those headers instead of hand-rolling dual-token forwarding.
The platform proxy strips inbound `X-Fusebase-Verified-*` headers it cannot prove came from Gate, so they cannot be forged through the app URL. Your backend's deploy FQDN is a separate public origin that the proxy does not front, and the backend cannot tell the two apart — so OBO removes the dual-token plumbing, not the trust requirement. Do not treat a verified header as a bearer credential for anything you would not expose to any authenticated peer in the org.
Denials come back as 403 with a machine-readable `errorCode` under `data` in the error body (`app_api_caller_not_allowed`, `app_api_missing_permissions`, `app_api_operation_private`); an unknown operation is a 404 `app_api_operation_not_found`. Branch on `errorCode`, not on the message.

## Main SDK Clients

- HealthApi
- AccessApi
- BillingApi
- OrgUsersApi
- OrgsApi
- PortalsApi
- SystemApi
- TokensApi
- WorkspacesApi

## Current Service Focus

For organization membership flows, prefer OrgUsersApi methods such as listOrgUsers and addOrgUser.
For session-backed org access checks, use AccessApi.getMyOrgAccess instead of inferring access from listOrgUsers timing.
After sign-up, sign-in, or provisioning writes, re-check AccessApi.getMyOrgAccess before unlocking org content.
Treat `result: "invite"` from addOrgUser as pending membership rather than granted access.
Do not treat a custom /me or account endpoint as the source of truth unless it delegates to getMyOrgAccess.
For platform email magic links (`/_auth/magiclink/{key}`), call `getMyOrgAccess` from the app backend with `x-app-feature-token` from the `fbsfeaturetoken` cookie and verify `source === 'member'`. For legacy SPA `activateAppMagicLink`, forward `sessionToken` as `EverHelper-Session-ID` together with `x-app-feature-token`, or POST both in the exchange body.
For Stripe onboarding, product, checkout, and subscription-cancel flows, start with BillingApi methods such as getStripeOauth, createStripeProduct, updateStripeProduct, deleteStripeProduct, getStripePaymentLink, cancelStripeSubscription, and getStripePaymentState.
Treat BillingApi.updateStripeMode as a compatibility surface for now rather than a normal app workflow: Gate billing should currently be considered live-mode only.
Use stable app-owned `kind` and `kindId` values in BillingApi. Keep `kind` at 32 chars max and `kindId` at 64 chars max so webhook-backed payment state can be checked later for the same entitlement.
For subscription offboarding, BillingApi.cancelStripeSubscription defaults to cancel-at-period-end when `cancelAtPeriodEnd` is omitted. Send `cancelAtPeriodEnd: false` only for immediate cancellation.
For workspace discovery, use WorkspacesApi.listWorkspaces.
For the organization canonical base URL (subdomain or custom CNAME domain), use OrgsApi.getOrgUrl.
For portal discovery, use PortalsApi.listPortals.
For portal invite flows, inspect addOrgUser because portal magic links are returned there rather than through a separate Portal invite API.
For isolated SQL schema work, keep migration files in the app repo and use SDK helpers `buildSqlMigrationBundle(...)` and `calculateSqlMigrationChecksum(...)` before calling IsolatedStoresApi.getIsolatedStoreSqlMigrationStatus / applyIsolatedStoreSqlMigrations.
For isolated store runtime wiring in external apps, do not hardcode `storeId` values and do not store them as long-lived app secrets or env vars. Treat this as an anti-pattern.
Do not ask users to register Gate-resolved store identity with `fusebase secret create`: `storeId`, database IDs, physical database names, and provider connection details are platform/resource binding details, not app-owned secrets.
Preferred isolated store discovery flow in SDK code: call IsolatedStoresApi.listIsolatedStores with `orgId` + `clientId`, filter by stable store alias (or `aliasLike`), then use the resolved `storeId` for stage and SQL operations.
Store app-level alias/client binding in non-secret config only when needed; resolve physical/logical store ids at runtime from Gate.

## Usage Rules

- Do not guess client names or method names. Discover them through sdk_search or sdk_describe.
- Treat sdk_describe as the source of truth for params shape and response shape.
- Keep MCP and SDK roles separate: MCP is for discovery and execution in chat, SDK is for product code.

## Tokens permissions behavior

When creating or updating API tokens, permission handling is soft by default (`strictPermissionValidation = false`).
- If requested permissions exceed caller role or granted permissions, token permissions are degraded to the allowed subset.
- If requested permissions are unknown or not allowed for the service, they are ignored in soft mode.
- Do not enable strict mode unless there is a clear product or compliance requirement for fail-fast behavior.

## SDK error handling

Always handle SDK operation failures explicitly.
- Wrap Gate SDK calls in try/catch and branch by HTTP status and operation context.
- Treat 401/403 as authorization outcomes: surface clear user-facing guidance and avoid privileged fallback paths.
- For token and permission-sensitive flows, include actionable diagnostics (requested permissions, caller role/context, and denied operation).
- For create/update token flows, treat permission reductions as expected in soft mode and only fail hard when strict mode is intentionally enabled.
---

## Version

- **Version**: 1.6.8
- **Category**: meta
- **Last synced**: 2026-08-04
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
