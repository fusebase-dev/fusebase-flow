---
name: app-backend
description: "Guide for adding a backend layer (REST API, WebSockets, cron jobs) to Fusebase Apps apps. Use when: (1) An app needs a server-side API beyond the Dashboard SDK, (2) Adding REST endpoints or WebSocket support, (3) Setting up the backend/ folder structure, (4) Scheduling cron jobs for periodic tasks. The backend is OPTIONAL — only add when the app genuinely requires server-side logic."
---

# App Backend

## Multi-User Architecture

**Apps are always multi-user.** The backend serves requests from many users concurrently. Every design decision must account for this.

**Per-user vs. shared state:**

| Storage                           | Scope                               | Use for                                      |
| --------------------------------- | ----------------------------------- | -------------------------------------------- |
| httpOnly cookies                  | Per-user (per browser)              | OAuth tokens, user preferences, session data |
| Dashboard rows (keyed by user ID) | Per-user (persistent)               | User settings, saved state                   |
| Fusebase secrets / env vars       | Shared (all users)                  | API keys, service-account credentials        |
| In-memory variables               | Shared (all users, lost on restart) | Short-lived caches only                      |

**Common mistakes:**

- ❌ Storing a user's OAuth token in an env var or in-memory config → all users share one token
- ❌ Storing a user's preference in a module-level variable → last user's preference wins for everyone
- ❌ Using env vars for per-user settings or selections → same value for everyone
- ❌ Using session/token-derived values (`ft:*`, JWT pieces, rotating token IDs) as persistent row partition keys
- ✅ Store per-user data in cookies or dashboard rows keyed by user
- ✅ Use env vars only for credentials/config shared across all users (e.g. OAuth client ID/secret)

### Stable key as partition key (required)

For any persisted per-user data, derive the partition key from stable identity only:

- Use `userId`/`orgUserId` from a stable identity endpoint (`getMe`-style call)
- Normalize to a canonical key (example: `user:<userId>`) in one helper
- Use the same key on **all** read/write paths

Do not derive partition keys from runtime app/session tokens. Tokens rotate, so token-derived keys cause "missing records after relogin" while data still exists under old keys.

## When to Add a Backend

A backend is **optional**. Most apps work fine with the Dashboard SDK alone (client-side calls to the dashboard service). Only add `backend/` when the app genuinely needs:

- Custom business logic (aggregations, validations, workflows)
- Real-time push via WebSockets
- Server-side API composition or proxying
- Operations that cannot run in the browser (secrets, heavy computation)

## Sidecar Containers

Sidecars are pre-built Docker images that run alongside the app backend in the same network namespace, sharing localhost. They are useful for auxiliary services like headless browsers (Chromium, Lightpanda), caches (Redis), or other tools the backend needs to communicate with over HTTP.

### When to Use Sidecars

- The backend needs a headless browser for web scraping or PDF generation
- The backend needs a local cache or queue
- The backend needs a specialized service (image processing, ML inference) available over localhost

### Adding a Sidecar

```bash
# Add a sidecar to an app backend
fusebase sidecar add --app <appPath> --name chromium --image browserless/chrome:latest --port 9222
```

The sidecar is accessible from the backend at `http://localhost:<port>`. Max 3 sidecars per app.

**Important:** Port 3000 is reserved for the backend app. If a sidecar image defaults to port 3000, override it via env vars (e.g. `--env PORT=9222` for browserless).

### Communicating with Sidecars

Since sidecars share the same network namespace, use `localhost` to reach them:

```typescript
// In backend code — call sidecar on localhost
const response = await fetch("http://localhost:9222/json");
const data = await response.json();
```

### Sidecar Environment Variables

Each sidecar can have its own env vars (not shared with the backend):

```bash
fusebase sidecar add --app <appPath> --name redis --image redis:7 --port 6379 --env REDIS_MAXMEMORY=256mb
```

### Debugging Sidecars

Use `fusebase remote-logs runtime <appId>` to see logs from all containers. Filter to a specific sidecar:

```bash
fusebase remote-logs runtime <appId> --container chromium
```

For full sidecar documentation, see the **app-sidecar** skill.

## Total Resource Budget

Azure Container Apps caps the **sum** of CPU and memory across **all containers in one revision** (backend + every sidecar) at:

> **Max 2.0 CPU / 4.0 Gi RAM**

Configurations that exceed this cap are rejected at deploy time, even if every individual container is within an allowed tier.

### Tier reference

These are the only allowed tiers (matches the `DeploySidecarDefinition` contract in the CLI):

| Tier | CPU | Memory |
|------|-----|--------|
| small | 0.5 | 1Gi |
| medium | 1 | 2Gi |
| large | 2 | 4Gi |

### Backend container default tier

The **backend container itself always runs at `small` (0.5 CPU / 1 Gi)**. This is fixed today and is not user-configurable — only sidecars accept a `--tier` option. When you compute the total budget, always start from `0.5 CPU / 1 Gi` for the backend.

### Worked examples

**Fits** — backend (small) + chromium sidecar (medium) + redis sidecar (small):

```
backend     small    0.5 CPU / 1 Gi
chromium    medium   1.0 CPU / 2 Gi
redis       small    0.5 CPU / 1 Gi
-------------------------------------
TOTAL                2.0 CPU / 4 Gi   ✓ at the limit
```

**Exceeds** — backend (small) + chromium (medium) + lightpanda (medium):

```
backend     small    0.5 CPU / 1 Gi
chromium    medium   1.0 CPU / 2 Gi
lightpanda  medium   1.0 CPU / 2 Gi
-------------------------------------
TOTAL                2.5 CPU / 5 Gi   ✗ Azure rejects, deploy will fail
```

If a revision would exceed the cap, downgrade one of the sidecars to a smaller tier (e.g. lightpanda is intended as a lightweight browser and runs fine at `small`).

### Cron jobs are excluded

