---
name: api-exploration
description: "Workflow for testing Fusebase API calls interactively using temporary tokens. Use when: 1. You need to verify an API endpoint behavior before writing app code, 2. You want to explore available API responses or schemas, 3. You're unsure how an API endpoint works and need to test it, 4. Debugging API integration issues by making direct calls."
---

# API Exploration with Temporary Tokens

When you're unsure about an API endpoint's behavior, response shape, or want to test a flow before committing to implementation — create a temporary token and run test calls directly.

## Workflow

### 1. Create a temporary token

```bash
fusebase token create --feature <featureId>
```

This outputs a short-lived token (15 min) to stdout. Capture it:

```bash
TOKEN=$(fusebase token create --feature <featureId>)
```

The `appId` comes from `fusebase.json` → `apps[].id`.

### 2. Write and run test code

Create a temporary script (e.g. `_test-api.ts`) to make the API calls you want to verify:

```typescript
const token = process.env.TOKEN || "<paste-token-here>";

const res = await fetch("https://api-endpoint/...", {
  headers: { "x-app-feature-token": token },
});
console.log(res.status);
console.log(await res.json());
```

Run it:

```bash
TOKEN=$(fusebase token create --feature <featureId>) bun _test-api.ts
```

### 3. Inspect results and iterate

Read the output, adjust your calls, and re-run. Once you understand the API behavior, implement it properly in your app code.

### 4. Clean up

Delete the temporary test script when done — don't commit it.

## Example: Testing `@fusebase/dashboard-service-sdk`

Use this to verify SDK calls before wiring them into app UI code.

`_test-sdk.ts`:

```typescript
import {
  createClient,
  DatabasesApi,
  CustomDashboardRowsApi,
} from "@fusebase/dashboard-service-sdk";

const token = process.env.TOKEN!;
const BASE_URL =
  "https://app-api.{FUSEBASE_HOST}/v4/api/proxy/dashboard-service/v1";

const client = createClient({
  baseUrl: BASE_URL,
  defaultHeaders: { "x-app-feature-token": token },
});

const dbApi = new DatabasesApi(client);
const rowsApi = new CustomDashboardRowsApi(client);

// List databases visible to this app
const dbs = await dbApi.listDatabases({});
console.log("databases:", JSON.stringify(dbs, null, 2));

// Read rows from a specific dashboard view
const rows = await rowsApi.getRows({
  dashboardId: "<dashboardId>",
  viewId: "<viewId>",
});
console.log("rows:", JSON.stringify(rows, null, 2));
```

Run it:

```bash
TOKEN=$(fusebase token create --feature <featureId>) bun _test-sdk.ts
```

Replace `BASE_URL` host with the value matching your environment's `FUSEBASE_HOST` (e.g. `app-api.thefusebase.com` for prod).

## Key Points

- Token expires in **15 minutes**. Create a new one if it expires.
- Use this for **any** Fusebase API call you want to validate — dashboard data, app endpoints, etc.
- The API spec is available at the public OpenAPI endpoint if you need to discover available routes.
- Prefix test files with `_` (e.g. `_test-sdk.ts`) so they're easy to spot and clean up.
