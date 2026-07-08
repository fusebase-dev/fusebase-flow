---
version: "1.3.0"
mcp_prompt: appMagicLinks
last_synced: "2026-05-28"
title: "Fusebase Gate App Magic Link Operations"
category: specialized
---
# Fusebase Gate App Magic Link Operations

> **MARKER**: `mcp-app-magic-links-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `appMagicLinks` for latest content.

---
## Table of contents

- [Fusebase Gate App Magic Link Operations](#fusebase-gate-app-magic-link-operations)
- [Terminology: `product` / `app` vs the Gate wire contract](#terminology-product--app-vs-the-gate-wire-contract)
- [Relevant Operations](#relevant-operations)
- [When To Use Each Flow](#when-to-use-each-flow)
- [Identity And Scoping Rules](#identity-and-scoping-rules)
- [Invite Flow Rules (`createAppMagicLink`)](#invite-flow-rules-createappmagiclink)
- [Self-Service Rules (`requestAppMagicLink`)](#self-service-rules-requestappmagiclink)
- [Activation Rules (`activateAppMagicLink`)](#activation-rules-activateappmagiclink)
- [Deep-Link Redirect Usage](#deep-link-redirect-usage)
- [Expired-Link Handling](#expired-link-handling)
- [Access Model](#access-model)
- [`accessPrincipals` Vs Org Membership](#accessprincipals-vs-org-membership)
- [Platform Edge: Visitor Token And `/api/*`](#platform-edge-visitor-token-and-api)
- [App Session Exchange After Activation](#app-session-exchange-after-activation)
  - [Test vs Production session policy](#test-vs-production-session-policy)
  - [Don't register non-secrets](#dont-register-non-secrets)
- [Working Rules](#working-rules)

---
## Fusebase Gate App Magic Link Operations

These operations expose one-click client onboarding for AI Apps. They mirror the portal magic-link flow but live on the app subdomain (`https://{appSubdomain}.{domain}/_auth/magiclink/{key}`) and target the `nimbus-ai` storage layer through Gate. Activation is handled **server-side by the platform** at that URL (HttpOnly cookies + redirect); the SPA never activates links itself.

## Terminology: `product` / `app` vs the Gate wire contract

FuseBase renamed its core entities: the old `app` is now a **`product`**, and the old `feature` is now an **`app`**. The Gate magic-link **wire contract still uses the pre-rename field names**, so those field names no longer match the CLI (`fusebase.json`, `fusebase app list`). Mixing the two ids up is the single most common cause of an `App not found` / `404` failure on `createAppMagicLink` — read this table before constructing any call.

| New name | Old name | What it is | Gate magic-link field | Where the value comes from |
| --- | --- | --- | --- | --- |
| **Product** | `app` | The deployable project / container | `appId` **path segment** of `createAppMagicLink` | `productId` in `fusebase.json` (the project; `fusebase product`) |
| **App** | `feature` | A host-bearing unit (one subdomain) inside a Product | `appFeatureId` in the activation response; the scope of `featureToken` | `apps[].id` in `fusebase.json` / `fusebase app list` / `fusebase app get` |

- `createAppMagicLink` path is `POST /:orgId/apps/:appId/magic-links`. Despite the `apps/:appId` spelling, `:appId` must be the **Product id** (`productId` from `fusebase.json`). Passing an **App** id (`apps[].id`, the value printed by `fusebase app list`) here is the #1 cause of `App not found`.
- `appFeatureId` returned by `activateAppMagicLink` is an **App** id in the new naming — the host-bearing unit you see in `fusebase app list`. It is not a Product id and must never be sent back as the `appId` path segment.
- `featureToken` is the Gate token for that **App** (host unit); `dashboardToken` is the dashboard-service token for the same App.
- The wire field names (`appId`, `appFeatureId`, `featureToken`, the `fbsfeaturetoken` cookie) are intentionally left at their pre-rename spelling for backward compatibility. Do not rename them in API calls or cookies — only the human-facing concepts were renamed, not the contract.

## Relevant Operations

- `createAppMagicLink` — owner/admin invite flow. Creates a 24h magic link for an email and dispatches it via the `magic_link_app` mail template. Optionally provisions a brand-new user and adds a user principal to every App of the Product.
- `requestAppMagicLink` — visitor self-service flow. Visitor enters their email; Gate forwards to nimbus-ai which sends a magic link only when the email already has access under the App's current `accessPrincipals`. Always returns `{ ok: true }` so it cannot be used to enumerate emails or access state.
- `activateAppMagicLink` — visitor activation. Exchanges a magic-link `globalId` for a session token, a Gate app token (`featureToken`), and a Dashboard token (`dashboardToken`), plus the `redirectPath` the SPA must navigate to.

## When To Use Each Flow

- Use `createAppMagicLink` when the caller is the app owner/admin and wants to invite a known client by email. This is the right call for proposal/invoice deep-link delivery (set `redirectPath` to the deep page).
- Use `requestAppMagicLink` from the app's own login form (a sign-in screen) when a visitor types their email and asks for a magic link. Never call it from the owner-side admin UI.
- `activateAppMagicLink` is called by the **platform**, not by app code: the visitor lands on `/_auth/magiclink/{globalId}`, fusebase-gate activates the link on nimbus-ai, sets HttpOnly session cookies on the app domain, and redirects to the stored `redirectPath`. Do not call activate from the SPA or write session cookies via JS.

## Identity And Scoping Rules

- `createAppMagicLink` is org- and Product-scoped: `orgId` and `appId` are required path inputs, and `appId` is the **Product id** (`productId`), not an App id. The caller must hold `app_magic_link.write` on that org plus org access.
- `requestAppMagicLink` is App-scoped by host: the `host` path param is the visitor's current hostname (`window.location.host`); Gate resolves it to an App (the host-bearing unit, formerly `feature`).
- `activateAppMagicLink` is link-scoped: `globalId` is the random id from the email URL; possession of the id is the only credential.
- Treat `globalId`, `appId`, and `appFeatureId` as opaque strings. Reuse values returned by previous responses, and never swap an `appId` (a Product id) for an `appFeatureId` (an App id).
- The visitor endpoints intentionally run with `AuthModuleContract.accessVisitor()`: do not attach a session cookie or feature token before calling them.

## Invite Flow Rules (`createAppMagicLink`)

- The `appId` path segment is the **Product id** (`productId` from `fusebase.json`) — see the Terminology section. Body fields: `email` (required), `redirectPath` (optional; defaults to `/`), `addToAccessPrincipals` (optional; defaults to true).
- `addToAccessPrincipals: true` provisions the user record if needed and appends `{ type: "user", id: <userId> }` to every App of the Product, de-duplicated. Use this when inviting a brand-new client.
- `addToAccessPrincipals: false` is only valid for emails that already have access. Sending it with an unknown email returns 404 — by design, so the caller does not silently dispatch a useless link.
- The response is `{ id, magicLinkUrl, expiresAt }`. `id` is the `globalId` and is also embedded inside `magicLinkUrl`.
- Mail dispatch errors are logged but do not roll the row back; the owner can still copy `magicLinkUrl` from the response.

## Self-Service Rules (`requestAppMagicLink`)

- Body fields: `email` (required), `redirectPath` (optional).
- Response is always `{ ok: true }`. Do not try to infer success/failure from the response — by design it cannot be used to enumerate. **No email sent** usually means the address is unknown, the user is not an org member, or their org role / user id does not match the App's `accessPrincipals` — not a transport failure.
- Apply per-IP rate limiting upstream of this call (e.g. CDN, ingress, or app-level middleware). nimbus-ai layers an internal per-`(orgId, appId, email)` 30-second cooldown so a typo-then-retry loop does not spam the inbox, but that is not a substitute for IP rate limiting.
- This endpoint never mutates `accessPrincipals` and never provisions users. Visitors who do not already have access stay unauthorized.
- Org membership alone is insufficient: `registerFusebaseOrgMember` and org invites do **not** update `accessPrincipals`. After onboarding members, ensure `fusebase app update <appId> --access=…` includes every `orgRole:*` that should receive self-service links (often together with `visitor` for public areas).
- Typical pitfall: App created with `--access=visitor` only → clients invited via `createAppMagicLink` (`addToAccessPrincipals: true`) receive mail; org **members** registered separately do not until their `orgRole` is listed in `--access`.

## Activation Rules (`activateAppMagicLink`)

- Activation happens **server-side**: the visitor opens `/_auth/magiclink/{globalId}` on the app domain, fusebase-gate calls the activate op against nimbus-ai, sets HttpOnly `eversessionid` / `fbsfeaturetoken` / `fbsdashboardtoken` cookies, and 302s to the stored `redirectPath` (the server stored it on the link row at create time). App code never calls activate. The SPA scaffold only keeps a legacy `/link?id={key}` route that forwards old email URLs to `/_auth/magiclink/{key}`.
- Successful response: `{ id, sessionToken, featureToken, dashboardToken, redirectPath, expiresAt, appFeatureId }`.
  - `sessionToken` — Fusebase user session for the **magic-link recipient**; the platform persists it as the HttpOnly `eversessionid` cookie. Apps must not treat platform cookies alone as durable app identity (see App session exchange below).
  - `featureToken` — Gate token scoped to the resolved **App** (host unit); authenticates the app feature but **does not substitute** for `sessionToken` on `getMyOrgAccess` and similar user-context Gate ops.
  - `dashboardToken` — dashboard-service token, scoped to the same App and target user. The bundled SPA persists it as the `fbsdashboardtoken` cookie so dashboard SDK calls (`@fusebase/dashboard-service-sdk`) can authenticate after activation; in the deployed app-wrapper flow it is bundled inside the gate feature token JWT, but the magic-link activation hands both tokens out as discrete strings.
  - `redirectPath` — relative path to navigate to after token persistence (`/` if the invite did not request a deep link).
  - `appFeatureId` — the resolved **App** id (host-bearing unit, formerly `feature`) the tokens are scoped to; it matches an `apps[].id` from `fusebase app list`, not a Product id.
  - `expiresAt` is included so the SPA can mirror the same expired UI without a second round-trip.
- Within the 24h TTL the link can be activated more than once (covers the "user opened the email twice" case).
- Failure modes are well-typed:
  - `404 NotFound` — link id does not exist or the row is soft-deleted.
  - `403 Forbidden` with `reason="expired"` — TTL elapsed; show the expired-link UI and offer a request-link flow.
  - `403 Forbidden` with `reason="revoked"` — the target user no longer has access at activation time (principals mutated after the link was issued); fall back to the same expired-link UI or show "this link is no longer valid".
- The platform renders the error page for these failures; app code branching on `reason` only matters if it surfaces activation errors in its own UI.

## Deep-Link Redirect Usage

- `redirectPath` is opaque to Gate; nimbus-ai stores it verbatim on the link row and returns it on activation.
- Always make `redirectPath` relative (`/proposals/abc`, `/invoices/123`). Absolute URLs would let the inviter point the activation to an unrelated origin.
- The platform `/_auth/magiclink/{key}` handler sanitizes `redirectPath` before redirecting (unsafe values collapse to `/`).
- Pair `redirectPath` with the email subject the owner sends so the deep page matches the user's expectation ("View your proposal" → `/proposals/abc`).

## Expired-Link Handling

- Gate surfaces 403 with `reason=expired` exactly when `expiresAt < now()`. Show a clear message ("This link has expired") plus a button that re-runs the self-service flow (`requestAppMagicLink`) with the previously-attempted email and `redirectPath`.
- Do not retry the activate call automatically on 403 — the link is already dead. Trying again only confuses the user.
- For `reason=revoked`, do not offer the request-link flow blindly: the user's access was removed deliberately. Either show a generic "link is no longer valid" message or route them through the standard sign-in / request-access path.

## Access Model

- `createAppMagicLink` requires `app_magic_link.write` plus org access. Granted by default to `owner`, `manager`, `member`, and `guest` org roles via the existing `GATE_ALL_PERMISSIONS` set.
- `requestAppMagicLink` and `activateAppMagicLink` are visitor endpoints (no permission, no session). The policy is enforced inside nimbus-ai by re-evaluating `accessPrincipals` against the resolved user.

## `accessPrincipals` Vs Org Membership

| Mechanism | What it grants | Affects `requestAppMagicLink`? |
| --- | --- | --- |
| Org membership (`registerFusebaseOrgMember`, `addOrgUser`, invites) | Role in the organization | Only if App principals are empty (org-member fallback) or list a matching `orgRole` / `orgGroup` / `user` |
| App `accessPrincipals` (`fusebase app create/update --access`) | Who may use this host-bearing App | **Yes** — self-service checks principals first when the list is non-empty |
| `createAppMagicLink` + `addToAccessPrincipals: true` | Adds `{ type: user, id }` on every App of the Product | Invite mail always; also satisfies self-service for that user id |

- Principals are comma-separated CLI entries: `visitor`, `orgRole:member`, `orgRole:client`, `user:<id>`, `orgGroup:<id>`. `visitor` allows **guests to open the App host** and receive a visitor `fbsfeaturetoken` via platform `/_auth/` — it is **not** unauthenticated `/api/*`. It does **not** grant self-service magic links to logged-in org members.
- Load the `fusebaseAuth` prompt for registration/login patterns, visitor/API edge behavior, and the mandatory app-backend session exchange after activation.

## Platform Edge: Visitor Token And `/api/*`

Magic-link Apps are often created with `--access=visitor`. The platform still requires `fbsfeaturetoken` before proxying `/api/*` to the App backend.

- Before activation (or before the browser completes `/_auth/`), `GET /api/…` without cookies redirects to auth — **not** a broken backend.
- After `/_auth/magiclink/{key}` activation the platform has set the cookies; same-origin `/api/account/from-magic-link` then reaches the backend. Timeouts on that route after deploy usually mean **backend listen port / health** (infra), not missing visitor access.
- Do not smoke-test deployed magic-link flows with naked `curl` on `/api/health`; use the browser flow or curl with cookies saved after `/_auth/`.
- Do not call Gate `getMyOrgAccess` from the SPA for the exchange — CORS blocks `EverHelper-Session-ID`; use the backend exchange pattern below.

## App Session Exchange After Activation

The platform activation at `/_auth/magiclink/{key}` sets HttpOnly cookies and redirects — JS cannot read the tokens. **The mandatory part of the exchange is identical in Test and Production:** before any protected route renders, the backend must resolve the recipient via Gate from the request cookies rather than trusting the feature token alone.

1. Visitor opens `/_auth/magiclink/{key}`; the platform activates the link, sets HttpOnly `eversessionid` / `fbsfeaturetoken` / `fbsdashboardtoken` cookies, and redirects to `redirectPath`.
2. The SPA calls a trusted app route (e.g. `/api/account/from-magic-link`); same-origin requests carry the HttpOnly cookies automatically.
3. Backend reads the cookies and calls Gate with `x-app-feature-token: <fbsfeaturetoken>` + `EverHelper-Session-ID: <eversessionid>` (e.g. `getMyOrgAccess`) to resolve `userId`.

Never use `getMyOrgAccess` with only the feature token to gate Memberspace — that returns the token owner, not the visitor.

### Test vs Production session policy

Choose the cookie policy based on what the app actually needs; do not auto-upgrade smoke tests to the production recipe.

**Test mode (smoke test of the magic-link flow, no Memberspace, no role gating):**

- Step 3 returns `userId` for the current request and the SPA redirects. That is the end of the exchange.
- Do **not** issue an HMAC-signed app session cookie. Do **not** create `APP_SESSION_SECRET` via `fusebase secret create`. The `fbsfeaturetoken` / `eversessionid` cookies set by activation are sufficient for the smoke flow, and re-running the exchange on the next protected request is acceptable.

**Production mode (Memberspace, role-gated UI, or any flow that must remember the recipient across navigations):**

- After step 3, issue an **app-owned** session cookie (HMAC-signed or equivalent integrity-protected payload, bound to the resolved `userId`) and treat it as the source of truth for subsequent requests. Verify on every protected request; do not re-infer identity from `fbsfeaturetoken`.
- Register the HMAC secret here and only here: `fusebase secret create --app <%= it.flags?.includes("declarative-manifest") ? "<appPath>" : "<appId>" %> --secret "APP_SESSION_SECRET:HMAC signing key for app-owned session cookie"`. Read it from `process.env.APP_SESSION_SECRET` at runtime.
- Set cookie attributes `httpOnly`, `secure`, `sameSite=Lax`, `path=/`. Rotate by changing the secret + invalidating active cookies; do not depend on Fusebase platform cookies for revocation.

### Don't register non-secrets

- `FUSEBASE_ORG_ID` is **not a secret** — it lives in `fusebase.json` as `orgId` and is readable by anyone who clones the repo. Do not run `fusebase secret create … FUSEBASE_ORG_ID:…`. Read the value from `fusebase.json` (or platform-injected env where available) at app start.
- The same rule applies to other already-public values such as `productId`, the app subdomain, or Fusebase host URLs (`FBS_*` config). `fusebase secret create` is reserved for credentials that must not appear in the repo (HMAC keys, third-party API tokens, OAuth client secrets).
- A Test-mode magic-link app needs **zero** `fusebase secret create` calls for the magic-link flow itself. A Production-mode app needs exactly one: `APP_SESSION_SECRET` for the app-owned session cookie.

## Working Rules

- Always inspect the exact contract with `tools_describe` or `sdk_describe` before integration work — the request and response shapes are versioned independently from this prompt.
- When wiring `createAppMagicLink`, pass the **Product id** (`productId` from `fusebase.json`) as the `appId` path segment. If a call fails with `App not found` / `404`, the most likely cause is an App id (`apps[].id` from `fusebase app list`) used where the Product id belongs — re-read the Terminology section.
- For app templates that ship with a sign-in form, wire the form to `requestAppMagicLink`; activation is platform-handled at `/_auth/magiclink/{key}`. Never persist the magic link `id` past activation; treat it as single-flow credential material.
- For owner-side admin UI, prefer `createAppMagicLink` with `addToAccessPrincipals=true` for first-time invites and `addToAccessPrincipals=false` for re-invites of users who already have access.
- If activation fails, do not assume `accessPrincipals` is the wrong shape; re-read the `reason` field and follow the expired-link handling rules above.
---

## Version

- **Version**: 1.3.0
- **Category**: specialized
- **Last synced**: 2026-05-28
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