**Cron jobs do NOT count toward this limit.** Each cron job runs as its own separate container (see *Scheduled Tasks (Cron Jobs)* below) with an independent resource budget — the 2.0 CPU / 4.0 Gi cap applies only to the live backend revision (backend + sidecars), not to scheduled job containers.

- Background processing or scheduled tasks

**Do NOT add a backend** just for CRUD on dashboard data — use the Dashboard SDK directly from the SPA.

## Structure

```
apps/my-app/
  package.json              ← SPA deps (unchanged)
  vite.config.ts
  src/                      ← SPA code
  backend/                  ← backend (only if needed)
    package.json            ← backend-only deps
    tsconfig.json
    src/
      index.ts              ← entrypoint
      routes/               ← route handlers
      ws/                   ← WebSocket handlers (if needed)
```

Key points:

- `backend/` has its **own `package.json`** — keeps backend deps (Hono, ws libs) out of the SPA bundle
- **No code is shared between SPA and backend** — each side defines its own types independently. Do not create a `shared/` directory
- **Backends are not shared among apps** — only the app that owns the `backend/` folder can access it. Each app must have its own backend if it needs one; one app cannot call another app's backend.
- The SPA `package.json` remains unchanged — no backend deps leak in

## Framework: Hono

Use **Hono** for the backend. It is TypeScript-first, lightweight, and has built‑in WebSocket support. It runs on Node.js and Bun.

### backend/package.json

```json
{
  "name": "my-app-server",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsup src/index.ts --format esm --out-dir dist",
    "start": "node dist/index.js",
    "lint": "eslint . --max-warnings 0"
  },
  "dependencies": {
    "hono": "^4.x",
    "@hono/node-server": "^1.x",
    "@hono/node-ws": "^1.x"
  },
  "devDependencies": {
    "tsx": "^4.x",
    "tsup": "^8.x",
    "typescript": "^5.x"
  }
}
```

### backend/tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "dist",
    "rootDir": "."
  },
  "include": ["src"]
}
```

### backend/src/index.ts (minimal)

```typescript
import { Hono } from "hono";
import { serve } from "@hono/node-server";

const app = new Hono().basePath("/api");

app.get("/health", (c) => c.json({ ok: true }));

// Add routes:
// import { itemsRoutes } from './routes/items'
// app.route('/items', itemsRoutes)

const port = Number(process.env.BACKEND_PORT) || 3000;

serve({ fetch: app.fetch, port }, () => {
  console.log(`Server running on port ${port}`);
});

export default app;
```

### Adding WebSockets

```typescript
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { createNodeWebSocket } from "@hono/node-ws";

const app = new Hono().basePath("/api");

const { injectWebSocket, upgradeWebSocket } = createNodeWebSocket({ app });

app.get(
  "/ws",
  upgradeWebSocket((c) => ({
    onMessage(event, ws) {
      // handle incoming message
      ws.send(JSON.stringify({ echo: event.data }));
    },
    onClose() {
      console.log("Client disconnected");
    },
  })),
);

