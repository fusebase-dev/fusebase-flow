---
version: "1.10.0"
mcp_prompt: fusebaseAuth
last_synced: "2026-08-05"
title: "Fusebase Auth For AI Apps"
category: specialized
---
# Fusebase Auth For AI Apps

> **MARKER**: `mcp-fusebase-auth-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `fusebaseAuth` for latest content.

---
## Table of contents

- [Fusebase Auth For AI Apps](#fusebase-auth-for-ai-apps)
- [Relevant Operations](#relevant-operations)
- [Architecture Rules](#architecture-rules)
- [Org Onboarding](#org-onboarding)
- [Public Registration With Org Membership](#public-registration-with-org-membership)
- [Forward The Visitor's IP On Auth Calls](#forward-the-visitors-ip-on-auth-calls)
- [Auth Operation Client Matrix](#auth-operation-client-matrix)
- [`getMyOrgAccess` `source` Field](#getmyorgaccess-source-field)
- [Gate Error Envelope Decoding](#gate-error-envelope-decoding)
- [Two Names For Feature Token](#two-names-for-feature-token)
- [Browser Token Against Guarded App APIs](#browser-token-against-guarded-app-apis)
- [App `accessPrincipals` Vs Org Membership](#app-accessprincipals-vs-org-membership)
- [Visitor Access Vs Open API (Platform Edge)](#visitor-access-vs-open-api-platform-edge)
- [Magic-Link → App Session Exchange](#magic-link--app-session-exchange)
  - [Test vs Production](#test-vs-production)
  - [Platform token lifetime (not a durable visitor session)](#platform-token-lifetime-not-a-durable-visitor-session)
  - [Non-secrets — never `fusebase secret create`](#non-secrets--never-fusebase-secret-create)
- [Challenge, 2FA, And MFA](#challenge-2fa-and-mfa)
- [Password Restore](#password-restore)
- [Google Auth](#google-auth)
- [Common Pitfalls](#common-pitfalls)

---
## Fusebase Auth For AI Apps

These operations help AI Apps add Fusebase account registration, login, logout, password restore, challenge/MFA completion, and optional org onboarding without calling auth-form directly from the browser.

## Relevant Operations

- `registerFusebaseUser` — visitor-safe email/password registration. Creates a Fusebase account through auth-form and returns a `sessionId` plus `userId` when registration succeeds. It does not add org membership. For AI App signup, send `autoConfirmEmail: true` unless product requirements explicitly need platform email confirmation.
- `registerFusebaseOrgMember` — protected registration plus org provisioning. Creates the Fusebase account, then adds the new user to the path `orgId`. Requires `org.members.write` and org access. Use this only on registration, not on login. **Does not add the user to any App's `accessPrincipals`** — org membership and app access are separate (see below). For AI App signup, send `autoConfirmEmail: true` regardless of the org role being granted.
- `setFusebaseInitialPassword` — sets the password of the **currently signed-in user**, once, with no password-restore email. Needed for an invitee whose account was pre-provisioned by an invite or an app magic link and holds a random password they never learn; `/auth/context` reports `needsInitialPassword: true` for exactly those accounts. Limits: the body is `{ password }` only, so you cannot target another account; the caller must be a user context (`fbsfeaturetoken` / session — `FBS_FEATURE_TOKEN` gets `403`); `409` once a password has been set; it mints no session and drops the account's existing ones, so follow it with `loginFusebaseUser`.
- `loginFusebaseUser` — visitor-safe email/password login. Returns `sessionId` plus `userId`, or a challenge. Never provisions org membership.
- `completeFusebaseAuthChallenge` — completes auth-form challenges such as CAPTCHA, OTP, mail OTP, two-factor, and MFA states returned by register/login.
- `requestFusebasePasswordRestore` — sends restore email through auth-form. It returns a generic `{ ok: true }` and must not be used for account enumeration.
- `requestFusebaseRestoreKey` — protected white-label reset. Mints the restore key WITHOUT sending the platform email and returns `{ key, platformResetUrl, expiresAt }` so the app can send its own branded reset mail. Requires `auth.restore_key.write` and org access; visitors get 403.
- `checkFusebasePasswordRestoreKey` and `resetFusebasePassword` — validate and complete password reset through user-service restore sessions.
- `logoutFusebaseUser` — returns the app-domain cookies that the app must clear. Gate cannot delete cookies for an AI App host.

## Architecture Rules

- All calls to auth-form must go through a backend or Gate operation. Do not `fetch()` auth-form directly from the SPA because the app host and auth host are different origins and CORS/session cookies will not behave correctly.
- The returned `sessionId` is credential material. A server/BFF should set it as an app-domain cookie such as `eversessionid` with `httpOnly`, `secure`, `sameSite=Lax`, and `path=/` where possible.
- After register, login, or challenge success, route the user to the returned `redirectPath`. Always keep redirect paths relative (`/dashboard`, `/tasks/123`) and reject absolute URLs or `//host` forms.
- When creating accounts from an AI App email/password signup flow, include `autoConfirmEmail: true` on `registerFusebaseUser` or `registerFusebaseOrgMember` so auth-form does not send a separate email-confirmation message.
- Use `registerFusebaseOrgMember` only for a brand-new registration flow. Do not add org membership during ordinary login because login must not mutate roles or downgrade existing access.
- For app access decisions after auth or provisioning, check the user's actual org/app access before unlocking protected content. Do not treat a successful write as a substitute for an access check.

