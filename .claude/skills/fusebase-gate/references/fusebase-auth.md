---
version: "1.1.0"
mcp_prompt: fusebaseAuth
last_synced: "2026-05-22"
title: "Fusebase Auth For AI Apps"
category: specialized
---
# Fusebase Auth For AI Apps

> **MARKER**: `mcp-fusebase-auth-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `fusebaseAuth` for latest content.

---
## Fusebase Auth For AI Apps

These operations help AI Apps add Fusebase account registration, login, logout, password restore, challenge/MFA completion, and optional org onboarding without calling auth-form directly from the browser.

## Relevant Operations

- `registerFusebaseUser` — visitor-safe email/password registration. Creates a Fusebase account through auth-form and returns a `sessionId` plus `userId` when registration succeeds. It does not add org membership.
- `registerFusebaseOrgMember` — protected registration plus org provisioning. Creates the Fusebase account, then adds the new user to the path `orgId`. Requires `org.members.write` and org access. Use this only on registration, not on login. **Does not add the user to any App's `accessPrincipals`** — org membership and app access are separate (see below).
- `loginFusebaseUser` — visitor-safe email/password login. Returns `sessionId` plus `userId`, or a challenge. Never provisions org membership.
- `completeFusebaseAuthChallenge` — completes auth-form challenges such as CAPTCHA, OTP, mail OTP, two-factor, and MFA states returned by register/login.
- `requestFusebasePasswordRestore` — sends restore email through auth-form. It returns a generic `{ ok: true }` and must not be used for account enumeration.
- `checkFusebasePasswordRestoreKey` and `resetFusebasePassword` — validate and complete password reset through user-service restore sessions.
- `logoutFusebaseUser` — returns the app-domain cookies that the app must clear. Gate cannot delete cookies for an AI App host.

## Architecture Rules

- All calls to auth-form must go through a backend or Gate operation. Do not `fetch()` auth-form directly from the SPA because the app host and auth host are different origins and CORS/session cookies will not behave correctly.
- The returned `sessionId` is credential material. A server/BFF should set it as an app-domain cookie such as `eversessionid` with `httpOnly`, `secure`, `sameSite=Lax`, and `path=/` where possible.
- After register, login, or challenge success, route the user to the returned `redirectPath`. Always keep redirect paths relative (`/dashboard`, `/tasks/123`) and reject absolute URLs or `//host` forms.
- Use `registerFusebaseOrgMember` only for a brand-new registration flow. Do not add org membership during ordinary login because login must not mutate roles or downgrade existing access.
- For app access decisions after auth or provisioning, check the user's actual org/app access before unlocking protected content. Do not treat a successful write as a substitute for an access check.

## Org Onboarding

- `registerFusebaseOrgMember` path is `/:orgId/auth/fusebase/register-member`; the org comes from the path, not from user input in the body.
- Default org role is `client`. Send `orgRole` only when the app intentionally grants another role and the caller has permission to do so.
- The operation uses `org.members.write`; expose it only through a trusted app backend or a properly scoped feature token. Do not build an unauthenticated public form that can choose arbitrary org ids or roles.
- If auth-form returns a challenge during registration, complete the challenge first and retry the registration flow as appropriate. Membership is added only after an authenticated registration response includes a `userId`.

## App `accessPrincipals` Vs Org Membership

Org membership (`registerFusebaseOrgMember`, `addOrgUser`, org invites) and **App** access (`accessPrincipals` on each host-bearing App, set via `fusebase app create/update --access`) are **different** control planes. Both may be required for the same person.

- `registerFusebaseOrgMember` (and org-service membership writes) **never** append `{ type: user }` or `orgRole:*` principals to an App. A user can be `orgRole:member` in the org and still have **no** self-service magic-link email if the App's principals list does not include their role.
- `requestAppMagicLink` (see the `appMagicLinks` prompt) dispatches mail only when the email resolves to a user who **matches** the App's current `accessPrincipals` (`user`, matching `orgRole`, or `orgGroup`). It always returns `{ ok: true }` — absence of mail is not an API error.
- `createAppMagicLink` with `addToAccessPrincipals: true` (default) adds a **user** principal and is the usual path for first-time client invites; that is separate from org registration.
- When an App ships a **Memberspace** or role-gated area plus self-service magic links, set principals at create time, e.g. `fusebase app create … --access=visitor,orgRole:client,orgRole:member,orgRole:manager,orgRole:owner` (adjust roles to the product). `--access=visitor` alone does **not** imply org members can request links.
- An App with **empty** `accessPrincipals` falls back to "any org member" for self-service; a non-empty list (including only `visitor`) is evaluated strictly — do not assume org membership alone is enough.