const port = Number(process.env.BACKEND_PORT) || 3000;
const server = serve({ fetch: app.fetch, port });
injectWebSocket(server);
```

## App API Contract: `openapi.json` Is Required

When backend scaffold is present, the app root contains `openapi.json`. This file is **not decorative** and it is **not generated from Hono routes automatically**.

`openapi.json` is the app's published API contract. Fusebase reads it during `fusebase deploy` and uses it for:

- App API registry publication
- Discovery in dashboard/App APIs SDK
- Gate/MCP `list/search/describe/call` flows

This means backend implementation and API contract are **two separate artifacts**:

- **Implementation**: Hono routes in `backend/src/routes/*.ts`
- **Contract**: `apps/<app>/openapi.json`

If you add or change a backend route and do not update `openapi.json`, the route may still work over HTTP, but the platform will not know about it for registry/discovery/call purposes.

### Rule: route change == `openapi.json` review

Any change to the backend route surface must be treated as incomplete until you have checked whether `openapi.json` needs to change.

Examples:

- New `app.get("/tasks")` route → add/update the corresponding path + operation in `openapi.json`
- New request/response shape → update `components.schemas`
- Route removed or renamed → remove/update the operation in `openapi.json`

Do not treat spec updates as optional follow-up documentation. They are part of the same backend change.

### Required metadata

Fusebase-specific metadata is expressed via OpenAPI `x-*` extensions.

Allowed values:

- `x-fusebase-visibility`: `org` or `private`
- `x-fusebase-execution-mode`: `sync` or `async`

Practical guidance:

- Use `x-fusebase-visibility: org` for business operations that other apps/agents in the org may discover and call
- Use `x-fusebase-visibility: private` for internal-only routes such as `health`, debug/admin endpoints, and routes that should not appear in org-wide discovery

`org` means **every member of the organization**, including **external members** (`orgRole: client` / `guest`), not just internal roles (`member`/`manager`/`owner`). A cross-app caller with any valid org role can discover and call an `org` operation — op lookup returns the operation, never 404-by-role. Enforce per-user, per-resource authorization (channel/record membership, ownership) **inside your handler** and return **200 or 403**; do not rely on `visibility` to hide an operation from a subset of org members. Use `x-fusebase-allowed-callers` to restrict which caller **project** may invoke the op — a caller id is the calling project's `productId` (`client:<productId>`), not an app id, so sibling apps of one project share it. It filters caller identity, not org role —
and not end users either: the browser `fbsfeaturetoken` embeds a Gate token with the same
`client:<productId>`, so any user of an allowed project matches it from devtools. Pair it with
`x-fusebase-required-permissions` (backend-only, never in the browser token) on anything sensitive.
- Use `x-fusebase-execution-mode: sync` for normal request/response APIs
- Use `x-fusebase-execution-mode: async` for long-running or async-style operations

### Validation and deploy checks

Before deploy, run:

```bash
fusebase api validate
```

During deploy, read the registry line carefully:

```text
Published OpenAPI registry: N operation(s) from openapi.json
```

If you added new backend operations and `N` did not increase as expected, assume `openapi.json` is stale until proven otherwise.

## Routing: `/api` is Reserved for the Backend

When an app has a backend, the `/api` path prefix is **reserved for the backend**. The SPA must not define client-side routes under `/api`.

- Backend routes: `/api/*` (REST endpoints, WebSocket upgrades)
- SPA routes: everything else (`/`, `/items/:id`, `/settings`, etc.)

## Cold Starts (Scale-to-Zero)

`backend.minReplicas` defaults to **`0`**: the backend scales to zero when idle and there is no
post-deploy warm-up, so the first request after idle *or* deploy pays a **~10s** cold start.

- Time out app → backend requests at **≥15s**; the platform ceiling is **30s** (CloudFront).
- Leave the SDKs' **30000ms** default alone — one `AbortController` spans all `fetchWithRetry`
  attempts, so retries do not get a fresh deadline.
- A slow first response is not a session error — never clear the session or force login.
- Need a fast first request? [Keep a replica warm](#keep-a-replica-warm-for-webhook-apps-backendminreplicas-1).

## Webhooks and External WebSocket Callbacks (Inbound)

Inbound integrations from external services (for example, Monday.com, GitHub, Stripe) can use regular HTTP webhooks and, when needed, WebSocket upgrades (for example, Twilio media streams). These requests typically do not carry a `fbsfeaturetoken` cookie or `x-app-feature-token` header.

The platform proxy skips app-token auth for any path under `/api/webhooks/`, including both HTTP routes and WebSocket upgrade routes.

### Keep a replica warm for webhook apps (`backend.minReplicas: 1`)

The backend **scales to zero when idle**, so a webhook can hit a cold container that
starts slower than the provider's timeout and is silently dropped.

**Rule:** if the app receives webhooks (or any always-on inbound integration), set
`backend.minReplicas: 1` in `fusebase.json` to keep one replica warm — see
[fusebase.json Backend Config](#fusebasejson-backend-config). Cap `3`; each warm replica
runs 24/7, so prefer `1`. Apps without webhooks omit it (or `0`) to keep scale-to-zero — and
must then follow [Cold Starts (Scale-to-Zero)](#cold-starts-scale-to-zero) for client timeouts.

### Register external webhooks yourself

When the app needs to receive webhooks from a third-party service (Asana, GitHub, Stripe, Monday, etc.), register the subscription with that provider **yourself** as part of the deploy — do not hand the user a `curl` / admin-UI step to run.

- Collect inputs once (provider PAT, project/resource id, etc.), then call the provider's `create webhook` HTTP API directly with the public webhook URL of the deployed app.
- Persist any returned id / signing secret via `fusebase secret create` and redeploy if the handler needs it.
- Never ask the user to `curl` your own `/api/admin/register-...` endpoint — invoke it yourself.
- Ask the user only for inputs you genuinely cannot obtain (e.g. a personal access token for a provider with no other auth path). Report the result briefly; don't enumerate the steps.

### Secret path segment

Try to come up with random and hard to guess path for webhooks, for example:

`/api/webhooks/stripe` - bad
`/api/webhooks/stripe-gja8dj21349asgj12n4asodgasdg` - good

### Webhook route

Public webhook URL: `https://{FEATURE_DOMAIN}/api/webhooks/...`

For external WebSocket integrations, use a path under `/api/webhooks/...` as well (example: `/api/webhooks/twilio-stream-<random-secret>`).

### Service-account token (`FBS_FEATURE_TOKEN`)

Use `process.env.FBS_FEATURE_TOKEN` when the backend must call Gate **without** the end-user's Fusebase session:

1. **Webhooks / cron** — no browser session at all
2. **Privileged provisioning** — public signup BFF routes that call `registerFusebaseOrgMember` or `addOrgUser` on behalf of a new visitor
3. **Isolated-store system routes** — visitor-facing writes that need `isolated_store.*` when no user session exists

`FBS_FEATURE_TOKEN` is the platform-issued service token minted at deploy (with permissions such as `org.members.write`). See **`fusebase-gate/references/fusebase-auth.md`** (§ Public Registration With Org Membership, § Two Names For Feature Token).

**Security rules:**

- Never expose `FBS_FEATURE_TOKEN` to the browser or SPA bundles.
- Do **not** use it as a fallback when resolving **who the current user is** (`getMyOrgAccess`, role-gated UI) — use the request `fbsfeaturetoken` cookie (post-NH1 magic-link flow) or `EverHelper-Session-ID` when an org session is on the same request path.
- **Do** use it inside trusted BFF handlers that perform org membership writes after validating signup input server-side.
- On routes like `POST /api/account/register`, incoming `header || cookie('fbsfeaturetoken')` is only for app-proxy auth; the Gate SDK client inside the handler must use `FBS_FEATURE_TOKEN`, not the forwarded visitor cookie.
- In local `fusebase dev`, backend-only provisioning may use `process.env.FBS_FEATURE_TOKEN ?? process.env.GATE_MCP_TOKEN`.
- User-facing routes must fail closed (`401/403`) on a missing/invalid app token — do not fall back to the service-account token.

### Deployed backend: `FBS_FEATURE_TOKEN` + isolated stores (system routes)

Public apps often need a **backend system route** (webhook, `POST /api/leads`, etc.) that writes to an isolated SQL store. The platform injects **`FBS_FEATURE_TOKEN`** (and usually **`FBS_ORG_ID`**, **`FBS_APP_ID`**) into the deployed backend env. Local dev typically has no `FBS_FEATURE_TOKEN`; use **`GATE_MCP_TOKEN`** from `.env` there instead.

**Token source (one helper, both environments):**

```typescript
const token =
  process.env.GATE_TOKEN?.trim() ||
  process.env.FBS_FEATURE_TOKEN?.trim() ||
  process.env.GATE_MCP_TOKEN?.trim();
if (!token) throw new Error("No Gate token in env");
```

**Transport — do not send deploy token as `Authorization: Bearer`**

| Environment | Token | Gate client headers |
|-------------|-------|---------------------|
| **Deployed** | `FBS_FEATURE_TOKEN` | `x-app-feature-token: <token>` only — Bearer → `401 Invalid or expired token` |
| **Local dev** | `GATE_MCP_TOKEN` | `Authorization: Bearer <token>` (MCP/service token) |

Probe both when unsure: try `feature` header first, then `bearer`; keep the transport that actually passes a capability check (below).

**`getMe` — no `health.read` grant required**

`AccessApi.getMe` is an identity introspection call. It requires a valid user or app token but **no named Gate permission** (same class as `getHealth`). Do not add `health.read` to `fusebaseGateMeta.permissions` solely to call `getMe`, and do not treat a missing `health.read` grant as the reason `getMe` fails — look for transport/header issues first.

**Gate SDK typing — use full `*Api` factories (not `Pick<>`)**

`fusebase analyze gate` / `--sync-gate-permissions` derive the published grant from static analysis. **Production code must use straightforward SDK patterns:**

```typescript
// GOOD
export function createAccessApi(token: string): AccessApi {
  return new AccessApi(createGateSdkClient(token));
}
await createAccessApi(token).getMe();
```

```typescript
// BAD — do not use in production (hides ops from analyze gate; caused prod lockouts)
type Client = Pick<AccessApi, "getMe">;
function loadMe(api: Client) { return api.getMe(); }
```

- Factory return type = full SDK class (`AccessApi`, `OrgUsersApi`, `IsolatedStoresApi`, …).
- No `Pick` / `Omit` / minimal interfaces for Gate clients.
- No destructuring Gate methods (`const { getMe } = api`).
- Before deploy: `fusebase analyze gate --feature <id>` → `usedOps` must match runtime calls.

See `fusebase-gate` skill § Gate SDK runtime patterns and `references/sdk.md` § Permission sync typing rules.

**Org id — do not derive from `getMe().scopes` on deploy**

On deploy, `getMe()` for `FBS_FEATURE_TOKEN` may return `type: "user"` with **empty `scopes` and `permissions`** even when `listIsolatedStores` / `insertIsolatedStoreSqlRow` work. Do **not** gate store access on `getMe().auth.scopes`.

```typescript
// Deployed: platform injects FBS_ORG_ID — prefer over getMe
const orgId =
  process.env.FBS_ORG_ID?.trim() ||
  (await getMeWithTransport(token, transport)).auth.scopes.find(
    (s) => s.scopeType === "org",
  )?.scopeId;
if (!orgId) throw new Error("orgId unresolved");
```

**Capability check — probe the store, not `getMe`**

Before insert/update, confirm the token can reach the target store:

1. `listIsolatedStores({ orgId, clientId: process.env.FBS_APP_ID })` (or product id from `fusebase.json`)
2. Match store by stable **`alias`**
3. Only then call structured row APIs

If step 1–2 succeed, proceed even when `getMe` looks empty.

**Diagnostics on deploy**

Deployed `/api/*` is behind the platform auth wall — tokenless `curl` from outside will not reach your handler. To debug live backend env and Gate behavior:

1. Add a temporary **`/api/_diag`** route (redact token values; log presence + `getMe` / `listIsolatedStores` / probe insert outcomes per transport).
2. Invoke it via platform **`callAppApi`** (mints a real app token and hits the live backend).

Remove `_diag` before shipping.

#### System-route backend checklist (isolated store / webhooks)

- [ ] Deployed Gate calls use **`x-app-feature-token`** for `FBS_FEATURE_TOKEN`, not Bearer.
- [ ] **`orgId`** on deploy comes from **`FBS_ORG_ID`** (or `fusebase.json` `orgId`), not from `getMe().scopes`.
- [ ] Store resolution is verified with **`listIsolatedStores` + alias**, not `getMe` permissions/scopes.
- [ ] Local dev uses **`GATE_MCP_TOKEN`** as Bearer; deploy uses **`FBS_FEATURE_TOKEN`** as feature header.
- [ ] User-facing routes do **not** silently fall back to `FBS_FEATURE_TOKEN` when the visitor app token is missing.

## Dev Proxy

`fusebase dev start` automatically proxies `/api` HTTP requests and WebSocket upgrades to the backend dev server.

The `BACKEND_PORT` env var is assigned by `fusebase dev start` and injected into both the SPA and backend processes, allowing multiple apps to run backends concurrently without port conflicts.

## fusebase.json Backend Config

When an app has a backend, add the `backend` block to its entry in `fusebase.json`:

```json
{
  "apps": [
    {
      "id": "app-id",
      "path": "apps/my-app",
      "dev": { "command": "npm run dev" },
      "build": { "command": "npm run build", "outputDir": "dist" },
      "backend": {
        "dev": { "command": "npm run dev" },
        "build": { "command": "npm run build" },
        "start": { "command": "npm run start" },
        "minReplicas": 1
      }
    }
  ]
}
```

Backend commands (`dev`, `build`, `start`) run from the `backend/` subdirectory of the app path.

### `backend.minReplicas` (keep the backend warm)

Optional integer `0..3`. Minimum replicas the platform keeps running. **`0` (default)** = scale to zero when idle — see [Cold Starts (Scale-to-Zero)](#cold-starts-scale-to-zero).

| `minReplicas` | Platform behavior (today) |
| ------------- | ------------------------- |
| omitted / `0` | Scale to zero; `maxReplicas` defaults to **3** when scaled up |
| `1` | One warm replica; deploy logs show `Resolved scale: minReplicas=1, maxReplicas=3` |
| `2`–`3` | N warm replicas; `maxReplicas` = `max(3, minReplicas)` |

Use **`1`** for webhook / always-on inbound integrations (see above). Prefer `1` over `3` — each warm replica runs 24/7.

### `backend.maxReplicas` — **not supported (do not use)**

**There is no `backend.maxReplicas` in the platform contract today.** If you add it to `fusebase.json`, the CLI may accept it in the file but **deploy ignores it silently** — nimbus-ai always resolves `maxReplicas` via `resolveBackendScale()` (default cap **3**, bumped only when `minReplicas > 3`).

**Never document or code against `maxReplicas=1` in fusebase.json.** A comment like “we pin single replica in fusebase.json” is false unless you also accept that the platform may run up to 3 replicas under load.

**If your backend assumes one process** (in-memory rate limiter, module-level cache, KB version stamp):

- Treat multi-replica as possible even with `minReplicas: 1` (HPA can scale to 3).
- Move counters/cache to **isolated store**, dashboard rows, or Redis sidecar — or document the multiplied limit as acceptable.
- Do **not** rely on `maxReplicas` in fusebase.json until the platform implements and validates it.

### Deploy restarts the backend (SPA must tolerate it)

Every **`fusebase deploy`** rolls the backend container. Users refreshing during rollout may see **502** from app-wrapper while the pod is not ready.

Apps with an httpOnly session cookie (`app_session`, etc.) **must** implement session bootstrap per skill **handling-authentication-errors** § session probe invariant:

- Only **401** on `/api/account/me` means logged out.
- **5xx / network** → retry (e.g. 400 ms + 1200 ms), then “Can't reach server” — **do not** clear the session cookie.

Without this, every deploy briefly “logs out” users who refresh in the rollout window.

### Logout: clear session cookies correctly

Call Gate `logoutFusebaseUser` from the **app backend** (user-context token), then clear **app-owned** cookies in the response. Gate returns which platform cookies to clear; your BFF must apply them on the app domain.

**Rules:**

1. **Backend first** — run logout on the server; do not only clear cookies client-side from localStorage flags.
2. **Overwrite, do not delete-only** — some browsers/proxies ignore `Max-Age=0` deletes on `Set-Cookie`. Prefer setting an **expired tombstone** cookie (`value=""`, `maxAge: 0`, same `name`/`path`/`domain`/`sameSite`/`secure` as the live cookie).
3. **Client logout flag** — if the SPA keeps a “signed out” flag, it must win over stale cookies until the next successful login probe.
4. **Tests** — assert **`Set-Cookie` attributes** (`Max-Age`, `Path`, `HttpOnly`), not merely that a `Set-Cookie` header exists.

```typescript
// After logoutFusebaseUser — tombstone app session
setCookie(c, 'app_session', '', {
  httpOnly: true,
  secure: true,
  sameSite: 'Lax',
  path: '/',
  maxAge: 0,
})
```

## Deriving the Public Base URL from the Request

**NEVER hardcode `localhost` in callback/redirect URLs** (e.g. OAuth redirect URIs, webhook URLs, links sent to external services). An app's backend runs behind a proxy — `localhost` only works during local dev and breaks in production.

Instead, derive the public base URL from the incoming request headers:

```typescript
/** Derive the public base URL from the incoming request. */
function getBaseUrl(req: Request): string {
  const url = new URL(req.url);
  const forwardedProto = req.headers.get("x-forwarded-proto");
  const forwardedHost =
    req.headers.get("x-forwarded-host") ?? req.headers.get("host");
  if (forwardedHost) {
    const proto = forwardedProto ?? url.protocol.replace(":", "");
    return `${proto}://${forwardedHost}`;
  }
  return url.origin;
}
```

Usage example (OAuth redirect URI):

```typescript
app.get("/auth/url", (c) => {
  const baseUrl = getBaseUrl(c.req.raw);
  const redirectUri = `${baseUrl}/api/auth/callback`;
  // Use redirectUri when building the OAuth authorization URL
});
```

This works in both environments:

- **Local dev**: resolves to `http://localhost:<port>` (via Fusebase dev server proxy forwarding host)
- **Deployed**: resolves to `https://<subdomain>.{FUSEBASE_APP_HOST}` (platform sets `x-forwarded-host` / `x-forwarded-proto`)