## Org Onboarding

- `registerFusebaseOrgMember` path is `/:orgId/auth/fusebase/register-member`; the org comes from the path, not from user input in the body.
- Default org role is `client`. Send `orgRole` only when the app intentionally grants another role and the caller has permission to do so.
- The operation uses `org.members.write`; expose it only through a trusted app backend or a properly scoped feature token. Do not build an unauthenticated public form that can choose arbitrary org ids or roles.
- If auth-form returns a challenge during registration, complete the challenge first and retry the registration flow as appropriate. Membership is added only after an authenticated registration response includes a `userId`.

## Public Registration With Org Membership

Acceptance flows that require `registerFusebaseOrgMember` (create account **and** add org membership) use a **two-token BFF pattern**. A `403 Authenticated user-bound context is required (authType=visitor)` is **not** "the platform blocks org join" — it means Gate was called with a **visitor** token instead of the backend service token.

- **Browser → app backend** (`POST /api/account/register` or similar): the request may carry visitor `fbsfeaturetoken` / `x-app-feature-token` so the app-proxy forwards `/api/*`. That token is **not** sufficient for org membership writes.
- **App backend → Gate** (`registerFusebaseOrgMember`, `addOrgUser`): use `process.env.FBS_FEATURE_TOKEN` — the platform-issued **service token** minted at deploy with `org.members.write` (subject = app owner). In local `fusebase dev`, backend-only provisioning may use `process.env.FBS_FEATURE_TOKEN ?? process.env.GATE_MCP_TOKEN`; browser/UI must never use MCP tokens.
- Do **not** forward the incoming request's visitor cookie to Gate for `registerFusebaseOrgMember` or `addOrgUser`. Do **not** store an admin session in secrets as a workaround.
- `orgId` in the Gate path must come from `fusebase.json` (`orgId`), never from user input in the registration body.
- Grant `org.members.write` on the app feature (`fusebase sync` / redeploy) before testing registration-with-membership.
- For instant password-based onboarding, prefer `registerFusebaseOrgMember` with `autoConfirmEmail: true`. `autoConfirmClientInvite` is only for `addOrgUser` org-only client invites and does not affect auth-form account registration.
- After success, set the returned `sessionId` as an app-domain cookie and verify membership with `getMyOrgAccess` (session header + feature token as documented for user-context reads).

## Forward The Visitor's IP On Auth Calls