## Magic-Link → App Session Exchange

For Apps that use `requestAppMagicLink` / `activateAppMagicLink` (load the `appMagicLinks` prompt for wire details), auth success is **not** complete when the SPA sets platform cookies alone.

- After `activateAppMagicLink`, pass **both** `featureToken` and `sessionToken` to a trusted app backend **before** `window.location.replace` to a protected route. Platform cookie `fbsfeaturetoken` can be overwritten on the next HTML request by the app proxy to match whichever Fusebase user is logged into the **browser**, not the magic-link recipient.
- User identity on Gate calls such as `getMyOrgAccess` requires forwarding `sessionToken` as header `EverHelper-Session-ID` together with `x-app-feature-token` (or your app's equivalent). **`featureToken` alone does not resolve the authenticated user** on those endpoints.
- Recommended pattern: `POST /api/account/from-magic-link` with `{ featureToken, sessionToken }` in the **body** → backend builds a Gate client with both credentials → `getMyOrgAccess` → issue an **app-owned** session cookie (HMAC-signed, bound to `userId`) → redirect. Do not infer the recipient from `eversessionid` or `fbsfeaturetoken` alone after redirect.
- Do not call `getMyOrgAccess` with only the app feature token for visitors or fresh magic-link users — that can return the **token owner's** identity (e.g. the app owner in dev, or a stale browser session in prod). Fail closed: show the sign-in / request-link UI instead.

## Challenge, 2FA, And MFA

- `loginFusebaseUser` and `registerFusebaseUser` can return `status: "challenge_required"` with `challenge.type` and `challenge.state` instead of a session.
- Render the required challenge UI, then call `completeFusebaseAuthChallenge` with `{ state, answer }`.
- OTP/MFA challenge success returns `status: "authenticated"` and a session. A failed or reissued challenge can return another `challenge_required` response.
- Never log passwords, challenge answers, or session ids. Flow ids are fine for diagnostics; credential values are not.

## Password Restore

- `requestFusebasePasswordRestore` forwards `email` as auth-form `login` and may pass `customAuthUrl`, `portalId`, and `workspaceId` when the app needs branded restore routing.
- The restore request intentionally returns only `{ ok: true }`. The UI should always show generic copy such as "If an account exists, we sent instructions."
- Use `checkFusebasePasswordRestoreKey` for the reset screen and `resetFusebasePassword` to set the new password. These depend on `USER_SERVICE_URL` being configured for Gate.

## Google Auth

- Google auth is still an auth-form redirect/OpenID flow, not a Gate JSON credential exchange. Use auth-form's Google/OpenID route or embedded auth-form template with Fusebase's configured Google Client ID.
- After the redirect flow produces a Fusebase session, the AI App should persist the app-domain session cookie and route to the requested relative path using the same redirect rules as email/password login.
- Do not introduce a second Google Client ID in the AI App unless the Fusebase auth-form/OpenID configuration has explicitly been changed to trust it.

## Common Pitfalls

- Do not put these app routes under `/api/auth/*` in generated app backends; deployed platform proxies may reserve that prefix. Prefer `/api/account/*` or another app-owned prefix.
- Do not confuse Fusebase platform cookies with app-domain cookies. The app must own its fallback session cookie on its own domain.
- Do not call org provisioning from login. If a user already has a stronger role, a login-time provisioning call can accidentally change the intended access model.
- Do not expose `sessionId` to localStorage. Prefer server-set cookies; if a pure SPA has to handle it, keep the lifetime short and document the tradeoff.
---

## Version

- **Version**: 1.1.0
- **Category**: specialized
- **Last synced**: 2026-05-22
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