## Calling the Backend from the SPA

Use standard `fetch` with relative URLs. Same-origin requests automatically include the `fbsfeaturetoken` cookie, so the backend can authenticate on behalf of the user without depending on a custom header surviving the deployed platform proxy:

```typescript
// In SPA code
const res = await fetch("/api/items");
const data = await res.json();
```

If you still send `x-app-feature-token` from the SPA, treat it as a best-effort dev/proxy optimization only. Backend handlers must always support both sources:

```typescript
import { getCookie } from "hono/cookie";

const appToken =
  c.req.header("x-app-feature-token") || getCookie(c, "fbsfeaturetoken");

if (!appToken) {
  return c.json({ error: "Missing app token" }, 401);
}
```

### Magic-link session exchange (Memberspace)

Platform activation at `/_auth/magiclink/{key}` mints `fbsfeaturetoken` on the app host and redirects; **that is not enough** for durable Memberspace identity. Implement in your app backend:

1. `POST /api/account/from-magic-link` — same-origin call from the SPA **immediately** after the activation redirect; the HttpOnly `fbsfeaturetoken` cookie rides along automatically (JS cannot read it).
2. Call Gate `GET /:orgId/me/access` with `x-app-feature-token: <fbsfeaturetoken cookie>` only (see § Magic-link session exchange below — org `eversessionid` is on a different domain after NH1).
3. **Fail-closed:** accept only `source === 'member'` with a real user id.
4. Issue an app-owned httpOnly session cookie (HMAC, bound to `userId`); `GET /api/account/me` reads only that cookie.