auth-form rate-limits registration by client IP (5 per 24h). A backend-to-Gate call carries the **app backend's** egress IP, which is shared by every visitor of the app — so without forwarding, one visitor's signups exhaust the bucket for everyone. Every SDK method takes per-call `headers`, so pass the visitor's IP through on `registerFusebaseUser`, `registerFusebaseOrgMember`, `loginFusebaseUser`, `completeFusebaseAuthChallenge` and `requestFusebasePasswordRestore`:

```ts
// visitor IP as the platform edge saw it: leftmost entry of the inbound chain
const visitorIp = (req.headers['x-forwarded-for'] ?? '').split(',')[0].trim();

const authApi = new FusebaseAuthApi(createClient({ baseUrl }));
await authApi.registerFusebaseUser({
  body: { email, password, autoConfirmEmail: true },
  ...(visitorIp ? { headers: { 'X-Forwarded-For': visitorIp } } : {}),
});
```

- Take the IP **only** from the incoming request's `X-Forwarded-For` (app-wrapper forwards it) — never from the request body or a query param, which would let a caller pick its own limiter bucket per request.
- Send the single leftmost entry, not the whole chain: intermediate hops append their own address and Gate reads the leftmost entry.
- Omit the header when the inbound request has none (local `fusebase dev`); an absent header is better than a fabricated one.
- Symptom of a missing forward: `-20` / `403` auth-form anti-abuse errors on registrations that are the first signup for that person but not for that app.

## Auth Operation Client Matrix

Use the **smallest** token that satisfies the op contract. Wrong subject → `403 token subject not allowed` or `403 Authenticated user-bound context is required (authType=visitor)`.

| Operation | Who calls | Gate client / token |
| --- | --- | --- |
| `loginFusebaseUser`, `registerFusebaseUser`, `requestFusebasePasswordRestore` | App backend BFF (visitor-safe) | `createClient({ baseUrl })` — **no** feature token |
| `registerFusebaseOrgMember`, `addOrgUser` | App backend only | `process.env.FBS_FEATURE_TOKEN` (service token with `org.members.write`) |
| `logoutFusebaseUser` | App backend on behalf of signed-in user | User-context token (`fbsfeaturetoken` / session), not the service token |
| `getMyOrgAccess` (user identity) | App backend from browser request | Request `fbsfeaturetoken` cookie — **not** `FBS_FEATURE_TOKEN` |
| `setFusebaseInitialPassword` (acts on the caller) | Browser → app backend, forwarding the invitee's request context | Request `fbsfeaturetoken` cookie / session — `FBS_FEATURE_TOKEN` gets `403` |

Never call `registerFusebaseOrgMember` / `addOrgUser` from the SPA with a visitor cookie. Never use `FBS_FEATURE_TOKEN` to answer "who is the current user?".

## `getMyOrgAccess` `source` Field

`source` is the caller's **org role** (`member`, `client`, `owner`, `none`) — not a security/trust tier. `owner` is still a live human account with org-wide powers; do not treat it as a service identity. For magic-link exchange, fail-closed on `source === 'member'` with a real `userId` when the product expects a recipient client/member — reject `none` (visitor) and unexpected `owner` unless the flow explicitly allows it.

## Gate Error Envelope Decoding

Gate BFF errors are often wrapped. Read **status + inner code**, not only the outer HTTP status:

- **`401` with `errorCode: fusebase_auth_invalid_credentials`** on login/register — wrong password or unknown account. Never retry the same credentials. (Older gate builds returned this as a **500** carrying `upstreamStatus: 401`.)
- **`401` with `errorCode: fusebase_auth_challenge_failed`** on `completeFusebaseAuthChallenge` — the OTP/MFA answer is wrong. **Do** re-prompt for the code; the challenge `state` is still usable.
- **`401` with `errorCode: fusebase_auth_challenge_expired`** on `completeFusebaseAuthChallenge` — the challenge `state` or mailed code expired. Restart from login/register to get a fresh challenge.
- **`400` with `errorCode: restore_key_invalid`** on `resetFusebasePassword` — the restore key is unknown, expired or already used. Mint a new one; retrying the same key never succeeds.
- **`400` with `errorCode: password_rejected`** on `resetFusebasePassword` — the key is fine, the new password failed platform rules; `message` carries the rule to show the user.
- **`-20` / `403` from auth-form anti-abuse** — registration or login blocked by rate/abuse policy. **Not transient**; backoff, surface human copy, do not spin retry loops.
- **`403 token subject not allowed`** — wrong token type for the op (see matrix above), not "platform denies org join".
- **`403` with `authType=visitor` on org writes** — backend forwarded visitor `fbsfeaturetoken` instead of `FBS_FEATURE_TOKEN`.

