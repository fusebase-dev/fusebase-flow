---
name: app-dev-practices
description: "Practical guide for building Fusebase Apps apps. Use when: (1) Creating a new app, (2) Setting up project structure, Vite config, or authentication, (3) Building or registering apps, (4) Configuring permissions or public access, (5) Navigating between apps, (6) Fetching user details, (7) Troubleshooting build issues."
---

# App Dev Practices

## Always Scaffold First

Run `fusebase scaffold --template spa --dir apps/<name>` before writing any app files. This generates the canonical React + Vite + Tailwind v4 + shadcn/ui project structure. For apps needing a backend, also run `fusebase scaffold --template backend --dir apps/<name>`. Customize from there — never recreate boilerplate by hand.

## Multi-User by Default

**Every app is multi-user.** Multiple users access the same deployed app simultaneously, each with their own identity (app token). Never design for a single user.

**Rules:**
- **Per-user state** (OAuth tokens, preferences, selections) must be stored **per-user** — use httpOnly cookies (set by the server, scoped to the user's browser) or dashboard rows keyed by user ID
- **Shared env vars / Fusebase secrets** are global — they are the **same for all users**. Never use them for per-user credentials or settings
- **In-memory backend variables** are shared across all requests from all users — never store per-user data in module-level variables
- When integrating third-party APIs with OAuth, each user must go through their own auth flow and get their own tokens

- **Stable partition keys only:** when storing per-user rows, the partition key must come from a **stable identity** (`userId`, `orgUserId`, email if immutable), not from session/token artifacts.
- **Never use token-derived keys** (e.g. `ft:*`, JWT fragments, rotating session IDs) as persistent `user_key`/partition keys — they change between sessions and split one user's data into multiple buckets.
- **Recommended format:** normalize once in backend (`user:<userId>`) and reuse the same key for both read and write paths.

**Ask yourself:** "If two users open this app at the same time, will they interfere with each other?" If yes, the design is wrong.


## Project Structure

Apps are React/Vite apps in `apps/`:

```
apps/
  my-app/
    package.json
    vite.config.ts
    src/
      App.tsx
      main.tsx
```

Use existing apps in `apps/` as reference when building new ones.

### Vite Config: Ignore Logs Directory

`fusebase dev start` writes debug logs to `<app-dir>/logs/`. Tell Vite's file watcher to ignore this directory so it doesn't trigger unnecessary reloads:

```ts
// vite.config.ts
export default defineConfig({
  server: {
    watch: {
      ignored: ['**/logs/**'],
    },
  },
  // ...rest of config
});
```

**Always include this in every app's `vite.config.ts`.**

### Vite Config: Do NOT add inline `css.postcss`

Do **NOT** add a `css.postcss` block in `vite.config.ts`. An inline `css` config — even with an empty `plugins` array — **overrides** the external `postcss.config.js` entirely, silently disabling Tailwind and all other PostCSS plugins.

```ts
// ❌ BROKEN — overrides postcss.config.js, Tailwind never runs
export default defineConfig({
  css: {
    postcss: {
      plugins: [],
    },
  },
});
```

```ts
// ✅ CORRECT — no css.postcss block; Vite picks up postcss.config.js automatically
export default defineConfig({
  plugins: [react()],
  // ...rest of config
});
```

PostCSS plugins (`@tailwindcss/postcss`, `autoprefixer`) belong in `postcss.config.js` only.

### Backend (Optional)

Apps may optionally include a `backend/` subfolder for a backend API (REST + WebSockets). **Do not add a backend unless the app genuinely needs backend logic** — most apps work fine with the Dashboard SDK alone. See skill **app-backend** for when and how to add one. The backend is served at `/api`.

<!-- CUSTOM:SKILL:BEGIN -->
## Consuming Another Fusebase App's API

If your app needs to integrate with **another Fusebase app in the same organization**, do **not** treat that app as an external opaque service by default.

Use this workflow:

1. Discover the target app's published API through Gate:
   - `searchAppApiOperations`
   - `listAppApiOperations`
   - `getAppApiOperation`
2. Inventory the relevant operations and their request or response shapes.
3. Build the integration against that published contract.
4. Use `callAppApi` or direct runtime probing only if behavior still needs live verification.

Avoid these dead ends as a first move:

- searching for the target app's source code in the current repo
- asking for raw OpenAPI export or manual endpoint lists
- spelunking dashboard tables or storage schemas instead of using the published app API

If a published app API exists, it is the primary cross-app integration surface.

For security-sensitive operations, prefer contract-level app API policy:

- `x-fusebase-allowed-callers` restricts the caller identity: a caller id is the calling project's `productId`, e.g. `client:<productId>`, not an app id — sibling apps of one project share it.
- `x-fusebase-required-permissions` restricts caller capability and must use the app API namespace `app_api.<namespace>.<capability>.<action>`, e.g. `app_api.client_portal.provision.write`.
- Do not use built-in Gate permissions such as `isolated_store.read` for app-to-app operation authorization.
- **Enforcement arrives per environment.** Both extensions are published to the registry and read by `callAppApi`, but enforcement is switched on per environment by the platform. Declare them now and grant the matching capability to caller apps with `fusebase app update <callerAppId> --permissions "app_api.<namespace>.<capability>.<action>"`, so the grants are in place when enforcement reaches yours. Never rely on them as your only authorization check today.
<!-- CUSTOM:SKILL:END -->

## Authentication

<% if (it.flags?.includes("portal-specific-apps")) { %>
Apps run as the main window. The platform provides an app token via `window.FBS_FEATURE_TOKEN` (with `fbsfeaturetoken` cookie fallback when needed).
<% } else { %>
Apps run as the main window. The platform sets a `fbsfeaturetoken` cookie automatically.
<% } %>

**Startup flow:**

<% if (it.flags?.includes("portal-specific-apps")) { %>
1. Read app token on app load from `window.FBS_FEATURE_TOKEN` first; if missing, fall back to `fbsfeaturetoken` cookie
<% } else { %>
1. Read app token on app load: check `fbsfeaturetoken` cookie first, fall back to `window.FBS_FEATURE_TOKEN` if the cookie is absent
<% } %>
2. Render app once token is available (show loading state until then)
3. Pass token via `x-app-feature-token` for direct SDK / Fusebase proxy calls
4. For calls to the app's own backend (`/api/*`), rely on the same-origin cookie and make backend handlers read `x-app-feature-token` or fallback to `fbsfeaturetoken`

**All apps MUST handle token expiration** (`AppTokenValidationError` / 401). See skill **handling-authentication-errors** for the implementation pattern.

### Backend session apps (httpOnly cookie)

If the app has a **backend** and the SPA boots auth from **`GET /api/account/me`** (or similar) with `credentials: 'include'`:

- Load **handling-authentication-errors** § **session probe invariant** before writing auth bootstrap code.
- **401 only** → login screen. **502/5xx/network** → retry with deploy tolerance, then transient error — **never** `setState('anon')` on proxy errors.
- **`fusebase deploy` restarts the backend** — session probe must survive the rollout window (see skill for retry delays).

Do not conflate this with platform `fbsfeaturetoken` expiry (`AppTokenValidationError` modal) — they are separate layers.

## User Details

<% if (it.flags?.includes("portal-specific-apps")) { %>
Fetch auth context:

```typescript
type AuthContextResponse = {
  user?: {
    id: number
    email: string
  }
  org?: {
    globalId: string
  }
  // Portal context. Optional in the type because it is absent outside a portal;
  // see "Portal context contract" below for exactly when it is present.
  // `portalId` and `workspaceId` are always set together, or both absent.
  runtimeContext?: {
    portalId?: string
    workspaceId?: string
  }
}

const response = await fetch('https://app-api.{FUSEBASE_HOST}/v4/api/auth/context', {
  headers: { 'x-app-feature-token': appToken },
})
const authContext: AuthContextResponse = response.ok ? await response.json() : {}
const user = authContext.user ?? null
// authenticated: { id: 4124, email: "testemail@gmail.com" }
// anonymous visitor on a public app: null (user field is missing)

const insidePortal = Boolean(authContext.runtimeContext?.portalId)
```

### Portal context contract

`portalId` and `workspaceId` are always set together, or both absent. Where they come from: the
portal app block stores a portal context token, the portal appends it to the app's iframe URL, and
the platform stamps its `portalId` / `workspaceId` into the `x-app-feature-token` minted when the
app opens. The token is stored **on the block**, not derived from the viewer's session.

**Present** — app opened from a portal embed whose block carries a portal context token. Because
the token is a property of the block, this does not depend on who is looking: it is present for
**every portal role (client, manager, anonymous visitor) and every portal access mode**. Role and
access mode never cause it to go missing.

**Absent** — the exhaustive list:

1. The app is opened directly by its own URL, outside any portal.
2. Local `fusebase dev start` — there is no portal embed locally, same as case 1.
3. **Legacy portal blocks.** App blocks added to a portal before the platform started storing the
   portal context token (April 2026) carry no token, so the fields are absent even though the app
   *is* embedded in a portal — for every viewer. Fixable per block, see below.

**Possibly stale** — if the block was **copied from another portal**, the stored token still carries
the **source** portal's id, so `portalId` can name a different portal than the one the app is
currently displayed in. All of these copy the block verbatim, and nothing re-mints the token:

- block copy-paste,
- duplicating a page or folder from another portal ("Create from another portal"),
- duplicating a whole portal, or creating a portal from a template — **every** app block in the new
  portal carries the source/template portal's id,
- synced-copy propagation into a page that lives in another portal.

**Fixing a block** (cases 3 and stale) — in the portal customizer, the block's app selection has to
actually **change** for a token to be minted: pick a different app in that block, then the intended
one again. Re-picking the *same* app is a no-op — the App picker ignores an unchanged value and no
token is minted. If the product has only one app, delete the app block and add it again.

**What this means in practice.** `Boolean(runtimeContext?.portalId)` is a good instant UX signal and
is correct for every portal embed created normally today. Absence almost always means "not in a
portal" — but because of case 3, do not make it an unrecoverable dead end: prefer degrading to the
standalone UI, or offer a way forward, rather than a hard "open me from a portal" wall that leaves a
user on a legacy embed stuck.

**This is a UX hint, not an authorization fact.** Use it to choose what to render. Anything that
grants access to portal data must still be authorized server-side by verifying the
`portalFeatureContextToken` — which is also what protects you from the stale-token case above. Do
not derive permissions from `runtimeContext`.

Important for public apps:

- A visitor app token may be valid even when `/auth/context` returns no `user`
- Missing `user` means "not authenticated", not "session expired"
- `/auth/context` should not throw just because the visitor is anonymous
<% } else { %>
Fetch current user:

```typescript
const response = await fetch('https://app-api.{FUSEBASE_HOST}/v4/api/users/me', {
  headers: { 'x-app-feature-token': appToken },
})
const user = response.ok ? await response.json() : null
// authenticated: { id: 4124, email: "testemail@gmail.com" }
// anonymous visitor on a public app: null
```

Important for public apps:

- A visitor app token may be valid even when `/users/me` returns 401
- In that case, treat the result as `user: null`, not as "session expired"
<% } %>
- Show the login/auth form for anonymous visitors
- Only show a "Session Expired" modal for actual `AppTokenValidationError` flows

See skill **handling-authentication-errors** for the exact 401 handling rules.

## Navigation

Use standard browser navigation (React Router, etc.) since apps run as the main window. For routing setup, see skill **app-routing**.

## UI Framework

Use **shadcn/ui**. For design and UX guidance (layout, tokens, components, accessibility), see skill **app-ui-design**.

## Building Apps

```bash
cd apps/my-app
npm run build
```

### devDependencies Missing

If `npm run build` fails because vite/typescript are not found, npm may be running in production mode (`NODE_ENV=production` — common in VS Code / Claude Code). Fix:

```bash
npm install --include=dev
```

### Typecheck at project root

From the repo root, `npm run typecheck` runs `tsc` for each app (see root `package.json`). It catches strict TypeScript issues that ESLint does not, including the same failures as `tsc` inside `fusebase deploy`’s build. Claude Code Stop hooks run it after lint.

## Registering Apps

After creating an app, register it via `fusebase app create` from the project root:

```bash
fusebase app create --name <name> --subdomain <subdomain> --path <path> --dev-command <command> --build-command <command> --output-dir <dir>
```


**Execute this command automatically** after writing the app code — do not ask the user to run it manually.

### Access Principals

Use `--access` to control who can access the app. Principals are comma-separated:

```bash
# Public (visitor) access
fusebase app create --name <name> --access=visitor
fusebase app update <appId> --access=visitor

# Org role access (guest, client, member, manager, owner)
fusebase app update <appId> --access=orgRole:member
fusebase app update <appId> --access=orgRole:member,orgRole:client

# Combine visitor and org roles
fusebase app update <appId> --access=visitor,orgRole:member
```

### Permissions

Use `--permissions` with `fusebase app create` when the app is first registered. Only use `fusebase app update --permissions` when changing permissions on an already-registered app. Use MCP to discover dashboard/view IDs. See skill **fusebase-cli** for permission format and examples.

## Getting App URLs

```bash
fusebase app list
```

Lists all apps with their deployed URLs. Use this to get actual URLs — do NOT hardcode or guess them.

**Always use the full subdomain URL** (read `FUSEBASE_APP_HOST` from `.env`, e.g. `https://my-app.{FUSEBASE_APP_HOST}/`), never relative paths. Each app is served from its own subdomain root — see skill **app-routing**.

## Cross-App Navigation

Use standard browser navigation (`<a>`, `window.location`) with full app URLs obtained from `fusebase app list`.
