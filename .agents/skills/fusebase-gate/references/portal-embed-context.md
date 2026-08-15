---
version: "1.1.0"
mcp_prompt: none
source: "docs/portal-embed-context.md"
last_synced: "2026-07-26"
title: "Portal iframe embed context (Gate SQL RLS)"
category: specialized
---
# Portal iframe embed context (Gate SQL RLS)

> **SOURCE**: This file is copied from `docs/portal-embed-context.md` in the fusebase-gate repo. Edit that file, then run `npm run mcp:skills:generate`.

---
# Portal embed context (`portalFeatureContextToken`)

When a Fusebase app is embedded in a **portal brick iframe**, the platform passes a signed handoff JWT in the iframe URL — not user identity.

## Iframe URL shape

```
https://<app-sub>.<managed-domain>/<path>?fromFrame=true&portalFeatureContextToken=<JWT>
```

- `fromFrame=true` — enables iframe resize helpers in the app proxy; **does not** inject portal scope into the runtime app token by itself.
- `portalFeatureContextToken` — platform-signed JWT minted when the brick is saved (stored as `brick.portalFeatureToken` in portal customizer).

## JWT payload (verified claims)

After signature verification (`HS256`, `iss: fusebase-api`, `aud: portal-app-feature`):

| Claim         | Meaning                                  |
| ------------- | ---------------------------------------- |
| `type`        | Must be `portal-app-feature-context`     |
| `portalId`    | Portal global id (also JWT `sub`)        |
| `workspaceId` | Workspace bound to the portal            |
| `appId`       | **Product** id (legacy field name)       |
| `featureId`   | **App (feature)** id (legacy field name) |

There is **no end-user id** in this token. It identifies portal + product + app feature only.

The token is also **static and long-lived**: it is minted once when the brick is saved, stored in `brick.portalFeatureToken`, served identically to every viewer of the portal page, and has no `exp`. Treat it as a portal-scoped artifact, never as a per-user credential.

## Caller identity in the verify response (`userId` / `orgRole`)

`verifyPortalFeatureContextToken` also returns the **caller's** `userId` (and `orgRole` when known). These are not token claims — the token has no user. They come from the live, user-bound app session (`fbsfeaturetoken`) that authenticated the verify call, and are returned **if and only if**:

```
session.portalId === verified token portalId   &&   caller is a real user (not an anonymous visitor)
```

| Caller                                                    | `userId` in response |
| --------------------------------------------------------- | -------------------- |
| Opened the app through **this** portal's embed, signed in | present              |
| Anonymous visitor of the portal (reserved visitor id `1`) | **absent**           |
| Session bound to a **different** portal                   | **absent**           |
| Session with no portal binding (e.g. plain app URL)       | **absent**           |

**What presence proves:** the platform bound WHO to WHERE — one call yields a trusted `user × portal × app` triple, so your app does not have to staple the session lookup and the portal token together itself.

**What it does not prove:**

- **Not membership.** A portal-bound session only means the caller came in through this portal's embed handoff: app-wrapper `/_auth/` copies `portalId` out of the token it was handed and then evaluates **app** access, not portal access — so any authenticated user holding the token (static, shared by every viewer) can end up with a portal-bound session. Enforce membership through the app's `--access` principals (`portalMember` / `portalClient` / `portalManager`), which are checked against portal-service.
- **Not token ownership.** Comparing the returned `userId` with the userId your own `getMe` returns is a **tautology** — both read the same session. It is not a check that the token "belongs to" the caller; the platform already performs that binding by omitting identity on a mismatched pairing.

## What Gate injects for embedded app tokens

For normal browser **`fbsfeaturetoken`** / app JWE sessions:

| Setting               | Injected automatically?                       |
| --------------------- | --------------------------------------------- |
| `app.org_id`          | Yes (from token org scope)                    |
| `app.portal_id`       | **No** for portal-embedded app tokens         |
| `getMe().auth.scopes` | Often empty for visitor/client embed sessions |

Do **not** assume `app.portal_id` or `CurrentPortal` RLS context without an explicit verified portal id.

## Recommended end-to-end pattern

1. **SPA (iframe):** read `portalFeatureContextToken` from `window.location.search` (not from user-editable body fields alone).
2. **Forward** the token to your app backend on session/bootstrap calls.
3. **Backend:** verify the token and extract trusted `portalId`:
   - **Preferred:** Gate `verifyPortalFeatureContextToken` (`POST /{orgId}/apps/{appId}/portal-feature-context/verify`) with the app token — returns `{ portalId, workspaceId, productId, appId }`, plus `{ userId, orgRole }` for a portal-bound caller (see above).
   - Do **not** trust unsigned JWT decode in production.
4. **Isolated store SQL:** pass trusted portal scope using one of:
   - `trustedRuntimeContext.portalId` when the backend token has `isolated_store.rls.delegate` (stored in `manifest.backendOnlyGatePermissions`, minted via `/_token` / sidecar only — **not** browser gst).
   - App-specific `rlsContext` key (e.g. `req_portal_id`) mapped in RLS policies — only after verification step 3.

## Security notes

- The query param is **not** “arbitrary user input” — it is a signed platform artifact, but it **must still be verified** (signature + product/app binding).
- Never let the browser call Gate isolated-store APIs with a self-chosen `portalId` in `trustedRuntimeContext` unless the gst includes `isolated_store.rls.delegate` (backend-only; see isolated-sql docs).
- `isolated_store.rls.delegate` / `isolated_store.rls.bypass` belong in `manifest.backendOnlyGatePermissions`, not in synced `app.permissions` (would leak into browser gst).

## Related platform paths

| Component                              | Role                                                                                               |
| -------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `nx-frontend` portal customizer        | Mints token via `POST /api/portal/portal-feature-context-token`                                    |
| `app-wrapper` `auth.ts`                | Verifies token on `/_auth/` redirect; passes `portalId`/`workspaceId` into `createAppFeatureToken` |
| Gate `verifyPortalFeatureContextToken` | Backend verification/exchange for RLS bootstrap                                                    |

See also: [isolated-sql.md](./isolated-sql.md), [isolated-sql-integrator-troubleshooting.md](./isolated-sql-integrator-troubleshooting.md).
---

## Version

- **Version**: 1.1.0
- **Category**: specialized
- **Last synced**: 2026-07-26