## Two Names For Feature Token

- **`window.FBS_FEATURE_TOKEN` / cookie `fbsfeaturetoken`** (browser): JWE from `/_auth/` for SPA and app-proxy, embedding a Gate token with the app's non-backend-only permissions. Cannot perform `org.members.write`.
- **`process.env.FBS_FEATURE_TOKEN`** (backend pod env): deploy-time Gate **service** token with app permissions. Required for privileged provisioning from trusted BFF routes.

## Browser Token Against Guarded App APIs

The platform-minted browser `fbsfeaturetoken` is a JWE that **embeds a Gate service token**, and Gate resolves the request against that embedded token's scopes and permissions — including `client:<productId>`. So a browser token **does** satisfy `x-fusebase-allowed-callers` for its own product: the cookie is not HttpOnly (also `window.FBS_FEATURE_TOKEN`), so any end user can replay it from devtools. Only `x-fusebase-required-permissions` is browser-proof, because `app_api.*` capabilities are backend-only and the browser mint omits them. **Pair the two guards on anything sensitive** — `allowedCallers` alone is a product filter, not an authorization check.

Two supported ways to run a guarded operation for an end user:

- **Dual-token (works today):** the app backend calls `callAppApi` with its own service token (`process.env.FBS_FEATURE_TOKEN`) and carries the user identity itself, after verifying the browser token.
- **On-behalf-of (preferred):** the app backend calls `callAppApi` with its service token and passes the user's `fbsfeaturetoken` as `onBehalfOfUserToken`. Gate verifies it fail-closed and forwards `X-Fusebase-Verified-User-Id` / `X-Fusebase-Verified-User-Source: obo` to the runtime instead of hand-rolling forwarding.

The app-wrapper proxy strips inbound `X-Fusebase-Verified-*` headers it cannot prove came from Gate, so they cannot be forged **through the app URL** — including on the auth-exempt `/api/webhooks/*` paths. Your backend's platform-provisioned deploy FQDN is a separate public origin that the proxy does not front, and the backend cannot tell the two apart — so OBO removes the dual-token plumbing, **not** the trust requirement. Do not treat a verified header as a bearer credential for anything you would not expose to any authenticated peer in the org.

Denials are an honest **403** with a machine-readable `errorCode` under `data` in the error body (`app_api_caller_not_allowed`, `app_api_missing_permissions`, `app_api_operation_private`, `obo_user_token_org_mismatch`; an invalid OBO token is `401 obo_user_token_invalid`, an unknown or unpublished operation is `404 app_api_operation_not_found`, and a transient verifier outage is `503 obo_verification_unavailable`), never a 500-wrapped 404. Branch on `errorCode`, not on the message.

Minting scopes or permissions into browser tokens is **not** the recommended path and is deliberately unsupported — the blast radius is every app host that already holds such a cookie. Use OBO.

## App `accessPrincipals` Vs Org Membership

Org membership (`registerFusebaseOrgMember`, `addOrgUser`, org invites) and **App** access (`accessPrincipals` on each host-bearing App, set via `fusebase app create/update --access`) are **different** control planes. Both may be required for the same person.

