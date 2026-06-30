---
version: "1.8.0"
mcp_prompt: sdk
last_synced: "2026-04-17"
title: "SDK Discovery"
category: meta
---
# SDK Discovery

> **MARKER**: `mcp-sdk-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `sdk` for latest content.

---
## Table of contents

- [Key principle: SDK is for runtime only](#key-principle-sdk-is-for-runtime-only)
- [SDK Discovery (during development)](#sdk-discovery-during-development)
  - [Discovery rules](#discovery-rules)
  - [How to know which SDK method to use](#how-to-know-which-sdk-method-to-use)
- [Dashboard clients (do not confuse)](#dashboard-clients-do-not-confuse)
- [Schema and execution rules](#schema-and-execution-rules)
- [SDK response format](#sdk-response-format)
- [SDK initialization (runtime code)](#sdk-initialization-runtime-code)
- [Package](#package)
- [Opening a database in the Thefusebase UI](#opening-a-database-in-the-thefusebase-ui)
- [Summary](#summary)

---
## Key principle: SDK is for runtime only

- **SDK** = used **only** in feature code when the feature is running (browser/UI, dev or prod).
- **LLM does NOT execute SDK** — the LLM discovers operations via MCP, then uses `sdk_search` / `sdk_describe` to get method signatures and **inserts** SDK code into feature files. The feature runs that code at runtime with the feature token.
- **Feature code does NOT know about MCP** — it only uses SDK methods with the feature token.

**MCP** is for development and dashboard access from the LLM (discovery, tool_call). **SDK** is only for runtime code.

---

## SDK Discovery (during development)

The SDK is a generated TypeScript client that mirrors API operations. Do **not** guess method names or parameters.

### Discovery rules

- Use `sdk_search` to find SDK methods by keywords (e.g. `sdk_search({ query: "getDashboardView" })` returns the correct client and method).
- Use `sdk_list` to browse all SDK clients and methods.
- Use `sdk_describe` to inspect schemas and HTTP behavior.

### How to know which SDK method to use

1. Use **MCP** to discover the operation: `tools_search` → `tools_describe` → `tool_call` for discovery/execution.
2. Use **MCP SDK discovery tools** to get the code signature for the same operation:
   - `sdk_search({ query: "<opId or keyword>" })` — find the SDK method (same `operationId` as the MCP tool).
   - `sdk_describe({ method: "<operationId>" })` — get API class, method name, parameters, response shape, HTTP details.
3. Insert the generated SDK call into the feature file. The LLM does **not** execute it; the feature runs it at runtime with the feature token.

Every MCP tool has a corresponding SDK method with the same `operationId` and the same input/output schema.

---

## Dashboard clients (do not confuse)

Dashboard-related methods are split across **two** clients:
- **DashboardsApi**: getDashboardView, getDashboard, describeDashboard, createDashboardIntent, createViewIntent, getChildTableLinkDashboard, updateViewIntent, etc. (metadata, views, schema). For creating dashboards/views in MCP use createDashboardIntent and createViewIntent; for schema/column updates use updateViewIntent; changes sync to the dashboard.
- **DashboardDataApi**: getDashboardViewData, batchPutDashboardData, etc. (rows and cell data).
- **DashboardRelationsApi**: addRelationRows, updateRelationRows — use these to link rows; do not write lookup/relation columns via batchPutDashboardData (causes 400).
There is also **CustomDashboardRowsApi** for listDashboardRows, deleteDashboardRow, etc. For creating rows use **batchPutDashboardData** with `create_new_row: true` (createDashboardRow is deprecated).
**Rule**: Do not assume a method lives on a client by name alone. Use `sdk_search("methodName")` to get the correct client; e.g. getDashboardView is on **DashboardsApi**, not DashboardDataApi.

---

## Schema and execution rules

- **Schema**: SDK method input schemas are identical to MCP tool input schemas. If you know how to call an MCP tool, you know how to call the SDK method.
- **Execution**: SDK calls are normal TypeScript method calls, not MCP tool calls. Use the usage hints from `sdk_describe` to generate code.

---

## SDK response format

The SDK returns the **HTTP response body directly** (no extra wrapper). There is no Axios-style envelope: the method return value **is** the body.

- For **getDashboardView**: the return value is `{ data: DashboardView }`. The view (schema, name, etc.) is in **response.data**, not on the top level. Use `const view = (response as { data?: DashboardView }).data` or destructure `const { data: view } = response` — otherwise response.schema is undefined and empty tables throw.
- For **getDashboardViewData** (and getRelatedDashboardData): the return value is `{ data: row[], meta?: { page, limit, total, ... } }`.
  - **response.data** = array of rows (objects with `root_index_value` and column keys).
  - **response.meta** = pagination info (if present).
- **Important runtime rule**: For `getDashboardViewData`, treat runtime JSON as source of truth. Cells are returned as raw values on the row object (`row[item_key]`), not guaranteed `{ value }` wrappers.
- **Type mismatch guard**: Some generated SDK types may still suggest `DashboardValueExtended`-style wrapped cells. Do not assume `.value` exists; read cells defensively as `unknown` and narrow by runtime type.
- Do **not** double-unwrap: use **response.data** for the rows, not response.data.data. Writing response.data.data is wrong and yields undefined.
- **Schema item fields**: API and SDK types use **snake_case** for schema items (e.g. `source.custom_type`, `_type_custom`). Do not use camelCase (e.g. customType) when reading getDashboardView/describeDashboard response.

Example in feature code:
```typescript
const response = await dataApi.getDashboardViewData({ path: { dashboardId, viewId } });
const rows = response.data ?? [];  // rows = Array<{ root_index_value, [item_key]: value }>
// Or: const { data: rows, meta } = response;
```

---

## SDK initialization (runtime code)

## Package

npm: `@fusebase/dashboard-service-sdk`. For development, install from public npm:
`npm install @fusebase/dashboard-service-sdk` (or the equivalent in your package manager).

**Browser/UI runtime** (using feature token):

```typescript
import { createClient, CustomDashboardRowsApi, DashboardDataApi, DatabasesApi } from "@fusebase/dashboard-service-sdk";

