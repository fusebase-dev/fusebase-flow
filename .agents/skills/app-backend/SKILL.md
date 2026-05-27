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
fusebase sidecar add --app <appId> --name chromium --image browserless/chrome:latest --port 9222
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
fusebase sidecar add --app <appId> --name redis --image redis:7 --port 6379 --env REDIS_MAXMEMORY=256mb
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

## Webhooks and External WebSocket Callbacks (Inbound)

Inbound integrations from external services (for example, Monday.com, GitHub, Stripe) can use regular HTTP webhooks and, when needed, WebSocket upgrades (for example, Twilio media streams). These requests typically do not carry a `fbsfeaturetoken` cookie or `x-app-feature-token` header.

The platform proxy skips app-token auth for any path under `/api/webhooks/`, including both HTTP routes and WebSocket upgrade routes.

### Secret path segment

Try to come up with random and hard to guess path for webhooks, for example:

`/api/webhooks/stripe` - bad
`/api/webhooks/stripe-gja8dj21349asgj12n4asodgasdg` - good

### Webhook route

Public webhook URL: `https://{FEATURE_DOMAIN}/api/webhooks/...`

For external WebSocket integrations, use a path under `/api/webhooks/...` as well (example: `/api/webhooks/twilio-stream-<random-secret>`).

### Service-account token for webhooks

Webhook handlers run without a user session. To call Fusebase services from a webhook handler, use `process.env.FBS_FEATURE_TOKEN` — a platform-issued service-account token.

**Security rule**: use `FBS_FEATURE_TOKEN` only in system/background routes (webhooks, scheduled jobs). User-facing routes must fail closed (`401/403`) on a missing/invalid app token — do not fall back to the service-account token.

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
        "start": { "command": "npm run start" }
      }
    }
  ]
}
```

Backend commands (`dev`, `build`, `start`) run from the `backend/` subdirectory of the app path.

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

### Magic-link session exchange (Memberspace / `/link`)

The bundled SPA `/link` route only activates the link and sets platform cookies; **that is not enough** for knowing which user opened the link. Implement in your app backend:

1. `POST /api/account/from-magic-link` — body `{ featureToken, sessionToken, redirectPath? }` from `activateAppMagicLink` **before** redirect.
2. Call Gate `GET /:orgId/me/access` with `x-app-feature-token` + **`EverHelper-Session-ID: <sessionToken>`** (not platform cookies alone).
3. Issue an app-owned httpOnly session cookie (HMAC, bound to `userId`); `GET /api/account/me` reads only that cookie.

See `fusebase-gate/references/app-magic-links.md` (§ App Session Exchange) and `fusebase-auth.md` (§ Magic-Link → App Session Exchange). Env: `FUSEBASE_ORG_ID`, `APP_SESSION_SECRET`.

### Gate security: fail closed for user-facing routes

When backend routes call Gate on behalf of the current user, keep auth in app-token context only.

- Do not silently fall back to service-account/service-token auth in user-facing routes.
- On missing/invalid app token or Gate auth rejection, return `401/403` and require re-auth/permission sync.
- Service-token usage is allowed only for explicitly system/admin routes, not as an automatic fallback path.

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
2. `fusebase secret create --app <id> --secret "KEY:description"` — register secrets (if needed), set values via the printed URL
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

> **⚠️ Cron jobs cannot reach backend sidecars on `localhost`.** Cron jobs are deployed as **independent Azure Container Apps Jobs**, not as part of the backend container app, so they do not share the backend's network namespace. A cron container that calls `http://localhost:9222` (or any other backend sidecar port) will fail with `fetch failed`.<% if (it.flags?.includes("job-sidecars")) { %> If a cron needs an auxiliary container, declare a **per-job sidecar** — see [Job Sidecars](#job-sidecars) below.<% } else { %> If a cron needs an auxiliary container, call back to the main backend over its public URL (`/api/...`), where the backend can use its own sidecars.<% } %>

### 1. Register the job in fusebase.json

```bash
fusebase job create \
  --app <appId> \
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
fusebase job delete --app <appId> --name <job-name>
```

This removes the job from `backend.jobs` in `fusebase.json`. On the next `fusebase deploy` the job will be automatically deleted from cloud infrastructure.

<% if (it.flags?.includes("job-sidecars")) { %>
### Job Sidecars

Each cron job can declare its own sidecar containers under `apps[].backend.jobs[].sidecars`. Sidecars share the **job replica's** network namespace, not the backend's, so the main job container talks to them on `localhost:<port>` exactly the way the backend talks to its own sidecars.

Add a sidecar to a job:

```bash
fusebase sidecar add \
  --app <appId> \
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

<% } %>### Cron Jobs Checklist

- [ ] App already has a `backend/` folder and a `backend` block in `fusebase.json` (backend is scaffolded first)
- [ ] Added `cron:<job-name>` npm script to `backend/package.json`
- [ ] Ran `fusebase job create` to register the job
- [ ] Ran `fusebase deploy` to deploy the app — **cron jobs only run after deployment**, not during `fusebase dev start`
<% if (it.flags?.includes("job-sidecars")) { %>- [ ] If the cron needs an auxiliary container (browser, cache, etc.), attached sidecars to the **job** via `fusebase sidecar add --job <jobName>` (not the backend)
<% } %>