- `registerFusebaseOrgMember` (and org-service membership writes) **never** append `{ type: user }` or `orgRole:*` principals to an App. A user can be `orgRole:member` in the org and still have **no** self-service magic-link email if the App's principals list does not include their role.
- `requestAppMagicLink` (see the `appMagicLinks` prompt) dispatches mail only when the email resolves to a user who **matches** the App's current `accessPrincipals` (`user`, matching `orgRole`, or `orgGroup`). It always returns `{ ok: true }` — absence of mail is not an API error.
- `createAppMagicLink` with `addToAccessPrincipals: true` (default) adds a **user** principal and is the usual path for first-time client invites; that is separate from org registration.
- When an App ships a **Memberspace** or role-gated area plus self-service magic links, set principals at create time, e.g. `fusebase app create … --access=visitor,orgRole:client,orgRole:member,orgRole:manager,orgRole:owner` (adjust roles to the product). `--access=visitor` alone does **not** imply org members can request links.
- An App with **empty** `accessPrincipals` falls back to "any org member" for self-service; a non-empty list (including only `visitor`) is evaluated strictly — do not assume org membership alone is enough.

## Visitor Access Vs Open API (Platform Edge)

`fusebase app create/update --access=visitor` means **unauthenticated users may open the App host** and receive a **visitor-scoped** `fbsfeaturetoken` — it does **not** mean the App's `/api/*` routes are callable without any platform token.

- The deployed **app-wrapper** proxy gates `/api/*` (and most non-static HTML) on a valid `fbsfeaturetoken` cookie (or equivalent). Without it, the browser is redirected through `/_auth/` (visitor JWE issuance) before API traffic reaches the App backend.
- Typical first visit: `GET /` or `/link` → `302 /_auth/?url=…` → `Set-Cookie: fbsfeaturetoken=<visitor JWE>` → redirect back → SPA loads. Browsers follow this automatically; **bare `curl` / fetch without a cookie jar** on `/api/health` will show `302` — that is expected, not an App bug.
- `--access=visitor` is about **who may obtain** a visitor token after the platform auth dance, not about exposing anonymous REST on the App subdomain.
- Do not treat `401`/`302` on `/api/*` before activation as "session expired" for visitor Apps. After `activateAppMagicLink`, platform cookies exist and `/api/*` is forwarded; identity for Memberspace still requires the app-backend exchange (below).
- Smoke tests: use a real browser, Playwright, or `curl` with `-c/-b` after one full `/_auth/` pass — not "`/api/health` without cookies must return 200".

## Magic-Link → App Session Exchange

For Apps that use `requestAppMagicLink` / platform `/_auth/magiclink/{key}` (load the `appMagicLinks` prompt for wire details), auth success is **not** complete when the platform redirect alone finishes.

**Cookie model after NH1 (platform email links):** org `eversessionid` on the **org domain**; recipient-scoped `fbsfeaturetoken` on the **app host**. Same-origin app-backend calls only receive `fbsfeaturetoken` — do not expect `eversessionid` on the app host.

**Mandatory for every magic-link app, Test and Production:**

- After the platform `/_auth/magiclink/{key}` redirect, SPA **immediately** `POST`s to `/api/account/from-magic-link` before navigating to protected routes. Platform `fbsfeaturetoken` can be overwritten on the next HTML request by the app proxy to match whichever Fusebase user is logged into the **browser**, not the magic-link recipient.
- Backend calls `getMyOrgAccess` with `x-app-feature-token` from the `fbsfeaturetoken` cookie. The app-api proxy resolves the recipient from the JWE minted by app-wrapper.
- **Fail-closed:** accept only `source === 'member'` with a real user id. Reject `source: 'none'` (visitor), `source: 'owner'`, and invalid responses.
- **Legacy `/link` + `activateAppMagicLink`:** POST `{ featureToken, sessionToken }` in the body to `/api/account/from-magic-link`, or forward `sessionToken` as `EverHelper-Session-ID` with `x-app-feature-token`.

### Test vs Production

Split the recipe so smoke tests don't grow the production attack surface and don't introduce secrets the app does not actually need:

