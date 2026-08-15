---
name: handling-authentication-errors
description: "Required patterns for auth and session errors in Fusebase Apps: AppTokenValidationError (401) on platform tokens, and backend session probes (/api/account/me) for SaaS apps with httpOnly cookies. Use when implementing auth error handling, AuthExpiredModal, session bootstrap on load, or global API error handlers."
---

# Handling Authentication Errors

Apps need **two** related but distinct patterns:

1. **Platform app token** (`fbsfeaturetoken` / `x-app-feature-token`) — `AppTokenValidationError` on Gate/Dashboard proxy calls.
2. **App-owned session** (httpOnly cookie, e.g. `app_session`) — backend `/api/account/me` (or equivalent) on load.

Do **not** treat every failed fetch as “logged out”. That lies to the user when the backend is restarting (deploy), the proxy returns 502, or the network blips.

---

## Session probe invariant (backend SaaS apps)

Any SPA that boots auth from **`GET /api/account/me`** (or similar) **MUST** follow this table:

| Response on session check | Meaning | UI action |
| ------------------------- | ------- | --------- |
| **`401`** | Session rejected by backend | Show login / anon state |
| **`403`** with known business code (`membership_revoked`, `tenant_suspended`, …) | Authenticated but blocked | Dedicated blocked screen |
| **Everything else** (502/503/504, 5xx, network error, timeout, aborted) | **No verdict** — server may be down | **Retry** (see below), then “Can't reach server” + Try again. **Do not** clear session cookie or force login |

**A timeout on the *first* call after idle or deploy is a cold start, not a logout.** Retry once
with the full deadline, then report "Can't reach server" — never clear the session. Timeout
sizing: skill **app-backend** § Cold Starts (Scale-to-Zero).

### Anti-pattern (never ship)

```typescript
// BAD — treats deploy blip as logout
catch (e) {
  if (e.code !== 'tenant_suspended' && e.code !== 'membership_revoked') {
    setAuth({ status: 'anon' }) // ← 502 during fusebase deploy looks like logout
  }
}
```

### Required pattern

```typescript
type SessionVerdict = 'authenticated' | 'anon' | 'blocked' | 'unknown'

async function probeSession(): Promise<SessionVerdict> {
  const res = await fetch('/api/account/me', { credentials: 'include' })
  if (res.status === 401) return 'anon'
  if (res.status === 403) {
    const body = await res.json().catch(() => ({}))
    if (body.code === 'membership_revoked' || body.code === 'tenant_suspended') return 'blocked'
    return 'unknown' // do not assume logout
  }
  if (!res.ok) return 'unknown'
  return 'authenticated'
}

async function probeSessionWithDeployTolerance(): Promise<SessionVerdict> {
  const delays = [0, 400, 1200] // ms — survives fusebase deploy pod restart window
  let last: SessionVerdict = 'unknown'
  for (const ms of delays) {
    if (ms) await new Promise((r) => setTimeout(r, ms))
    try {
      const v = await probeSession()
      if (v !== 'unknown') return v
      last = v
    } catch {
      last = 'unknown'
    }
  }
  return last
}
```

