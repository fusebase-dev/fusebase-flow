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

| Claim | Meaning |
| ----- | ------- |
| `type` | Must be `portal-app-feature-context` |
| `portalId` | Portal global id (also JWT `sub`) |
| `workspaceId` | Workspace bound to the portal |
| `appId` | **Product** id (legacy field name) |
| `featureId` | **App (feature)** id (legacy field name) |

There is **no end-user id** in this token. It identifies portal + product + app feature only.

## What Gate injects for embedded app tokens

For normal browser **`fbsfeaturetoken`** / app JWE sessions:

| Setting | Injected automatically? |
| ------- | ---------------------- |
| `app.org_id` | Yes (from token org scope) |
| `app.portal_id` | **No** for portal-embedded app tokens |
| `getMe().auth.scopes` | Often empty for visitor/client embed sessions |

Do **not** assume `app.portal_id` or `CurrentPortal` RLS context without an explicit verified portal id.

## Recommended end-to-end pattern

1. **SPA (iframe):** read `portalFeatureContextToken` from `window.location.search` (not from user-editable body fields alone).
2. **Forward** the token to your app backend on session/bootstrap calls.
3. **Backend:** verify the token and extract trusted `portalId`:
   - **Preferred:** Gate `verifyPortalFeatureContextToken` (`POST /{orgId}/apps/{appId}/portal-feature-context/verify`) with the app token — returns `{ portalId, workspaceId, productId, appId }`.
   - Do **not** trust unsigned JWT decode in production.
4. **Isolated store SQL:** pass trusted portal scope using one of:
   - `trustedRuntimeContext.portalId` when the backend token has `isolated_store.rls.delegate` (stored in `manifest.backendOnlyGatePermissions`, minted via `/_token` / sidecar only — **not** browser gst).
   - App-specific `rlsContext` key (e.g. `req_portal_id`) mapped in RLS policies — only after verification step 3.

## Security notes

- The query param is **not** “arbitrary user input” — it is a signed platform artifact, but it **must still be verified** (signature + product/app binding).
- Never let the browser call Gate isolated-store APIs with a self-chosen `portalId` in `trustedRuntimeContext` unless the gst includes `isolated_store.rls.delegate` (backend-only; see isolated-sql docs).
- `isolated_store.rls.delegate` / `isolated_store.rls.bypass` belong in `manifest.backendOnlyGatePermissions`, not in synced `app.permissions` (would leak into browser gst).

## Related platform paths

| Component | Role |
| --------- | ---- |
| `nx-frontend` portal customizer | Mints token via `POST /api/portal/portal-feature-context-token` |
| `app-wrapper` `auth.ts` | Verifies token on `/_auth/` redirect; passes `portalId`/`workspaceId` into `createAppFeatureToken` |
| Gate `verifyPortalFeatureContextToken` | Backend verification/exchange for RLS bootstrap |

See also: [isolated-sql.md](./isolated-sql.md), [isolated-sql-rls-plan.md](./isolated-sql-rls-plan.md).