See `fusebase-gate/references/app-magic-links.md` (§ App Session Exchange) and `fusebase-auth.md` (§ Magic-Link → App Session Exchange). Env: `FUSEBASE_ORG_ID`, `APP_SESSION_SECRET`.

### Gate security: fail closed for user-facing routes

When backend routes call Gate on behalf of the current user, keep auth in app-token context only.

- Do not silently fall back to service-account/service-token auth in user-facing routes.
- On missing/invalid app token or Gate auth rejection, return `401/403` and require re-auth/permission sync.
- Service-token usage is allowed only for explicitly system/admin routes, not as an automatic fallback path.

### Gate 403 triage: permission drift and `--sync-gate-permissions`

When Gate calls fail with **403** and messages like **`Token missing required permission: …`** or **`token subject not allowed for this operation`**, especially after a **Gate SDK bump** or platform deploy while app source did not change:

1. **Read** `fusebase.json` → `fusebaseGateMeta.usedOps` vs `permissions`. A used op without its derived permission (e.g. `listPortals` but no `portals.read`) means **remote permissions are stale**.
2. **Analyze** (read-only): `fusebase analyze gate --operations --json --feature <featureId>`.
3. **Propose or run** (with user approval if mutating remote state):

   ```bash
   fusebase app update <appId> --sync-gate-permissions
   ```

   Run this after changing Gate SDK usage or upgrading `@fusebase/fusebase-gate-sdk`, and **before** `fusebase deploy` when publishing permission changes. `deploy` does **not** sync permissions.