**Test mode (smoke test, no Memberspace, no role-gated UI):**

- The mandatory exchange above is enough — `getMyOrgAccess` + redirect.
- Do **not** issue an app-owned HMAC-signed session cookie. Do **not** register `APP_SESSION_SECRET` or any other HMAC secret via `fusebase secret create`. The platform `fbsfeaturetoken` cookie is sufficient for the smoke flow; re-call the exchange on every protected page-load if needed.
- Treat the `userId` returned by `getMyOrgAccess` as the source of truth for the current request only; do not persist it server-side.

**Production mode (Memberspace, role-gated areas, any flow where the app must remember which user opened the link across navigations):**

- After the mandatory exchange, issue an **app-owned** session cookie (HMAC-signed or equivalent integrity-protected payload, bound to `userId`) and use it as the source of truth for subsequent requests. Verify on every request — do not infer the recipient from `eversessionid` or `fbsfeaturetoken` after the initial redirect.
- Register the HMAC secret only here, with `fusebase secret create --feature <appId> --secret "APP_SESSION_SECRET:HMAC signing key for app-owned session cookie"`, then read it from `process.env.APP_SESSION_SECRET` in the backend.
- Set the cookie `httpOnly`, `secure`, `sameSite=Lax`, `path=/`. Rotate by changing the secret + invalidating live cookies; do not rely on Fusebase cookies for revocation.

### Platform token lifetime (not a durable visitor session)

- **Invite link TTL** (`createAppMagicLink` / `ttlSeconds`, default 24h, clamped 1h–7d) is how long the email link can be **activated**. It is **not** how long the signed-in session lasts after activation.
- After activation, the platform-minted `fbsfeaturetoken` on the app host is a **short-lived** credential (typically ~24h). Day-scale “stay signed in” is an **app** responsibility via the Production HMAC session cookie — not a platform cookie promise.
- There is **no** supported silent refresh of that token from the app host for magic-link visitors (post-NH1 org `eversessionid` is org-domain only). Do **not** treat `…/auth/?appSuccess=…` failures as a broken visitor renew path.
- When the platform token lapses after an app session exists, keep the app session and re-check entitlement from your store / service token; do not treat expired-platform-token `getMyOrgAccess` 401 as “user signed out”.

### Non-secrets — never `fusebase secret create`

- `FUSEBASE_ORG_ID` is **not a secret** — it lives in `fusebase.json` (`orgId`) and is readable in plain text by anyone who can clone the app. Do not run `fusebase secret create … FUSEBASE_ORG_ID:…`. Read the value from `fusebase.json` (or platform-injected env if the deployed runtime exposes it) at app start.
- The same rule applies to other already-public values such as the app's subdomain, the `productId`, or Fusebase host URLs. `fusebase secret create` is reserved for things that must not be visible to the agent or anyone reading the repo (HMAC keys, third-party API tokens, OAuth client secrets).
- If the app only needs a Test-mode exchange, the result is that **no** `fusebase secret create` call is required for the magic-link flow itself.

## Challenge, 2FA, And MFA

- `loginFusebaseUser` and `registerFusebaseUser` can return `status: "challenge_required"` with `challenge.type` and `challenge.state` instead of a session.
- Render the required challenge UI, then call `completeFusebaseAuthChallenge` with `{ state, answer }`.
- OTP/MFA challenge success returns `status: "authenticated"` and a session. A failed or reissued challenge can return another `challenge_required` response.
- Never log passwords, challenge answers, or session ids. Flow ids are fine for diagnostics; credential values are not.

## Password Restore

