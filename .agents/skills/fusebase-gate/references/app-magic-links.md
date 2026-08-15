---
version: "1.9.2"
mcp_prompt: appMagicLinks
last_synced: "2026-08-12"
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
- [Activation Keys Are Host-Agnostic (Supported)](#activation-keys-are-host-agnostic-supported)
- [Deep-Link Redirect Usage](#deep-link-redirect-usage)
- [Binding A Link To An App Entity (`meta`)](#binding-a-link-to-an-app-entity-meta)
- [Expired-Link Handling](#expired-link-handling)
- [Access Model](#access-model)
- [`accessPrincipals` Vs Org Membership](#accessprincipals-vs-org-membership)
- [Platform Edge: Visitor Token And `/api/*`](#platform-edge-visitor-token-and-api)
- [App Session Exchange After Activation](#app-session-exchange-after-activation)
  - [Test vs Production session policy](#test-vs-production-session-policy)
  - [Platform token lifetime (not a durable visitor session)](#platform-token-lifetime-not-a-durable-visitor-session)
  - [Don't register non-secrets](#dont-register-non-secrets)
- [Invite Lifecycle And Orphan Links](#invite-lifecycle-and-orphan-links)
- [Working Rules](#working-rules)

---
## Fusebase Gate App Magic Link Operations

These operations expose one-click client onboarding for AI Apps. They mirror the portal magic-link flow but live on the app subdomain (`https://{appSubdomain}.{domain}/link?id=…&redirect=…`) and target the `nimbus-ai` storage layer through Gate.

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

- `createAppMagicLink` — owner/admin invite flow. Creates a magic link for an email (24h lifetime by default, or pass `ttlSeconds` to override) and dispatches it via the `magic_link_app` mail template. Optionally provisions a brand-new user and adds a user principal to every App of the Product.
- `requestAppMagicLinkURL` — owner/admin, no-email sibling of `createAppMagicLink`. `POST /:orgId/apps/:appId/magic-link-url` with the SAME body/response and side effects, but the platform does NOT send the `magic_link_app` email — the response still carries `magicLinkUrl`, so a white-label app can deliver its own branded email. Use this instead of `createAppMagicLink` when the app sends the invite email itself (avoids the recipient getting two emails). **Withheld case:** if the recipient is an existing FuseBase account that has never activated a magic link of this org, `id`/`magicLinkUrl` are absent and the platform sends its own `magic_link_app` email instead — check for `magicLinkUrl` before trying to send your branded one. Requires `app_magic_link.write` + org access.
- `bulkCreateAppMagicLinks` — owner/admin bulk invite. Invites MANY users to ONE app in a single call (use instead of looping `createAppMagicLink`). Invites run with bounded concurrency (default 5, max 5; the rest are queued); `background=true` returns immediately with `status='processing'`. Per-invitee semantics match `createAppMagicLink`, and one failed invitee never aborts the batch.
- `requestAppMagicLink` — visitor self-service flow. Visitor enters their email; Gate forwards to nimbus-ai which sends a magic link only when the email already has access under the App's current `accessPrincipals`. Always returns `{ ok: true }` so it cannot be used to enumerate emails or access state.
- `activateAppMagicLink` — visitor activation. Exchanges a magic-link `globalId` for a session token, a Gate app token (`featureToken`), and a Dashboard token (`dashboardToken`), plus the `redirectPath` the SPA must navigate to.
- `revokeAppMagicLink` — owner/admin revoke. `POST /:orgId/apps/:appId/magic-links/:globalId/revoke` soft-deletes a link so it can no longer be activated (activation then 404s) and the recipient email can be invited again. The fix for orphaned invites that would otherwise block a re-invite for 24h. Returns 404 for an unknown or already-revoked link. Requires `app_magic_link.write` + org access.
- `listAppMagicLinks` — owner/admin support/debug. `GET /:orgId/apps/:appId/magic-links?email=` lists the app's active (non-revoked) links, newest first, with an optional email filter. Returns row metadata only (never token material). Use it to find the `globalId` of an orphaned invite to revoke. NIM-42663: `id` is **omitted** for links whose URL was never disclosed to the owner (self-service links, and invites to existing accounts outside the org) — the id activates the link. Those links cannot be revoked by id; use `removeAppAccessPrincipal` on the recipient instead, which makes activation fail. Requires `app_magic_link.write` + org access.
- `removeAppAccessPrincipal` — owner/admin. `POST /:orgId/apps/:appId/access-principals/remove` with body `{ type, id }` removes an access principal from EVERY feature of the Product — the inverse of the invite grant. Use it to revoke a user's app access (`{ type: 'user', id: '<userId>' }`) or drop an `orgRole`/`orgGroup`/`visitor` grant. Idempotent: returns `{ removed: false, appsAffected: 0 }` when the principal was not present; 404 when the Product has no apps. Note this removes the app-access principal only — it does not remove the user from the org (see org member removal). Requires `app_magic_link.write` + org access.

## When To Use Each Flow

- Use `createAppMagicLink` when the caller is the app owner/admin and wants to invite a known client by email. This is the right call for proposal/invoice deep-link delivery (set `redirectPath` to the deep page).
- Use `bulkCreateAppMagicLinks` when inviting several clients to the same app — one call instead of N sequential `createAppMagicLink` calls. It shares the same path params (`orgId` + Product id) and `app_magic_link.write` permission.
- Use `requestAppMagicLink` from the app's own login form (the `/link` page or a sign-in screen) when a visitor types their email and asks for a magic link. Never call it from the owner-side admin UI.
- Use `activateAppMagicLink` from the SPA's `/link` route — the visitor lands on `/link?id={globalId}&redirect={path}`, the SPA calls activate, sets the session cookie, persists the feature token, and redirects.

## Identity And Scoping Rules

- `createAppMagicLink` is org- and Product-scoped: `orgId` and `appId` are required path inputs, and `appId` is the **Product id** (`productId`), not an App id. The caller must hold `app_magic_link.write` on that org plus org access.
- `requestAppMagicLink` is App-scoped by host: the `host` path param is the visitor's current hostname (`window.location.host`); Gate resolves it to an App (the host-bearing unit, formerly `feature`).
- `activateAppMagicLink` is link-scoped: `globalId` is the random id from the email URL; possession of the id is the only credential.
- Treat `globalId`, `appId`, and `appFeatureId` as opaque strings. Reuse values returned by previous responses, and never swap an `appId` (a Product id) for an `appFeatureId` (an App id).
- The visitor endpoints intentionally run with `AuthModuleContract.accessVisitor()`: do not attach a session cookie or feature token before calling them.

## Invite Flow Rules (`createAppMagicLink`)

- The `appId` path segment is the **Product id** (`productId` from `fusebase.json`) — see the Terminology section. Body fields: `email` (required), `redirectPath` (optional; defaults to `/`), `addToAccessPrincipals` (optional; defaults to true), `meta` (optional opaque string, ≤ 4 KB UTF-8 — see the `meta` section below), `appFeatureId` (optional), `ttlSeconds` (optional).
- `appFeatureId` (optional) is a child **App** globalId (`apps[].id` from `fusebase.json` / `fusebase app list`) that pins the sign-in host, so a multi-app Product can route the magic link per app. Omit it to fall back to the Product's first App (the previous behavior). Same field applies to `requestAppMagicLinkURL` and `bulkCreateAppMagicLinks`.
- `ttlSeconds` (optional) is the link lifetime in seconds; it defaults to 86400 (24h) and is clamped server-side to 3600..604800 (1h..7d) rather than rejected. `ttlSeconds: 0` (or negative) is NOT 'no expiry' and does NOT expire the link immediately — it clamps UP to 3600 (1h), the shortest lifetime the platform can issue. Same field applies to `requestAppMagicLinkURL` and `bulkCreateAppMagicLinks`.
- `addToAccessPrincipals: true` provisions the user record if needed and appends `{ type: "user", id: <userId> }` to every App of the Product, de-duplicated. Use this when inviting a brand-new client.
- `addToAccessPrincipals: false` is only valid for emails that already have access. Sending it with an unknown email returns 404 — by design, so the caller does not silently dispatch a useless link.
- The response is `{ id, magicLinkUrl, expiresAt }`. `id` is the `globalId` and is also embedded inside `magicLinkUrl`.
- **`id` and `magicLinkUrl` are optional (NIM-42663, NIM-43179).** They are returned only when the invite provisions a **brand-new** account, or targets an email that has **already activated a magic link of this org** (org membership alone does not count — the caller can create it themselves). For any other existing FuseBase account the response is `{ expiresAt }` only and the link is emailed to the recipient — activating a magic link grants a full session as that user, so the platform never hands the link to someone else. Always branch on `magicLinkUrl` being present; never render or forward it unchecked.
- Mail dispatch errors are logged but do not roll the row back; the owner can still copy `magicLinkUrl` from the response when it was disclosed.

## Self-Service Rules (`requestAppMagicLink`)

- Body fields: `email` (required), `redirectPath` (optional).
- Response is always `{ ok: true }`. Do not try to infer success/failure from the response — by design it cannot be used to enumerate. **No email sent** usually means the address is unknown, the user is not an org member, or their org role / user id does not match the App's `accessPrincipals` — not a transport failure.
- Apply per-IP rate limiting upstream of this call (e.g. CDN, ingress, or app-level middleware). nimbus-ai layers an internal per-`(orgId, appId, email)` 30-second cooldown so a typo-then-retry loop does not spam the inbox, but that is not a substitute for IP rate limiting.
- This endpoint never mutates `accessPrincipals` and never provisions users. Visitors who do not already have access stay unauthorized.
- Org membership alone is insufficient: `registerFusebaseOrgMember` and org invites do **not** update `accessPrincipals`. After onboarding members, ensure `fusebase app update <appId> --access=…` includes every `orgRole:*` that should receive self-service links (often together with `visitor` for public areas).
- Typical pitfall: App created with `--access=visitor` only → clients invited via `createAppMagicLink` (`addToAccessPrincipals: true`) receive mail; org **members** registered separately do not until their `orgRole` is listed in `--access`.

## Activation Rules (`activateAppMagicLink`)

- The SPA at `/link` reads `id` and `redirect` from the query string, then activates the link by issuing `POST {gateBaseUrl}/apps/magic-links/{id}/activate`. The bundled SPA template currently calls this endpoint directly via `fetch` so it stays usable before `@fusebase/fusebase-gate-sdk` exposes `AppMagicLinksApi.activateAppMagicLink`. Once that SDK ships, prefer `activateAppMagicLink({ path: { globalId: id } })` over hand-rolled fetches; the wire request is identical (the server already stored `redirectPath` on the link row at create time, so the client never sends it on activation).
- Successful response: `{ id, sessionToken, featureToken, dashboardToken, redirectPath, expiresAt, appFeatureId, meta }`.
  - `sessionToken` — Fusebase user session for the **magic-link recipient**. On **legacy SPA `/link` activation**, forward as `EverHelper-Session-ID` together with `x-app-feature-token`. On **platform email links** (`/_auth/magiclink/{key}`), org session lives on the org domain — the app host does not receive this as a cookie; use the post-activation exchange below instead.
  - `featureToken` — Gate token scoped to the resolved **App** (host unit). On platform email links, app-wrapper mints recipient-scoped `fbsfeaturetoken` on the app host (user id embedded in the JWE) — that cookie is the identity source for `getMyOrgAccess` on the app backend.
  - `dashboardToken` — dashboard-service token, scoped to the same App and target user. The bundled SPA persists it as the `fbsdashboardtoken` cookie so dashboard SDK calls (`@fusebase/dashboard-service-sdk`) can authenticate after activation; in the deployed app-wrapper flow it is bundled inside the gate feature token JWT, but the magic-link activation hands both tokens out as discrete strings.
  - `redirectPath` — relative path to navigate to after token persistence (`/` if the invite did not request a deep link).
  - `appFeatureId` — the resolved **App** id (host-bearing unit, formerly `feature`) the tokens are scoped to; it matches an `apps[].id` from `fusebase app list`, not a Product id.
  - `expiresAt` is included so the SPA can mirror the same expired UI without a second round-trip.
  - `meta` — the opaque string supplied at create time, echoed back byte-for-byte (`null` for links created without it). See the `meta` section below.
- Within the 24h TTL the link can be activated more than once (covers the "user opened the email twice" case).
- Failure modes are well-typed:
  - `404 NotFound` — link id does not exist or the row is soft-deleted.
  - `403 Forbidden` with `reason="expired"` — TTL elapsed; show the expired-link UI and offer a request-link flow.
  - `403 Forbidden` with `reason="revoked"` — the target user no longer has access at activation time (principals mutated after the link was issued); fall back to the same expired-link UI or show "this link is no longer valid".
- The SPA should branch on the `reason` field rather than the HTTP status alone so error copy stays stable as new reasons are added.

## Activation Keys Are Host-Agnostic (Supported)

Activation resolves the link by **key alone** — nimbus-ai never checks which host the key was opened on. Opening `https://<any-app-host>/_auth/magiclink/{key}` therefore activates the link and signs the recipient in **on that host**: app-wrapper proxies the route to Gate, and mints that host's `fbsfeaturetoken` after the session exchange. This is a **supported contract**, not an accident — one-click Launch and hub host-rewrite depend on it.

Two separate boundaries decide whether a rewritten host works. Activation is key-only, but *being signed in* on the opened host needs an access principal on that **App**, and `createAppMagicLink` grants principals per **Product** (see above) — while the cookie handoff resolves the org from the opened host.

- Supported: rewriting the activation host to any App host **of the same Product** (sibling Apps of the Product, managed subdomain ⇄ active custom domain).
- Not supported: a host of a **different Product**, even in the same org. Activation succeeds, but app-wrapper evaluates access against the *opened* App: no matching principal renders the `access-denied` page, and a `visitor`-only match hands back a visitor-level token instead of the recipient's identity.
- Not supported: a host **outside the link's org**. Same access outcome as above, plus the cookie handoff resolves the org from the *opened* host via `getAppByHost` — an unregistered host renders the generic error page, and a host registered to another org sends the recipient through that org's sign-in first. Fail loudly in the hub rather than rewriting across orgs.
- The link's pinned `appFeatureId` scopes the `featureToken` in the **activation JSON** (legacy SPA `/link` flow). On platform email links the browser token comes from the host that was actually opened, so a rewritten host still gets a usable token.
- If activation ever becomes host-bound, it must ship behind an explicit fallback flag with a long deprecation window — host rewrite is in production use today.

## Deep-Link Redirect Usage

- `redirectPath` is opaque to Gate; nimbus-ai stores it verbatim on the link row and returns it on activation.
- Always make `redirectPath` relative (`/proposals/abc`, `/invoices/123`). Absolute URLs would let the inviter point the activation to an unrelated origin.
- The SPA is responsible for sanitizing `redirectPath` before navigating (reject schemes, reject `//host…` patterns) — Gate does not enforce this.
- Pair `redirectPath` with the email subject the owner sends so the deep page matches the user's expectation ("View your proposal" → `/proposals/abc`).

## Binding A Link To An App Entity (`meta`)

- `meta` is an optional **opaque** string (≤ 4 KB UTF-8) on `createAppMagicLink` / `bulkCreateAppMagicLinks`. The platform never interprets it — it is stored on the link row and echoed back byte-for-byte at activation. Use it to bind a link to an app-side entity (e.g. an invitation id) instead of overloading `redirectPath` with app data.
- The 4 KB cap is enforced in **UTF-8 bytes** (not JS string length); a multibyte value over the cap is rejected with `400`.
- **Delivery is dual-channel.** Which one you read depends on the flow:
  - **Legacy SPA `/link` + `activateAppMagicLink`:** `meta` is a field in the activation JSON response (`null` when the link had none).
  - **Platform email links (`/_auth/magiclink/{key}`):** the SPA never sees the activation JSON, so Gate appends `?mlmeta=<urlencoded>` to the final app URL before the `/_auth/` handoff. Read it from `location.search` (`new URLSearchParams(location.search).get('mlmeta')`). It is placed in the query segment even when `redirectPath` carries a `#` fragment, and `mlmeta` is **reserved** — any `mlmeta` a `redirectPath` sets is replaced by the link-bound value.
- **URL visibility:** on the platform-email flow `meta` rides in the address bar (`mlmeta`), same as an id smuggled through `redirectPath`. It does not hide the payload from the browser — it only gives it a dedicated channel separate from the navigation target. Do not put secrets in `meta`.
- Omitting `meta` is fully backward compatible: legacy rows echo `meta: null`, and no `mlmeta` is added to the handoff URL.

## Expired-Link Handling

- Gate surfaces 403 with `reason=expired` exactly when `expiresAt < now()`. Show a clear message ("This link has expired") plus a button that re-runs the self-service flow (`requestAppMagicLink`) with the previously-attempted email and `redirectPath`.
- Do not retry the activate call automatically on 403 — the link is already dead. Trying again only confuses the user.
- For `reason=revoked`, do not offer the request-link flow blindly: the user's access was removed deliberately. Either show a generic "link is no longer valid" message or route them through the standard sign-in / request-access path.

## Access Model

- `createAppMagicLink`, `bulkCreateAppMagicLinks`, `revokeAppMagicLink`, and `listAppMagicLinks` all require `app_magic_link.write` plus org access. Granted by default to `owner`, `manager`, `member`, and `guest` org roles via the existing `GATE_ALL_PERMISSIONS` set.
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
- After `activateAppMagicLink`, the SPA should persist platform cookies; same-origin `/api/account/from-magic-link` then reaches the backend. Timeouts on that route after deploy usually mean **backend listen port / health** (infra), not missing visitor access.
- Do not smoke-test deployed magic-link flows with naked `curl` on `/api/health`; use the browser flow or curl with cookies saved after `/_auth/`.
- Do not call Gate `getMyOrgAccess` from the SPA for the exchange — CORS blocks `EverHelper-Session-ID`; use the backend exchange pattern below.

## App Session Exchange After Activation

**Platform email (default):** magic links in mail point at `https://{app-host}/_auth/magiclink/{key}`. After NH1, org `eversessionid` is on the **org domain** and `fbsfeaturetoken` on the **app host** — they are different registrable domains, so a same-origin app-backend call only receives `fbsfeaturetoken`.

**Mandatory exchange (Test and Production):**

1. After the platform redirect lands on `redirectPath`, SPA **immediately** `POST`s to `/api/account/from-magic-link` (same-origin; `fbsfeaturetoken` cookie attached automatically).
2. Backend calls `getMyOrgAccess` with `x-app-feature-token` from the cookie only.
3. **Fail-closed:** accept only `source === 'member'` with a real user id. Reject `source: 'none'` (visitor), `source: 'owner'`, and invalid responses.
4. Redirect to protected content (or issue app-owned session cookie in Production — below).

Without that hop the next HTML load may re-issue `fbsfeaturetoken` for a **different** Fusebase user already signed in on that browser.

**Legacy SPA `/link` + `activateAppMagicLink`:** activation JSON returns `{ featureToken, sessionToken, … }`. POST both in the **body** to `/api/account/from-magic-link`, or forward `sessionToken` as `EverHelper-Session-ID` with `x-app-feature-token`. Dual-token in the request body is still valid for this path.

### Test vs Production session policy

Choose the cookie policy based on what the app actually needs; do not auto-upgrade smoke tests to the production recipe.

**Test mode (smoke test of the magic-link flow, no Memberspace, no role gating):**

- Step 3 returns `userId` for the current request and the SPA redirects. That is the end of the exchange.
- Do **not** issue an HMAC-signed app session cookie. Do **not** create `APP_SESSION_SECRET` via `fusebase secret create`. The platform `fbsfeaturetoken` cookie is sufficient for the smoke flow; re-running the exchange on the next protected request is acceptable.

**Production mode (Memberspace, role-gated UI, or any flow that must remember the recipient across navigations):**

- After step 3, issue an **app-owned** session cookie (HMAC-signed or equivalent integrity-protected payload, bound to the resolved `userId`) and treat it as the source of truth for subsequent requests. Verify on every protected request; do not re-infer identity from `fbsfeaturetoken`.
- Register the HMAC secret here and only here: `fusebase secret create --feature <appId> --secret "APP_SESSION_SECRET:HMAC signing key for app-owned session cookie"`. Read it from `process.env.APP_SESSION_SECRET` at runtime.
- Set cookie attributes `httpOnly`, `secure`, `sameSite=Lax`, `path=/`. Rotate by changing the secret + invalidating active cookies; do not depend on Fusebase platform cookies for revocation.

### Platform token lifetime (not a durable visitor session)

- **Invite link TTL** (`createAppMagicLink` / `ttlSeconds`, default 24h, clamped 1h–7d) is how long the email link can be **activated**. It is **not** how long the signed-in session lasts after activation.
- After activation, the platform-minted `fbsfeaturetoken` (app feature token / JWE on the app host) is a **short-lived** credential — typically on the order of ~24h. Treat day-scale “stay signed in” as an **app** responsibility, not a platform cookie promise.
- There is **no** supported silent refresh/renewal of that token from the app host for magic-link visitors: post-NH1, org `eversessionid` lives only on the org domain and is **not** present on `*.thefusebase.app` (or app CNAMEs). Do **not** treat `GET …/auth/?appSuccess=…` transport failures as a broken visitor renew path — that flow is not the durable-session mechanism for magic-link clients on the app host.
- **Production portals / Memberspace:** the endorsed pattern is the **app-owned HMAC session cookie** (above). When the platform token lapses, keep serving the app session and re-derive entitlement from your store (or Gate with the backend service token) so revoke still 401s; do not bounce the user to sign-in solely because `getMyOrgAccess` returned 401 on an expired platform token after you already established an app session.
- Paths that still require a **live** platform feature token (browser→Gate/Dashboard proxy, some embeds) will fail when that token expires — keep those behind the app backend, or accept re-auth via a fresh magic link.

### Don't register non-secrets

- `FUSEBASE_ORG_ID` is **not a secret** — it lives in `fusebase.json` as `orgId` and is readable by anyone who clones the repo. Do not run `fusebase secret create … FUSEBASE_ORG_ID:…`. Read the value from `fusebase.json` (or platform-injected env where available) at app start.
- The same rule applies to other already-public values such as `productId`, the app subdomain, or Fusebase host URLs (`FBS_*` config). `fusebase secret create` is reserved for credentials that must not appear in the repo (HMAC keys, third-party API tokens, OAuth client secrets).
- A Test-mode magic-link app needs **zero** `fusebase secret create` calls for the magic-link flow itself. A Production-mode app needs exactly one: `APP_SESSION_SECRET` for the app-owned session cookie.

## Invite Lifecycle And Orphan Links

Gate exposes **create**, **bulk create**, **request**, **activate**, plus owner-side **list** (`listAppMagicLinks`) and **revoke** (`revokeAppMagicLink`).

- A `createAppMagicLink` row lives for the **24h TTL** (`expiresAt`) by default, or the clamped `ttlSeconds` when provided. Creating a new invite does not delete earlier rows; use `revokeAppMagicLink` to retire one explicitly.
- **Mail dispatch failure does not roll back** the persisted row. The API still returns `{ id, magicLinkUrl, expiresAt }` when the link is disclosable; the owner can copy `magicLinkUrl` manually. Treat a failed SMTP/log as a delivery problem, not a failed create.
- **Lost HTTP response after create:** if your app times out or crashes after Gate accepted the call, the link row **already exists** in nimbus-ai. Rolling back a local dashboard row or assuming "no response = no link" leaves an **orphan**.
- **Orphan recovery:** call `listAppMagicLinks?email=<addr>` to find the orphan's `globalId`, then `revokeAppMagicLink` it. When the row comes back without an `id`, its URL was never disclosed — revoke it by removing the recipient's access principal (`removeAppAccessPrincipal`) instead. After revoke the email can be invited again immediately with a fresh `createAppMagicLink`. Alternatively `requestAppMagicLink` re-sends a link to an email that still has access (self-service resend; 30s per-(org,app,email) cooldown).
- **Idempotent invite UX:** track `invited_at` / delivery status in your app tables; offer explicit **Resend** (`requestAppMagicLink`) and **Revoke** (`revokeAppMagicLink`), not blind `createAppMagicLink` loops.

## Working Rules

- Always inspect the exact contract with `tools_describe` or `sdk_describe` before integration work — the request and response shapes are versioned independently from this prompt.
- When wiring `createAppMagicLink`, pass the **Product id** (`productId` from `fusebase.json`) as the `appId` path segment. If a call fails with `App not found` / `404`, the most likely cause is an App id (`apps[].id` from `fusebase app list`) used where the Product id belongs — re-read the Terminology section.
- For app templates that ship with a sign-in form, wire the form to `requestAppMagicLink` and the `/link` route to `activateAppMagicLink`. Never persist the magic link `id` past activation; treat it as single-flow credential material.
- For owner-side admin UI, prefer `createAppMagicLink` with `addToAccessPrincipals=true` for first-time invites and `addToAccessPrincipals=false` for re-invites of users who already have access.
- If activation fails, do not assume `accessPrincipals` is the wrong shape; re-read the `reason` field and follow the expired-link handling rules above.
---

## Version

- **Version**: 1.9.2
- **Category**: specialized
- **Last synced**: 2026-08-12
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