4. **Re-test** with a fresh session / new feature token after sync.

**Limits of sync**

- Fixes **missing permissions on the minted `gst`** when ops are `userOrToken(permission)`.
- Does **not** fix **`getMyOrgAccess`** called from the SPA — use the backend exchange (see § Magic-link session exchange).
- Does **not** replace fixing wrong call patterns (bare gst on user-context ops).

Full permission model: `apps-cli/docs/PERMISSIONS.md`. Incident skill (issues workspace): **gate-feature-token-debug** § Gate 403 authz.

### Magic-link session exchange (`/api/account/from-magic-link`)

If the app uses Fusebase Gate magic links (`requestAppMagicLink` / platform `/_auth/magiclink/{key}` — see `fusebase-gate/references/app-magic-links.md` and `fusebase-gate/references/fusebase-auth.md`), the backend exchange after activation is **mandatory for every app**, but the cookie policy splits cleanly into Test and Production.

**Cookie model after NH1 (platform email links):**

| Cookie | Domain | Available on app backend? |
| --- | --- | --- |
| `eversessionid` | org domain (`*.thefusebase.com` / org CNAME) | **No** — different registrable domain |
| `fbsfeaturetoken` | app host (`*.thefusebase-app.com` / app CNAME) | **Yes** — same-origin cookie |

Do **not** expect `eversessionid` on a same-origin `POST /api/account/from-magic-link` from the app host. That is intentional (see `apps-cli/docs/proposals/APP-AUTH-FORM-SESSION-EXCHANGES.md`).

**Mandatory exchange — platform email (`/_auth/magiclink/{key}`):**

1. Visitor opens the email link; platform activates, auth-form sets org `eversessionid`, app-wrapper mints recipient-scoped `fbsfeaturetoken` on the app host, then redirects to `redirectPath`.
2. SPA **immediately** calls `POST /api/account/from-magic-link` as a plain same-origin request — only `fbsfeaturetoken` is attached; JS cannot (and must not) read or forward tokens.
3. Backend reads `fbsfeaturetoken` from the cookie, calls `getMyOrgAccess` with `x-app-feature-token` only. The app-api proxy resolves the recipient `userId` from the JWE embedded at mint time.
4. **Fail-closed:** accept only `source === 'member'` with a real user id. Reject `source: 'none'` (visitor), `source: 'owner'` (owner-scoped / legacy), and missing/invalid responses — do not log in the wrong user.
5. Backend responds with whatever the SPA needs (typically `{ userId }`).

**Legacy SPA activation (`activateAppMagicLink` on `/link`):** the activation JSON still returns `{ featureToken, sessionToken, … }`. **`featureToken` alone is not enough** — bare `x-app-feature-token` to gate-proxy returns **`401 UNAUTHORIZED`**. Always POST both in the **body** to `/api/account/from-magic-link`, or forward the **mandatory** pair `x-app-feature-token: <featureToken>` + `EverHelper-Session-ID: <sessionToken>`. Dual-token in the request body still works here because tokens do not rely on cross-domain cookies.

Run the exchange **before** `window.location.replace` to a protected route — the next HTML load may re-mint `fbsfeaturetoken` for a different Fusebase user already signed into the browser.

#### Test vs Production cookie policy

Pick the recipe based on what the app actually needs. **Do not auto-upgrade a smoke test to the production recipe.**

**Test mode — smoke test of the magic-link flow, no Memberspace, no role-gated UI:**

- The mandatory exchange above is enough. The SPA can keep the platform `fbsfeaturetoken` cookie; re-running the exchange on the next protected page-load is acceptable for a smoke test.
- Do **not** issue an HMAC-signed app session cookie.
- Do **not** register `APP_SESSION_SECRET` (or any other HMAC secret) via `fusebase secret create`.
- Result: a Test-mode magic-link app needs **zero** `fusebase secret create` calls for the magic-link flow itself.

**Production mode — Memberspace, role-gated UI, anything that must remember which user opened the link across navigations:**

- After step 3, issue an **app-owned** session cookie (HMAC-signed or equivalent integrity-protected payload, bound to the resolved `userId`). Verify it on every protected request; do not re-infer identity from `fbsfeaturetoken` after the initial redirect.
- Register the HMAC secret here and only here: `fusebase secret create --app <appPath> --secret "APP_SESSION_SECRET:HMAC signing key for app-owned session cookie"`. Read it from `process.env.APP_SESSION_SECRET` at runtime.
- Cookie attributes: `httpOnly`, `secure`, `sameSite=Lax`, `path=/`. Rotate by changing the secret and invalidating active cookies; do not rely on Fusebase platform cookies for revocation.
- Result: a Production-mode magic-link app needs exactly **one** `fusebase secret create` call (the HMAC secret).