- `requestFusebasePasswordRestore` forwards `email` as auth-form `login`, and `portalId` / `workspaceId` when the app needs branded restore routing.
- The restore request intentionally returns only `{ ok: true }`. The UI should always show generic copy such as "If an account exists, we sent instructions."
- **Restore-link format:** the platform email's link is built by the mail template, not by Gate. Its shape is not part of this contract — never hardcode or parse it. If the app needs a reset URL it controls, use `requestFusebaseRestoreKey` and send your own email.
- **`portalId` / `workspaceId`:** set BOTH to apply portal white-label branding — user-service resolves the portal domain itself, uses the portal name, and sends the `restore_portal_password` template. Setting only one has no branding effect.
- **White-label reset (send your own email):** call `requestFusebaseRestoreKey` (POST `/:orgId/auth/fusebase/restore-key`, service token with `auth.restore_key.write`). It returns the raw `key` and does NOT email the recipient, so the app sends a single branded reset mail. The key is NOT bound to a URL — host your reset page anywhere and embed the key however you like, e.g. `${yourApp}/account/new-password?t=<key>`; that page then calls `checkFusebasePasswordRestoreKey` and `resetFusebasePassword`. Same TTL and one-time-use as the email flow. Use the returned `platformResetUrl` if you have no reset page of your own. Backend only — the app-wrapper `fbsfeaturetoken` cookie also resolves as a token subject, so the calling credential must never be reachable from frontend code.
- **Who you may target:** the service token must be scoped to the `orgId` in the path (403 otherwise), and the target email must belong to that org and to NO other org — a key resets the GLOBAL Fusebase password, so users with a footprint elsewhere (another org, or a private org from self-registration) are refused with 404. Users your app provisioned via magic link work; a person who already had a Fusebase account does not.
- Use `checkFusebasePasswordRestoreKey` for the reset screen and `resetFusebasePassword` to set the new password. These depend on `USER_SERVICE_URL` being configured for Gate.

## Google Auth

- Google auth is still an auth-form redirect/OpenID flow, not a Gate JSON credential exchange. Use auth-form's Google/OpenID route or embedded auth-form template with Fusebase's configured Google Client ID.
- After the redirect flow produces a Fusebase session, the AI App should persist the app-domain session cookie and route to the requested relative path using the same redirect rules as email/password login.
- Do not introduce a second Google Client ID in the AI App unless the Fusebase auth-form/OpenID configuration has explicitly been changed to trust it.

<% if (it.flags?.includes("direct-openid-login")) { %>
### Google / Microsoft direct login (app-wrapper OpenID routes)

For a one-click "Continue with Google / Microsoft" button on the **platform** OAuth client ids (apps must not register their own), link to the **app-wrapper** routes on the app host:

```
https://<app-host>/_auth/openid/google?appSuccess=<urlencoded same-app-host URL>
https://<app-host>/_auth/openid/microsoft?appSuccess=<urlencoded same-app-host URL>
```

<% } %>
## Common Pitfalls

- Do not put these app routes under `/api/auth/*` in generated app backends; deployed platform proxies may reserve that prefix. Prefer `/api/account/*` or another app-owned prefix.
- Do not confuse Fusebase platform cookies with app-domain cookies. The app must own its fallback session cookie on its own domain.
- Do not expect multi-day “stay signed in” from `fbsfeaturetoken` alone, and do not treat ~24h expiry after magic-link activation as a platform outage — use the Production app-owned HMAC session cookie (see § Platform token lifetime).
- Do not call org provisioning from login. If a user already has a stronger role, a login-time provisioning call can accidentally change the intended access model.
- Do not call `registerFusebaseOrgMember` or `addOrgUser` from the SPA directly to Gate, and do not forward visitor `fbsfeaturetoken` from the signup request into those ops.
- Do not downgrade a flow that requires org membership to account-only (`registerFusebaseUser`) without explicit product approval — `registerFusebaseUser` never adds org membership.
- `403` with `authType=visitor` on org-write ops: fix backend token wiring (`FBS_FEATURE_TOKEN` + `org.members.write`), not platform policy.
- Do not expose `sessionId` to localStorage. Prefer server-set cookies; if a pure SPA has to handle it, keep the lifetime short and document the tradeoff.
---

## Version

- **Version**: 1.10.0
- **Category**: specialized
- **Last synced**: 2026-08-05
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