const BASE_URL = 'https://app-api.{FUSEBASE_HOST}/v4/api/proxy/dashboard-service/v1'

export function createSdkClient(featureToken: string) {
  return createClient({
    baseUrl: BASE_URL,
    defaultHeaders: {
      'x-app-feature-token': featureToken,
    },
  })
}

export function createDatabasesApi(featureToken: string): DatabasesApi {
  const client = createSdkClient(featureToken)
  return new DatabasesApi(client)
}

export function createRowsApi(featureToken: string): CustomDashboardRowsApi {
  const client = createSdkClient(featureToken)
  return new CustomDashboardRowsApi(client)
}

export function createDataApi(featureToken: string): DashboardDataApi {
  const client = createSdkClient(featureToken)
  return new DashboardDataApi(client)
}

// Usage: get feature token from postMessage or cookie, then create API and call methods.
```

---

## Opening a database in the Thefusebase UI

To open a database in the Thefusebase UI in the browser, use this URL pattern:

`https://{{orgDomain}}/dashboard/{{orgId}}/tables/databases/{{databaseId}}`

- **orgDomain**: The organization’s **CNAME** when a custom domain is configured; otherwise **`{orgSubdomain}.{FUSEBASE_WEB_CLIENT_HOST}`** (org subdomain on the Fusebase tenant host; pay attention that `{FUSEBASE_WEB_CLIENT_HOST}` may be different from `{FUSEBASE_HOST}`, used in `https://app.{FUSEBASE_HOST}/...` and `https://app-api.{FUSEBASE_HOST}/...` in these prompts). Ensure you know the exact value of `FUSEBASE_WEB_CLIENT_HOST`.
- **orgId** and **databaseId**: UUIDs (`global_id`) for the organization and database (same as in MCP tools and SDK).

---

## Summary

- **SDK = feature runtime only**: used in browser/UI code when the feature is running; never executed by the LLM.
- **MCP = LLM development**: discovery and execution during development.
- **Discovery**: MCP first (tools_search, tools_describe, tool_call), then sdk_search / sdk_describe to generate SDK code for the feature.
- **Token**: SDK uses the feature token (`x-app-feature-token`); MCP uses the connection token from the environment.
---

## Version

- **Version**: 1.8.0
- **Category**: meta
- **Last synced**: 2026-04-17
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