**Platform token lifetime (not a durable visitor session):**

- **Invite link TTL** (`ttlSeconds`, default 24h, max 7d) is only how long the email link can be **activated** — not how long the signed-in session lasts.
- After activation, `fbsfeaturetoken` on the app host is **short-lived** (typically ~24h). There is **no** supported silent renew from the app host for magic-link visitors (post-NH1 `eversessionid` is org-domain only). Do not treat `…/auth/?appSuccess=…` failures as a broken visitor renew path.
- Day-scale “stay signed in” = **app-owned HMAC session** (Production recipe above). When the platform token lapses, keep the app session and re-check entitlement from your store / service token — do not bounce to sign-in solely on expired-platform-token `getMyOrgAccess` 401.
- Anything that still needs a **live** platform feature token (browser proxy to Gate/Dashboard, some embeds) dies when that token expires — keep those behind the app backend or accept a fresh magic link.

#### What is **not** a secret — never `fusebase secret create`

`fusebase secret create` is reserved for credentials that must not appear in the repo or platform-readable config. The following are **not secrets** and must never be registered as such:

- `FUSEBASE_ORG_ID` — lives in `fusebase.json` (`orgId`) and is readable by anyone who can clone the app. Read it from `fusebase.json` (or platform-injected env where available) at app start.
- `productId` and the app subdomain — same reasoning; both live in `fusebase.json` / `fusebase app list` output.
- Fusebase host URLs (`FBS_*`) — already public configuration.

If `fusebase secret list --feature <appId>` shows any of the above, remove them (`fusebase secret delete`) and read the value from `fusebase.json` instead.

#### Magic-link backend checklist

Before claiming the magic-link flow is done, verify:

- [ ] After the platform `/_auth/magiclink/{key}` redirect, the SPA calls `/api/account/from-magic-link` (or another app-owned route) **immediately** as a same-origin request; no code reads or forwards tokens via JS.
- [ ] Platform email flow: backend calls `getMyOrgAccess` with `x-app-feature-token` from the `fbsfeaturetoken` cookie only (no `eversessionid` on app host — expected).
- [ ] Exchange **fail-closed:** `getMyOrgAccess` must return `source === 'member'` with a real user id before unlocking protected UI.
- [ ] Legacy `/link` + `activateAppMagicLink`: if using activation JSON, POST `{ featureToken, sessionToken }` in the body (dual-token still valid for this path).
- [ ] Test mode: no `APP_SESSION_SECRET`, no HMAC-signed app cookie, no `fusebase secret create` call for the magic-link flow.
- [ ] Production mode (only if Memberspace/role-gated UI is required): exactly one `fusebase secret create … APP_SESSION_SECRET:…`, HMAC-signed app-owned session cookie, verified on every protected request; durable “stay signed in” does **not** depend on `fbsfeaturetoken` lasting beyond ~24h.
- [ ] `fusebase secret list --feature <appId>` does **not** include `FUSEBASE_ORG_ID`, `productId`, app subdomain, or any other value that already lives in `fusebase.json`.

For WebSockets:

```typescript
const ws = new WebSocket(`wss://${window.location.host}/api/ws`);
ws.onmessage = (event) => {
  const msg: WsMessage = JSON.parse(event.data);
  // handle message
};
```

## Stateless Backend — No Filesystem Writes, No In-Memory Persistence

**The deployed backend is stateless.** The filesystem is ephemeral and in-memory state is lost on restart/redeployment. Do not rely on either for persistent data.

**NEVER:**

- Write to `.env`, JSON, or any local file to persist runtime state
- Use `fs.writeFileSync` / `fs.writeFile` for data that must survive restarts
- Store tokens, credentials, or user data on the local filesystem
- Use SQLite or file-based databases
- Store persistent state only in backend memory (lost on restart)

**Instead, use:**

- **httpOnly cookies** — for per-user credentials obtained at runtime (e.g. OAuth refresh tokens). The browser sends them automatically; the backend stays stateless. This is the **preferred approach** for user-specific tokens.
- **Fusebase dashboards** — for persistent runtime data shared across users (via Dashboard SDK in backend code)
- **Fusebase secrets** (env vars) — for shared credentials set at deploy time (API keys, service-account tokens). Not suitable for per-user or dynamically obtained tokens.
- **In-memory caches** — acceptable only for short-lived caches (e.g. access tokens derived from a refresh token in a cookie). Must be re-derivable from persistent source.

**Example — OAuth token flow (httpOnly cookie):**
When an OAuth callback returns a refresh token, store it in an httpOnly cookie:

```typescript
import { setCookie, getCookie } from "hono/cookie";

// In the OAuth callback handler:
setCookie(c, "oauth_refresh_token", tokens.refresh_token, {
  httpOnly: true,
  secure: true,
  sameSite: "Lax",
  path: "/",
  maxAge: 60 * 60 * 24 * 365, // 1 year
});

// In API handlers — read token from cookie, fall back to env var:
const refreshToken =
  getCookie(c, "oauth_refresh_token") ?? process.env.REFRESH_TOKEN ?? "";

// ❌ Wrong: writing to filesystem
writeFileSync(".env", `REFRESH_TOKEN=${tokens.refresh_token}`);

