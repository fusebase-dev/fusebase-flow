---
name: dev-debug-logs
description: "Use when debugging an app through `fusebase dev start`, or when you need to inspect browser logs, proxied API traffic, frontend dev server output, or backend output captured by the local CLI. Explains where logs are written and which file to inspect for each symptom. This is for LOCAL DEVELOPMENT only - for deployed apps, use the remote-logs skill instead."
---

# Dev Debug Logs

> **Important**: This skill is for **local development** only. For logs from deployed app backends, use the **remote-logs** skill with `fusebase remote-logs` command.

When an app is run through:

```bash
fusebase dev start FEATURE_PATH
```

the CLI creates a per-session log directory inside the selected app directory:

```text
<app-dir>/logs/dev-<timestamp>/
```

with these files:

- `browser-logs.jsonl`
- `access-logs.jsonl`
- `backend-logs.jsonl`
- `frontend-dev-server-logs.jsonl`

Use this skill when debugging the local app runtime. These logs are local development artifacts only.

## Which Log File To Read

### `browser-logs.jsonl`

Use for:

- `console.log` / `console.error` output from the browser
- uncaught browser errors
- unhandled promise rejections
- navigation/lifecycle events from the app page

Important:

- It only works when the app is opened through the CLI proxy started by `fusebase dev start`
- The CLI injects a browser debug script into proxied HTML pages automatically
- Records are JSON Lines; each line is one event

Typical fields:

- `timestamp`
- `type`
- `level`
- `message`
- `args`
- `error`
- `url`
- `pathname`

### `backend-logs.jsonl`

Use for:

- backend stdout/stderr captured during `fusebase dev start`
- runtime errors printed by an app backend
- startup messages like port binding, env/config issues, and stack traces

Typical fields:

- `timestamp`
- `appId`
- `line`

Important:

- If the app defines a dedicated backend dev command, the CLI captures that process directly
- If frontend and backend are started together from one `dev.command` using tools like `concurrently`, the CLI attempts to capture the backend lane into this file as well
- This file is line-based output, not structured request logs

### `access-logs.jsonl`

Use for:

- requests made to `/api` through the local proxy
- request/response headers
- request/response bodies for small JSON/text payloads
- proxy failures between the CLI and the app/frontend dev server

Typical record types:

- `request`
- `response`
- `proxy-error`

Important:

- Records include `requestId`
- The same request ID is also forwarded as `x-fusebase-dev-request-id`
- Use `requestId` to correlate request and response records for one `/api` call
- Headers and obvious secrets are redacted before writing

### `frontend-dev-server-logs.jsonl`

Use for:

- frontend dev server stdout/stderr captured during `fusebase dev start`
- Vite startup errors, port-binding issues, and plugin/build diagnostics printed by the frontend dev server
- frontend-side dev proxy messages emitted by the app dev server

Typical fields:

- `timestamp`
- `appId`
- `line`

Important:

- If the app uses a dedicated backend via `app.backend.dev.command`, this file contains the app dev server output directly
- If frontend and backend are started together from one `dev.command` using tools like `concurrently`, the CLI attempts to exclude the detected backend lane from this file
- This file is line-based output, not structured browser events

## How To Use These Logs Together

For frontend/UI issues:

- Start with `browser-logs.jsonl`
- If the browser error looks related to Vite, module resolution, HMR, or frontend dev proxying, check `frontend-dev-server-logs.jsonl`
- If the browser error came from a failed `/api` call, inspect `access-logs.jsonl` and then check `backend-logs.jsonl` around the same time if a backend exists

For `/api` failures seen in the UI:

- Start with `browser-logs.jsonl` to confirm the browser-visible symptom
- Check `access-logs.jsonl` to correlate the request and response or a proxy error
- Check `frontend-dev-server-logs.jsonl` if the frontend dev server may be failing to proxy or compile
- Then inspect `backend-logs.jsonl` for the corresponding backend-side error or startup issue

For backend startup failures:

- Start with `backend-logs.jsonl`
- Check whether the backend printed startup errors, missing env vars, port conflicts, or stack traces
- If the browser is only showing a generic fetch failure, confirm the browser-visible symptom in `browser-logs.jsonl`

## Quick runbook: CORS vs NotFound for Gate/PostgreSQL flows

When a PostgreSQL-backed feature fails early, use this order before changing code:

1. **Preflight / OPTIONS**
   - confirm whether the browser is failing on CORS/preflight before the real request
   - check `browser-logs.jsonl` and `access-logs.jsonl`
2. **Gate `/me` token context**
   - call `GET /v4/api/proxy/gate-service/v1/me` with the current `x-app-feature-token`
   - verify identity, scopes, and effective permissions
3. **Store discovery**
   - call `listIsolatedStores` for the current `orgId`
   - if the store is app-scoped, verify the exact `clientId` / source scope match
4. **Only then change app code**

Heuristic:

- preflight/CORS failure -> host/origin/config issue
- valid `/me` + empty store list -> org/source-scope/config issue
- valid `/me` + visible store + failing data call -> then inspect feature code / SDK args

## Rules

- Use `fusebase dev start`; do not bypass the CLI with direct `npm run dev` if you need these logs
- Read the latest session directory under the selected app directory's `logs/dev-<timestamp>/` for the current run
- **Vite watch**: Add `server.watch.ignored: ['**/logs/**']` to the app's `vite.config.ts` so log writes don't trigger HMR reloads (see skill **app-dev-practices**)
- Treat logs as debug artifacts, not as a source of truth for business data
- Do not assume secrets are fully removed; redaction is best-effort