On `unknown`: show a **transient error** surface (“Can't reach the server”, Retry). Keep the httpOnly session cookie untouched so the next successful probe restores the user without a false login screen.

**SPA bootstrap checklist (backend apps):**

1. On mount: `probeSessionWithDeployTolerance()` — not a single bare `fetch`.
2. `unknown` → loading/error UI with Retry; **do not** route to login.
3. `anon` → login/register routes.
4. `authenticated` → main app shell.
5. Platform token expiry (`AuthTokenExpiredError`) is a **separate** handler — do not merge with `/api/account/me` logic.

### Why deploy tolerance matters

**`fusebase deploy` restarts the app backend.** Users who refresh during rollout may hit 502 from app-wrapper/proxy while the pod is not ready. Without retries, every deploy briefly “logs out” everyone refreshing in that window — even though `app_session` is still valid.

---

## Platform app token: `AppTokenValidationError`

All apps **MUST** handle `AppTokenValidationError` responses from the **platform** API (Gate/Dashboard proxy). When the app token expires, the API returns a 401 with this body:

```json
{
  "name": "AppTokenValidationError",
  "message": "Fail to validate app token",
  "reason": "expired"
}
```

## Implementation

## Preflight: distinguish expired token vs wrong token context

Before changing UI error handling for Gate-powered features, first verify the current feature token against Gate:

```typescript
const response = await fetch(
  'https://app-api.{FUSEBASE_HOST}/v4/api/proxy/gate-service/v1/me',
  { headers: { 'x-app-feature-token': featureToken } }
)
```

Interpretation:

- `401` with `AppTokenValidationError` -> token is actually expired/invalid
- `200` but empty or unexpected permissions/scopes -> token context is wrong for the intended flow
- valid token + later `404 NotFound` on store routes -> likely org/source-scope/store-discovery issue, not auth expiry

Do not show a Session Expired modal for plain `NotFound` or for valid-but-underprivileged tokens.

### 1. Detect `AppTokenValidationError` in API calls

The error name may appear at different nesting levels depending on the SDK. Check all of them:

```typescript
function isAppTokenValidationError(error: unknown): boolean {
  if (error && typeof error === 'object') {
    const err = error as any
    const names = [err.name, err.data?.name, err.error?.name, err.body?.name]
    return names.includes('AppTokenValidationError')
  }
  return false
}
```

Create a custom `AuthTokenExpiredError` class. In every API call's catch block, check with the function above and throw `AuthTokenExpiredError` if matched; otherwise rethrow.

### 2. Show a "Session Expired" modal

When `AuthTokenExpiredError` is caught at the UI level, display a centered modal:

- **Title**: "Session Expired"
- **Message**: "Your authentication expired, please refresh the page to authenticate again."
- **Buttons**: "Refresh page" (calls `window.location.reload()`) and "Cancel" (closes modal)

Manage modal open/close state in `App.tsx` and pass an `onAuthError` callback to child components that make API calls.

<% if (it.flags?.includes("portal-specific-apps")) { %>
## Critical: `/auth/context` Behavior

The `/auth/context` endpoint **MUST NOT** trigger `AuthTokenExpiredError` just because `user` is missing.

When an app is **public**, anonymous visitors may receive an auth context with no `user` field. This is expected — it means "not authenticated", NOT "session expired". Throwing `AuthTokenExpiredError` here causes the Session Expired modal to appear immediately for every anonymous visitor.

```typescript
type AuthContextResponse = {
  user?: {
    id: number
    email: string
  }
  org?: {
    globalId: string
  }
  // Portal context; only when opened from a portal embed — and not for every
  // embed (legacy blocks carry no token).
  // See "Portal context contract" in the app-dev-practices skill.
  runtimeContext?: {
    portalId?: string
    workspaceId?: string
  }
}

export async function fetchAuthContext(
  appToken: string
): Promise<AuthContextResponse> {
  try {
    const response = await fetch(
      'https://app-api.{FUSEBASE_HOST}/v4/api/auth/context',
      { headers: { 'x-app-feature-token': appToken } }
    )
    if (!response.ok) return {} // Do NOT throw AuthTokenExpiredError here
    return await response.json()
  } catch {
    return {}
  }
}
```

### Rule of thumb

- **`/auth/context` with missing `user`** → treat as anonymous/guest
- **`/auth/context` request failure** → handle gracefully without forcing "Session Expired"
- **Dashboard/data API 401 with `AppTokenValidationError`** → throw `AuthTokenExpiredError` (session expired)
<% } else { %>
## Critical: `/users/me` Exception

The `/users/me` endpoint **MUST NOT** trigger `AuthTokenExpiredError`.

When an app is **public**, anonymous visitors receive a 401 from `/users/me`. This is expected — it means "not authenticated", NOT "session expired". Throwing `AuthTokenExpiredError` here causes the Session Expired modal to appear immediately for every anonymous visitor.

```typescript
export async function fetchCurrentUser(
  appToken: string
): Promise<{ id: number; email: string } | null> {
  try {
    const response = await fetch(
      'https://app-api.{FUSEBASE_HOST}/v4/api/users/me',
      { headers: { 'x-app-feature-token': appToken } }
    )
    if (!response.ok) return null // Do NOT throw AuthTokenExpiredError
    return await response.json()
  } catch {
    return null
  }
}
```

### Rule of thumb

- **`/users/me` 401** → return `null` (user is anonymous/guest)
- **Dashboard/data API 401 with `AppTokenValidationError`** → throw `AuthTokenExpiredError` (session expired)
<% } %>

## Quick reference

| Layer | Endpoint | 401 means | 5xx / network means |
| ----- | -------- | --------- | ------------------- |
| Platform token | Gate/Dashboard via `app-api` proxy | Token expired → refresh page modal | Transient — retry, not logout |
| App session cookie | `/api/account/me` (your backend) | Not logged in → login screen | Transient — retry + “server unavailable”, **keep cookie** |

## `getMe` status `0` (network/CORS) — wrong backend host, not auth

A `getMe`/Gate call failing with HTTP status **0** is almost never an auth
problem: the request left for the **wrong platform host** (typically a
build-time `VITE_FUSEBASE_HOST`-style constant baked from another backend)
and died on network/CORS. Fix the host resolution — see “Runtime host
resolution” in the project `AGENTS.md`: same-origin relative paths first,
otherwise derive from `window.location.hostname` or `/fusebase-env.json`
(`backend` field), never from build-time env in the frontend.

**Never let a failed `getMe` block the whole app load.** When
`/fusebase-env.json` is present, `orgId`/`appId` are already known — render
the shell and confine the auth error to the affected area.

---

## Same-origin `/api/*` and the platform proxy

### Feature token source (cookie, not embed)

For same-origin `fetch('/api/…')`, the browser sends the **`fbsfeaturetoken` cookie** automatically. The platform rotates this cookie; an embedded `window.FBS_FEATURE_TOKEN` from the initial HTML **does not**.

- **Read order:** cookie `fbsfeaturetoken` first; treat `window.FBS_FEATURE_TOKEN` as bootstrap-only (first paint), never as the live token after navigation.
- **Do not** send `x-app-feature-token` on same-origin `/api/*` unless you have a deliberate cross-origin reason. The scaffold pattern is bare `fetch('/api/items', { credentials: 'include' })` — the proxy authenticates from the cookie.
- **Do not retry** opaque redirects or 302 chains on mutations — a stale token will not heal on retry.

### Proxy returns `302` on API requests (not `401`)

Today the app-wrapper may answer **invalid/expired session on `/api/*`** with `302 Location: …/auth/?appSuccess=…` instead of `401` JSON. For `fetch()` this is catastrophic:

- Default `fetch` follows the redirect → cross-origin CORS → `TypeError: NetworkError` with **no status, no body**
- The app cannot distinguish “token dead” from “server down”

**Workaround until platform fix ([NIM-42325](https://nimbusweb.atlassian.net/browse/NIM-42325)):**

```typescript
const res = await fetch('/api/tenant/invites', {
  method: 'POST',
  credentials: 'include',
  redirect: 'manual', // see opaqueredirect instead of silent CORS failure
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
  body: JSON.stringify(payload),
})
if (res.type === 'opaqueredirect' || res.status === 302) {
  // Probe session — do not assume logout from redirect alone
  const verdict = await probeSessionWithDeployTolerance()
  if (verdict === 'anon') showAuthExpiredModal()
  else showTransientError()
}
```

`redirect: 'manual'` is **self-defense**, not approval of the design. After NIM-42325 lands, keep handling `401` explicitly; `opaqueredirect` should become rare on `/api/*`.

### Proxy slowdown windows

Under load, the proxy may return a redirect **after it already forwarded the request** to your backend. Symptom: mutation “failed” in the UI but side effect happened; or `GET /me` flips to anon for a few seconds with a valid cookie.

- On `opaqueredirect` / ambiguous auth failure: **poll** `probeSessionWithDeployTolerance()` (~7s total), do not clear cookies on the first miss.
- On failed **mutations**: **reconcile with server state** (list/read) before offering retry — the write may have succeeded.