// ❌ Wrong: relying solely on in-memory state
config.refreshToken = tokens.refresh_token; // lost on restart
```

## Dev Workflow

1. `cd apps/my-app/backend && npm install` — install backend deps
2. `fusebase secret create --app <appPath> --secret "KEY:description"` — declare secrets in `fusebase.json` (if needed); deploy/dev start registers them and prints the UI URL where you set the values
3. `fusebase dev start` — starts both SPA and backend; secrets are injected automatically as env vars

**No `.env` files or `dotenv` needed** — `fusebase dev start` injects secrets into the backend process.

## Checklist

Before adding a backend:

- [ ] Confirmed the app **genuinely needs** backend logic (not just dashboard CRUD)
- [ ] Created `backend/` with its own `package.json` and `tsconfig.json`
- [ ] Set up Hono with `.basePath('/api')`
- [ ] Verified `fusebase dev start` proxies `/api` to backend (automatic when `backend` block exists in `fusebase.json`)
- [ ] Updated `fusebase.json` with `backend` block
- [ ] SPA does not define routes under `/api`
- [ ] Reviewed app-root `openapi.json` as the canonical app API contract
- [ ] Kept `openapi.json` in sync with every new/changed backend route
- [ ] Used only valid Fusebase OpenAPI extensions:
  - `x-fusebase-visibility`: `org | private`
  - `x-fusebase-execution-mode`: `sync | async`
- [ ] Ran `fusebase api validate`
- [ ] Checked deploy output for `Published OpenAPI registry: N operation(s) from openapi.json`
- [ ] No `.env` files or `dotenv` — secrets injected by `fusebase dev start`
- [ ] Verified backend tier + all sidecar tiers sum to ≤ 2 CPU / 4 Gi



## Scheduled Tasks (Cron Jobs)

> **⚠️ Cron jobs do NOT run with `fusebase dev start`.** Local dev mode does not schedule or execute jobs. Run `fusebase deploy` to deploy the app — jobs will be scheduled and executed in the cloud after deployment.

Cron jobs run on a schedule using the **same Docker image** as the app backend. Each job is an independent process that executes a command on a cron schedule and exits.

> **⚠️ Cron jobs cannot reach backend sidecars on `localhost`.** Cron jobs are deployed as **independent Azure Container Apps Jobs**, not as part of the backend container app, so they do not share the backend's network namespace. A cron container that calls `http://localhost:9222` (or any other backend sidecar port) will fail with `fetch failed`. If a cron needs an auxiliary container, declare a **per-job sidecar** — see [Job Sidecars](#job-sidecars) below.

### 1. Register the job in fusebase.json

```bash
fusebase job create \
  --app <appPath> \
  --name <job-name> \
  --cron "0 * * * *" \
  --command "npm run cron:my-job"
```

**Job name** must be unique within the app. Use kebab-case (e.g. `send-reports`, `cleanup-old-data`).

**Cron expression** uses standard 5-field syntax: `minute hour day-of-month month day-of-week`. All times are UTC.

### 2. Add the npm script to backend/package.json

```json
{
  "scripts": {
    // existing scripts...
    "cron:send-reports": "node dist/jobs/send-reports.js"
  }
}
```

Build config must include job entry points so they are compiled to `dist/`.

### 3. Implement the job script

```typescript
// backend/src/jobs/send-reports.ts
async function main() {
  console.log("[send-reports] Starting at", new Date().toISOString());

  // Use the same SDK / secrets as the main backend
  // Env vars injected at runtime (same as backend)

  // ... business logic ...

  console.log("[send-reports] Done");
  process.exit(0);
}

main().catch((err) => {
  console.error("[send-reports] Failed:", err);
  process.exit(1);
});
```

Key points:

- **Always call `process.exit(0)` on success** — the container job finishes only when the process exits
- **Call `process.exit(1)` on failure** — signals the job failed
- Job scripts share the same `dist/` bundle as the backend — they can import from `../` freely
- Env vars (secrets) are injected the same way as for the main backend process

### Removing a Job

```bash
fusebase job delete --app <appPath> --name <job-name>
```

This removes the job from `backend.jobs` in `fusebase.json`. On the next `fusebase deploy` the job will be automatically deleted from cloud infrastructure.

### Job Sidecars

Each cron job can declare its own sidecar containers under `apps[].backend.jobs[].sidecars`. Sidecars share the **job replica's** network namespace, not the backend's, so the main job container talks to them on `localhost:<port>` exactly the way the backend talks to its own sidecars.

Add a sidecar to a job:

```bash
fusebase sidecar add \
  --app <appPath> \
  --job <jobName> \
  --name <name> \
  --image <dockerImage> \
  [--port <port>] \
  [--tier small|medium|large] \
  [--env KEY=VALUE ...]
```

Example — a screenshot cron with its own headless browser:

```bash
fusebase sidecar add \
  --app my-scraper \
  --job screenshots \
  --name chromium \
  --image browserless/chrome:latest \
  --port 9222 \
  --tier medium \
  --env PORT=9222
```

Use `fusebase sidecar remove --job <jobName>` and `fusebase sidecar list --job <jobName>` to manage them. When `--job` is omitted, the commands target backend sidecars exactly as before.

Key constraints:

- Each job has its own **3-sidecar cap**, independent of the backend cap.
- Sidecar names are unique **per scope** — the same name (e.g. `chromium`) may exist on the backend and on a job; they are separate containers in separate replicas.
- Replica completion is determined by the **main job container's exit**. Non-exiting sidecars (headless browsers, Redis, etc.) are torn down with the replica; no custom shutdown logic is needed. `replicaTimeout=3600s` is the hard ceiling.
- `fusebase dev start` still does **not** run cron jobs nor any sidecars — job sidecars take effect only after `fusebase deploy`.

For full details (config format, networking, debugging), see the **app-sidecar** skill.

### Cron Jobs Checklist

- [ ] App already has a `backend/` folder and a `backend` block in `fusebase.json` (backend is scaffolded first)
- [ ] Added `cron:<job-name>` npm script to `backend/package.json`
- [ ] Ran `fusebase job create` to register the job
- [ ] Ran `fusebase deploy` to deploy the app — **cron jobs only run after deployment**, not during `fusebase dev start`
- [ ] If the cron needs an auxiliary container (browser, cache, etc.), attached sidecars to the **job** via `fusebase sidecar add --job <jobName>` (not the backend)
