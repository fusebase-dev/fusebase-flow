---
version: "1.12.0"
mcp_prompt: domain.data
last_synced: "2026-04-28"
title: "Dashboard Data"
category: core
---
# Dashboard Data

> **MARKER**: `dashboards-data-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.data` for latest content.

---
## Table of contents

- [Dashboard Data Operations](#dashboard-data-operations)
  - [Core Concepts](#core-concepts)
  - [Resolving column keys (item_key) — REQUIRED before read/write](#resolving-column-keys-itemkey--required-before-readwrite)
  - [Reading Dashboard Data](#reading-dashboard-data)
  - [Writing Dashboard Data](#writing-dashboard-data)
  - [Related Data Operations](#related-data-operations)
  - [Data Value Structure (getDashboardViewData response)](#data-value-structure-getdashboardviewdata-response)
  - [Custom column types: read and write by type](#custom-column-types-read-and-write-by-type)
  - [Link columns (type: link)](#link-columns-type-link)
  - [File columns (type: files)](#file-columns-type-files)
  - [Constraints and Validation](#constraints-and-validation)
  - [Common Patterns](#common-patterns)

---
## Dashboard Data Operations

Dashboard data consists of rows and values. Each row represents an entity (identified by `root_index_value`), and each value is stored in a cell (identified by `item_key` from the dashboard schema).

### Core Concepts

- **Row**: A single entity in the dashboard, identified by `root_index_value` (e.g., a portal ID, workspace ID, client ID, or custom row UUID for tables with rootEntity='custom')
- **Item Key**: Column identifier from `schema.items[].key`. Keys are **opaque IDs** (e.g. `B9pYbJFk`, `Qt1l4UDS`) — **NEVER** use display names like "Meeting Name" or "Date/Time" as item_key; they are invalid and cause 400 or wrong columns. Always resolve key from schema (see "Resolving column keys" below).
- **Value**: The actual data stored in a cell, typed as string, number, boolean, date, or JSON object
- **Root Index Key**: The primary key field name (usually `global_id` or a custom field)
- **Root Index Value**: The primary key value for the row (UUID or string)

### Resolving column keys (item_key) — REQUIRED before read/write

**CRITICAL**: API expects **item_key** (opaque ID from schema), not the column display name. Wrong: `name`, `date`, `link`. Right: `B9pYbJFk`, `Qt1l4UDS`, `pvnsDDPn` (from schema).

**Single source of truth**: Call **getDashboardView** (or describeDashboard) **once** for the dashboard/view. Response includes `schema.items[]` with both `name` (display) and `key` (API identifier). Use that to map name → key:
```
const view = await dashboardsApi.getDashboardView({ dashboardId, viewId });
const schema = view.data?.schema ?? view.schema;
const meetingNameKey = schema.items.find(item => item.name === "Meeting Name")?.key;   // e.g. B9pYbJFk
const dateKey = schema.items.find(item => item.name === "Date/Time")?.key;             // e.g. Qt1l4UDS
const linkKey = schema.items.find(item => item.name === "Link")?.key;                 // e.g. pvnsDDPn
```
Then use these keys in getDashboardViewData (e.g. `row[meetingNameKey]`) and in batchPutDashboardData (e.g. `{ item_key: meetingNameKey, value: "..." }`). No extra discovery: one getDashboardView call gives all keys for that view.

**Chain for writing data after creating a dashboard**: Column keys (item_key) are unknown until you fetch the schema. **Always**: (1) Create dashboard (and view if needed), (2) Call **describeDashboard** or **getDashboardView** to get `schema.items[]` with `key` and `name` for each column, (3) Resolve item_key from schema (e.g. by name: `schema.items.find(item => item.name === "Column Name")?.key`), (4) Only then call **batchPutDashboardData** with those item_key values. Do not guess or hardcode keys.

### Reading Dashboard Data

**Operation**: `getDashboardViewData`
- **Purpose**: Retrieve paginated rows with values for all schema items in a view
- **Required**: `dashboardId` (UUID), `viewId` (UUID)
- **Optional Query Parameters**:
  - `filters`: Filter conditions (see filters prompt group)
  - `select`: Column selection (see tools_describe)
  - `sort`: Sort order (field name and direction)
  - `page`, `limit`: Pagination
  - `item_keys`: Array of item keys to include (filters columns)
  - `root_index_values`: Array of specific row IDs to fetch
  - `exclude_async_items`: Exclude async/computed items
  - `system_filters`: Include system filters
  - `use_stored_filters`, `use_stored_sort`: Use view's saved filters/sort
  - `section_type`, `section_key`: For section-scoped data (see tools_describe)
  - `cacheStrategy`: Cache behavior strategy (optional, default: `use`)
    - `use`: Use cached data if available (default, fastest)
    - `reset`: Rebuild cache from database and return fresh data (use when data may be stale)
    - `bypass`: Skip cache entirely and fetch directly from database (slowest, most up-to-date)
    - **When to use**:
      - `use`: Normal operations, when cached data is acceptable
      - `reset`: After schema changes, when you need to refresh the cache but still want caching for future requests
      - **`root_entity` / `rootEntity` `client`** (org **clients** dashboard): **always** pass **`cacheStrategy: "reset"`** for **getDashboardViewData** — required for correct behavior; do not use the default `use`.
      - `bypass`: When you need the absolute latest data and don't want to wait for cache rebuild

**Response Structure**:
Each row in `data` is an object with `root_index_value` and **column values keyed by item_key directly** (no nested `values` object, no `{ value, value_type }` wrapper). Cell values are **raw** (string, number, boolean, object, or array).
```json
{
  "data": [
    {
      "root_index_value": "550e8400-...",
      "yob7rlYw": 249,
      "_tgmsSVT": 100,
      "eLtAFfFU": "AirPods Pro 2"
    }
  ],
  "meta": { "page": 1, "limit": 10, "total": 100, "total_pages": 10 }
}
```
**CRITICAL**: Do not expect `row.values` or `row[item_key].value`. The value is **directly** at `row[item_key]` (e.g. `row["yob7rlYw"]` is the number 249). Handle both primitive values and objects (e.g. file columns return `{ context, files }`).

**IMPORTANT - When to use `getDashboardViewData`**:
- **Use `getDashboardViewData`** when you need to:
  - Get `root_index_value` of existing rows to UPDATE them
  - Read actual data values from existing rows
  - Query or filter existing data
- **DO NOT use `getDashboardViewData`** when:
  - Creating new rows (`create_new_row: true`) - you don't need to see existing data
  - Just trying to "inspect existing format" - use `getDashboardView` schema instead

**IMPORTANT**: Before reading data, call `getDashboardView` to understand:
- **SDK**: getDashboardView is on **DashboardsApi** (e.g. dashboardsApi.getDashboardView). getDashboardViewData and batchPutDashboardData are on **DashboardDataApi** — do not call dataApi.getDashboardView (that method does not exist).
- Available `item_key` values (from `schema.items[].key`)
- Value types for each item (from `schema.items[].json_schema.type`)
- Required vs optional items (from `schema.items[].required`)
- Item descriptions and validation rules

### Writing Dashboard Data

**To write data you need item_key for each column.** Get them from the dashboard schema: call **describeDashboard** (dashboardId) or **getDashboardView** (dashboardId, viewId), then use `schema.items[].key` (and `schema.items[].name` to map display name → key). After creating a dashboard, keys are nanoid (e.g. UWHaCU7g, EbG1KXXP) — always fetch schema first, then call batchPutDashboardData.

**Operation**: `batchPutDashboardData`
- **Purpose**: Create or update multiple dashboard rows and their values in a single request. **Use this method** for all row creation: one call with `create_new_row: true` and `values` (or `values: []` for empty row); do not use createDashboardRow (deprecated).
- **Required Parameters**: `dashboardId` (string/UUID), `viewId` (string/UUID), `body` (object)
- **Request Format**: ```{   dashboardId: 'uuid',   viewId: 'uuid',   body: {     rows: [       {         create_new_row: true,  // Optional, default: false         root_index_value: 'uuid',  // Optional for create, required for update         values: [           { item_key: 'string', value: 'any' },           { item_key: 'string', value: 123 }         ]       }     ]   } }```
- **Request Body Structure**: The `body` parameter is an **object** with a `rows` property containing an **array of row update objects**. Structure: `body: { rows: [{ ... }, { ... }] }`. **CRITICAL**: `body` must be an object with `rows` array. Incorrect: `body: { values: [...] }` or `body: [...]`. Each row object in the `rows` array contains:
  - `values` (array): Objects with `{ item_key: string, value: any }`. When `create_new_row: true`, may be empty (empty row); when updating, must have at least one element.
  - `create_new_row` (boolean, optional, default: false): Set to `true` to CREATE a new row. Use for all row creation (empty or with data); do not use createDashboardRow (deprecated).
  - `root_index_value` (string/UUID, optional): Row identifier.   - **For CREATE mode** (`create_new_row: true`): Optional - will be auto-generated if omitted.   - **For UPDATE mode** (`create_new_row: false` or omitted): **REQUIRED** - you must provide the existing row's identifier.
- **Response**: Array of updated dashboard values
- **Key Capabilities**:
  1. **Create new rows**: Set `create_new_row: true`. Use `values: []` for empty row or provide values to create and fill. `root_index_value` is optional (auto-generated if omitted). Do not use createDashboardRow.
  2. **Update existing rows**: **MUST provide `root_index_value`** (the existing row's identifier). You can set `create_new_row: false` or omit it (defaults to false).
  3. **Default behavior**: If `create_new_row` is omitted, it defaults to `false` (UPDATE mode), which requires `root_index_value`. To create a new row, you MUST explicitly set `create_new_row: true`.
  4. **Mix modes**: You can create new rows and update existing rows in the same request - just include both types in the `rows` array.
- **CRITICAL**: The `body` must be an object with a `rows` array property. Correct: `body: { rows: [...] }`. Incorrect: `body: { values: [...] }` or `body: [...]`

**BEST PRACTICE FOR LARGE BATCHES**: If you need to create many rows (e.g., 10+ rows), it's recommended to first create a single test row to validate the schema, format, and values. Once you confirm the first row is created successfully, you can then create the remaining rows in a single batch request. This helps catch validation errors early and avoids wasting API calls on invalid data. Example workflow: (1) Create one test row with `create_new_row: true`, (2) Verify it succeeds, (3) Create remaining rows in a batch.

**FAST-SAFE SEEDING WORKFLOW**:
- For demo/mock data seeding across related dashboards, optimize for **one schema read and one main write per dashboard/view**.
- Fetch schema with `getDashboardView` **once per dashboard/view** and reuse it for the rest of that seeding pass. Do **not** re-read schema before every batch or verification step unless the schema actually changed.
- Resolve `item_key` values from `schema.items[]` once, cache the name -> key mapping for the current run, and reuse it across all rows for that dashboard.
- For CREATE-only seeding, avoid `getDashboardViewData` unless you truly need existing row IDs, file context from existing cells, or a post-write verification read.
- Use a **single probe row only when schema risk is real**: link columns, files, date/date-time, labels, or other complex object/array values. For simple scalar-only tables, go straight to the main batch when the schema is clear.
- After the probe row succeeds, batch all remaining rows for that dashboard in one request instead of splitting into many small batches.
- When seeding several related dashboards, finish the full write/verify cycle for one dashboard, then move to the next; avoid repeated back-and-forth rediscovery.

**SEEDING OBSERVABILITY**:
- For seeding tasks, record a short timing breakdown per dashboard: `schema_ms`, `probe_ms` (if used), `batch_write_ms`, `verify_ms`, `retry_count`, and `rows_written`.
- If verification needs a fallback path, log which read operation was used so slow runs can be attributed to verification rather than to the write API itself.

**VALUE FORMAT AND VALIDATION**:
Each `value` in the `values` array must be a valid JSON value: `string`, `number`, `boolean`, `object` (JSON object), `array`, or `null` (to delete). **CRITICAL**: The `value` for each `item_key` MUST be valid according to the `json_schema` for that item in the dashboard schema. The value must match the json_schema type and pass all validation rules, or the request will fail with a validation error.

**Value Types** (based on schema.items[].json_schema and render.type):
- `string`: Text values (e.g., email, name, description). Must match string validation rules (format, minLength, maxLength, pattern, enum, etc.)
- `number`: Numeric values (integers or decimals). Must match number validation rules (minimum, maximum, multipleOf, etc.)
- `boolean`: True/false values. Must be exactly `true` or `false`
- **link** (render.type === "link"): Value must be **object** `{ url: string, text: string }`, **never a string**. Link columns are NOT text — passing a URL or any string is wrong. Example: `{ url: "https://...", text: "Link text" }`.
- `object`: Other complex JSON objects (e.g. files: `{ context, files }`). Must match object schema structure and validation rules
- **label** (customType label): Value is **always an array of strings** (label nanoids), e.g. `["processing"]` or `["done", "archived"]`. **Never** a single string — causes 400. json_schema: `{ type: "array", items: { type: "string" } }`. Whether one or multiple labels are allowed is per item (e.g. schema/render); API always expects array.
- `array`: Other array values. The item type is from `json_schema.items.type`:
  - **label** (items.type: "string"): `array<string>`, e.g. `["nanoid1", "nanoid2"]`
  - **Other** (items.type: "object"): `array<object>`, e.g. `[{...}, {...}]`
  - **Always check** `schema.items[].json_schema` from getDashboardView or describeDashboard
- `null`: Deletes the value for that item_key

**IMPORTANT - When to use which operation**:

**For CREATE operations** (`create_new_row: true`):
1. Call `getDashboardView` (or use schema from `describeDashboard`) to get the view schema - **DO NOT call `getDashboardViewData`**
2. Find the target items in `schema.items[]` by matching `item_key`
3. Check `item.json_schema` to understand:
   - Expected type (type: "string", "number", "boolean", "object", "array")
   - Validation rules (`format`, `minLength`, `maxLength`, `pattern`, `enum`, `minimum`, `maximum`, `required`, `properties`, `items`, etc.)
   - Required vs optional (`required: true/false` in the schema item metadata)
4. **Trust the schema** - the `json_schema` from `getDashboardView` is the source of truth for value types
5. Generate values that match the json_schema type and pass all validation rules
6. Call `batchPutDashboardData` with `create_new_row: true`

**For UPDATE operations** (updating existing rows):
1. Call `getDashboardViewData` **only if you need to get `root_index_value`** of existing rows to update
2. Use `getDashboardView` to get the schema for value types (same as CREATE)
3. Generate values matching the schema
4. Call `batchPutDashboardData` with `root_index_value` (and optionally `create_new_row: false` or omit it)

**CRITICAL RULES**:
- **NEVER** call `getDashboardViewData` just to "inspect existing format" when creating new rows
- **ALWAYS** trust the schema from `getDashboardView` or `describeDashboard` for value types
- **ONLY** call `getDashboardViewData` when you need `root_index_value` to UPDATE existing rows
- For CREATE operations, the schema alone is sufficient - you don't need to see existing data

**Dashboard Schema Caching**:
- **Before calling `describeDashboard`**: Check your conversation cache for the schema
  - Cache key: `${dashboardId}:${schemaVersion}`
  - Check: "Have I already fetched schema for dashboardId X with version Y in this conversation?"
  - If cached version exists and matches, reuse it instead of calling `describeDashboard`
- **After calling `describeDashboard`**: Store the result in conversation cache
  - Cache key: `${dashboardId}:${schema.metadata.version || schemaVersion}`
  - Cache expires at conversation scope only (not persisted across conversations)
- This reduces redundant API calls when working with the same dashboard multiple times
- For multi-dashboard seeding, keep a separate cache entry per `dashboardId:viewId` so one seeding pass does not rediscover the same view schema repeatedly

**Using `tools_describe` for Data Operations**:
- **ALWAYS use `schemaMode: "summary"`** when calling `tools_describe` for `batchPutDashboardData`:
  - Example: `tools_describe({ name: "batchPutDashboardData", schemaMode: "summary" })`
  - This returns only top-level required/properties without nested schemas
  - Provides 80% faster responses compared to "input" or "full" modes
- **Only use `schemaMode: "input"` or `"full"`** if you encounter validation errors requiring deep schema understanding
- **Default to `"summary"` mode** for all data operations unless you specifically need nested schema details

**Example: CREATE new row (using schema only)**:
```
// 1. Get schema from getDashboardView (NOT getDashboardViewData)
const view = await getDashboardView({ 
  dashboardId: '550e8400-e29b-41d4-a716-446655440000', 
  viewId: '660e8400-e29b-41d4-a716-446655440001' 
});

// 2. Find item by key
const emailItem = view.schema.items.find(item => item.key === 'email');

// 3. Check json_schema
// emailItem.json_schema might be:
// {
//   type: 'string',
//   format: 'email',
//   minLength: 5,
//   maxLength: 100
// }

// 4. Generate value matching schema (trust the schema!)
const emailValue = 'user@example.com';  // Valid email string

// 5. Create new row
await batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [{
      create_new_row: true,  // Creating new row
      values: [{ item_key: 'email', value: emailValue }]
    }]
  }
});
```

**Example: UPDATE existing row (need root_index_value)**:
```
// 1. Get existing rows to find root_index_value
const existingData = await getDashboardViewData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001'
});

// 2. Get schema for value types
const view = await getDashboardView({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001'
});

// 3. Find the row to update and get its root_index_value
const rowToUpdate = existingData.data.find(row => row.email === 'old@example.com');
const rootIndexValue = rowToUpdate.root_index_value;

// 4. Update the row
await batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [{
      root_index_value: rootIndexValue,  // Required for updates
      values: [{ item_key: 'email', value: 'new@example.com' }]
    }]
  }
});
```

**Note**: Use `batchPutDashboardData` with `create_new_row: true` for all row creation (empty row: `values: []`; with data: include values). Do not use createDashboardRow (deprecated).


**Example: Create new row with data**:
```
batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [
      {
        create_new_row: true,  // REQUIRED: Must set to true to create new row
        // root_index_value is optional here - will be auto-generated if omitted
        values: [
          { item_key: 'email', value: 'newuser@example.com' },  // string value
          { item_key: 'name', value: 'New User' },  // string value
          { item_key: 'age', value: 25 },  // number value
          { item_key: 'active', value: true },  // boolean value
        ]
      }
    ]
  }
})
```

**WARNING**: If you omit `create_new_row` or set it to `false`, you MUST provide `root_index_value` or the request will fail with "root_index_value is required when create_new_row is false".

**Note**: All values must match the json_schema for their respective item_key. For example, if `email` has `json_schema: { type: 'string', format: 'email' }`, the value must be a valid email string. If `age` has `json_schema: { type: 'number', minimum: 0 }`, the value must be a non-negative number.

**Example: Mix create and update in one request**:
```
batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [
      {
        root_index_value: 'existing-uuid-123',  // Update existing row
        values: [
          { item_key: 'email', value: 'updated@example.com' }
        ]
      },
      {
        create_new_row: true,  // Create new row
        values: [
          { item_key: 'email', value: 'new@example.com' }
        ]
      }
    ]
  }
})
```

### Related Data Operations

**Operation**: `getRelatedDashboardData`
- **Purpose**: Fetch data from dashboards connected via relations
- **Required**: `dashboardId`, `source_dashboard_id`, `source_index`
- **Optional Query Parameters**:
  - `cacheStrategy`: Same as `getDashboardViewData` (use/reset/bypass)
  - `page`, `limit`: Pagination
  - `item_keys`: Array of item keys to include
  - `exclude_async_items`: Exclude async/computed items
- **Use Case**: When you need data from a related dashboard (e.g., one_to_many, many_to_many)

**Operation**: `reindexDashboardData`
- **Purpose**: Force refresh of cached dashboard data
- **Use Case**: After schema changes or when data appears stale
- **Requires**: `dashboard.write` permission

### Data Value Structure (getDashboardViewData response)

**Response envelope**: The API returns a **body** with a **data** property: `{ data: row[], meta?: { total, page, limit, ... } }`. When using the SDK, `getDashboardViewData()` returns this full body. The array of rows is **response.data** — use it directly (e.g. `const rows = response.data`). Do **not** use `response.data.data`; there is no nested .data, so that yields undefined and empty lists.

**getDashboardViewData** returns rows where **each cell is the raw value** keyed by `item_key` on the row object. There is **no** nested `values` object and **no** `{ value, value_type }` wrapper.
- **Row shape**: `{ root_index_value: string, [item_key]: value }` — column values are **directly** on the row (e.g. `row["price_key"]` is the number 249, not `{ value: 249, value_type: "number" }`).
- **Value types**: Each cell can be `string`, `number`, `boolean`, `object`, or `array` (or undefined if empty). Use `row[item_key]` as-is for display or logic.
- **If SDK typings disagree** (for example, suggesting wrapped `DashboardValueExtended` cells), treat that as a typing artifact. Runtime `getDashboardViewData` JSON remains the source of truth.

**Reading cell values safely**: The value at `row[item_key]` may be a **primitive** (string, number, boolean) or an **object/array**. Do **not** use the `in` operator (e.g. `'value' in cell`) on primitives — it throws. Prefer: if `cell == null` return null; if `typeof cell !== 'object'` return cell as-is (primitive); if object and `'value' in cell` return cell.value; else return cell (e.g. files, link, raw objects).

**Boolean-like columns when reading (apps/SDK)**: The API may return boolean-like fields as **numbers** (1 and 0) instead of true/false. In JavaScript/TypeScript, `1 === true` is false (strict equality compares type too). When building app logic (filtering, conditions, "is active", "is deleted"), **use truthy checks or explicit normalization**, not strict equality: use `!!row[item_key]` or `if (row[item_key])` / `if (!row[item_key])`, not `row[item_key] === true`. Example: filter active rows with `rows.filter(r => !!r[COLUMNS.IS_ACTIVE])`, not `r[COLUMNS.IS_ACTIVE] === true` (the latter would drop all rows if the API returned 1).
- **Hard rule**: For values from `getDashboardViewData`, do **not** compare with `=== true`/`=== false` unless the value was normalized first. Preferred helper: `const toBool = (raw: unknown) => raw === true || raw === 1 || raw === "1";`.

### Custom column types: read and write by type

Use `schema.items[].json_schema` and `source.customType` / `render.type` from describeDashboard or getDashboardView to know the expected shape. Below: what you **read** from getDashboardViewData and what you **write** in batchPutDashboardData for each custom type.

**label** (customType label, json_schema: `{ type: "array", items: { type: "string" } }`):
- **Read**: `row[item_key]` is an **array of strings** (label nanoids), e.g. `["abc12XY", "def34ZW"]` or `[]`.
- **Write**: Value must be an **array of strings**, e.g. `["processing"]` or `["done", "archived"]`. **Never** pass a single string (e.g. `"processing"`) — that causes 400. Labels are **always** an array; whether the UI allows one or multiple labels is defined by the item schema (e.g. maxItems), but the API always expects an array.
- Example batchPut: `{ item_key: 'MxUBBZPy', value: ['processing'] }`.

**link** (customType link, json_schema: `{ type: "object", required: ["url", "text"], properties: { url, text } }`):
- **Read**: `row[item_key]` is an object `{ url: string, text: string }` or empty.
- **Write**: **Always** object with **url** and **text** (both required). Link is NOT a text column — never pass a string (e.g. URL only). Example: `{ item_key: 'pvnsDDPn', value: { url: 'https://meet.example.com/abc', text: 'Meeting' } }`.

**files** (customType files, json_schema: `{ type: "object", required: ["context", "files"], properties: { context, files } }`):
- **Read**: `row[item_key]` is `{ context: { workspaceId, target, ... }, files: [{ name, url, ... }] }`. Backend always returns context in every file cell (including empty).
- **Write**: You **must** include **context** and **files**. Do not send only `{ files: [...] }` — that causes 400. **Default**: use **defaults.defaultFileContext** from the connection (call whoami or read resource connection/context). Use that as `context` unless the user specifies a different scope or you already have the exact context from getDashboardViewData for that row. Example: `{ item_key: 'fileColKey', value: { context: defaults.defaultFileContext, files: [{ name: 'doc.pdf', url: '...' }] } }`.

**lookup** (source type lookup, including selectable: true relation columns):
- **Read**: `row[item_key]` may be a primitive (string, number) or an object/array, depending on the source column. Read with the safe cell access above (primitives as-is, no `'value' in cell` on primitives).
- **Write**: Do **NOT** write lookup/relation columns via **batchPutDashboardData**. They are filled only via **addRelationRows** (DashboardRelationsApi). Writing any value (e.g. { linkedRowId, relationId, dashboardId }) to a lookup item_key in batchPut causes 400 — the API expects a specific internal shape. To link rows: (1) create the row with batchPutDashboardData **omitting** all lookup/relation item_keys, (2) call **addRelationRows** with relationId and body.rows: [{ source_index: sourceRowRootIndexValue, target_index: targetRowRootIndexValue }]. Get relationId from findRelationsByDashboardIds or getDashboardRelationById; use root_index_value from getDashboardViewData for row IDs.

**Simple types** (string, number, boolean, email, phone, date):
- **Read**: `row[item_key]` is the primitive (string, number, boolean) or ISO date string. No wrapper. **Boolean columns**: API may return 1/0 instead of true/false; in app code use truthy checks (`!!value`, `if (value)`), not `=== true`.
- **Write**: Pass the value directly: `{ item_key: 'emailKey', value: 'a@b.com' }`, `{ item_key: 'countKey', value: 42 }`, `{ item_key: 'dateKey', value: '2025-02-06T12:00:00.000Z' }`.
- **Date and date-time columns** (json_schema `format: "date-time"` or date): **Do not send empty string** (`''`). Empty string is not a valid date-time and causes 400. To clear the value use `value: null` or omit the column from the values array.

**assignee** (json_schema: `{ type: "array", items: { type: "number" } }`): array of user IDs. **child-table-link**: object `{ title, childTableId?, childTableViewId? }` — see childTables prompt. **currency**: number.

### Link columns (type: link)

**CRITICAL**: Link columns are **not** text columns. Do **not** send the URL as a string or treat the cell as plain text. Always send the object `{ url, text }`. Wrong: `value: 'https://example.com'` or `value: 'Meeting link'`. Right: `value: { url: 'https://example.com', text: 'Meeting link' }`.

For columns with `render.type === "link"` (custom type `link`), the value is an **object** with required keys **`url`** and **`text`**. Never pass a plain string.
- **url** (string, required): The link URL (e.g. meeting link, external page).
- **text** (string, required): The display text for the link.
Example: `{ url: "https://meet.example.com/abc", text: "Meeting Name" }`. Empty link: `{ url: "", text: "" }`.
The schema item has `json_schema: { type: "object", required: ["url", "text"], properties: { url, text } }`. For link columns **always** send the object; sending a string causes wrong data or 400.

### File columns (type: files)

For columns with `render.type === "files"` (custom type `files`), the value is an **object** with **two required keys**: `context` and `files`. **Sending only `{ files: [...] }` without `context` causes 400.**
- **context** (object, required when writing): Where files are scoped. Required: `workspaceId` (string), `target` (string). Optional: `portalId`, `pageId`, `blockId`. `target` values: `"workspace"` (standalone database / workspace scope), `"portalGlobal"` (portal scope), `"portalPage"` (page scope), `"portalBlock"` (block scope).
- **files** (array, required): List of file descriptors. Each item must have `name` (string) and `url` (string). Optional: `type`, `size`, `globalId`, `bucketId`, `userId`, `workspaceId`, `storedFileUUID`, `kind`.

**When writing file columns, always use a valid context.** **Preferred**: use the **default file context** from the connection — get it via the whoami tool or resource `connection/context` and use `defaults.defaultFileContext` as the `context` value. This works for new rows and avoids 400 when the workspace is unknown. Only use a different context if (1) the user explicitly asks for another scope, or (2) you are updating an existing row and already have the exact context from getDashboardViewData for that row.

**Backend builds context for every file cell**: In **getDashboardViewData** the backend **always** returns for file columns an object with `context` and `files` in **every cell** (including empty cells). Context is **per row**: different rows can have different context (e.g. row A = workspace, row B = portal block). When **writing**, use **defaults.defaultFileContext** unless you have the exact context for that row from getDashboardViewData; do not omit context.

**Upload handoff**: For file upload lifecycle, use `file-upload/references/upload-lifecycle.md`. It owns `tempStoredFileName`, `storedFileUUID`, `readUrl`, `relative url`, and file descriptor construction.

**Writing an uploaded file to a dashboard**: First upload the file with the `file-upload` skill, then pass the resulting file descriptor to `batchPutDashboardData`. Set the file column value to `{ context: defaults.defaultFileContext, files: [descriptor] }` unless you have the exact row context from getDashboardViewData.

### Constraints and Validation

- **Read-only views**: Cannot write to views with `schema.readonly === true`
- **Root index key**: Must match dashboard's `schema.rootIndexKey`
- **Item key**: Must exist in view's `schema.items[]`
- **Value format**: Must be a valid JSON value: `string`, `number`, `boolean`, `object`, `array`, or `null`
- **JSON Schema validation**: **CRITICAL** - Each value MUST be valid according to the `json_schema` for its `item_key` in the dashboard schema. The value must match the json_schema type (string/number/boolean/object/array) and pass all validation rules (format, minLength, maxLength, pattern, enum, minimum, maximum, required, properties, items, etc.). If validation fails, the request will return a 400 Bad Request error. Always call `getDashboardView` first to check `schema.items[].json_schema` before writing values.
- **Deleting values**: Set `value: null` to delete a value for a specific `item_key`
- **Date/date-time columns**: Never send empty string (`''`) — it fails format validation (400). Use `value: null` to clear or omit the item.
- **Link columns**: Never send a string (e.g. URL only). Value must be object `{ url, text }`. Treating link as text causes wrong data.

### Common Patterns

**Parsing getDashboardViewData in feature code (SDK)**: The SDK returns the response body directly. Use **response.data** for the array of rows (not response.data.data):
```
const response = await dashboardDataApi.getDashboardViewData({ path: { dashboardId, viewId } });
const rows = response.data ?? [];  // Array<{ root_index_value, [item_key]: value }>
rows.forEach((row) => { const name = row[nameKey]; const id = row.root_index_value; /* ... */ });
```

**Reading all rows**:
```
getDashboardViewData({ dashboardId, viewId, page: 1, limit: 100 })
```

**Reading specific rows**:
```
getDashboardViewData({ dashboardId, viewId, root_index_values: ["uuid1", "uuid2"] })
```

**Reading specific columns**:
```
getDashboardViewData({ dashboardId, viewId, item_keys: ["email", "status"] })
```

**Filtering by boolean-like column (app/SDK)** — API may return 1/0; use truthy or helper normalization, not === true:
```
// Right: works when API returns 1 or true
const activeRows = rows.filter(r => !!r[COLUMNS.IS_ACTIVE]);
if (!row[COLUMNS.IS_ACTIVE]) { /* deleted */ }
// Wrong: 1 === true is false in JS, so filter returns []
const activeRows = rows.filter(r => r[COLUMNS.IS_ACTIVE] === true);  // avoid
```

**Updating existing row with multiple values**:
```
batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [
      {
        root_index_value: 'row-uuid-123',  // Required for updates
        values: [
          { item_key: 'email', value: 'user@example.com' },
          { item_key: 'name', value: 'John Doe' },
          { item_key: 'count', value: 42 }
        ]
      }
    ]
  }
})
```

**Creating new row with multiple values**:
```
batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [
      {
        create_new_row: true,  // Required to create new row
        values: [
          { item_key: 'email', value: 'newuser@example.com' },
          { item_key: 'name', value: 'Jane Doe' },
          { item_key: 'count', value: 0 }
        ]
      }
    ]
  }
})
```

**Writing label (status) column** — value is **always array of strings**, not a string:
```
// json_schema: { type: 'array', items: { type: 'string' } }
batchPutDashboardData({ ... body: { rows: [{ root_index_value: 'row-uuid', values: [{ item_key: 'MxUBBZPy', value: ['processing'] }] }] } });  // OK
// Wrong: { item_key: 'MxUBBZPy', value: 'processing' }  → 400
```

**Writing files column** — **context** is required. Use **defaults.defaultFileContext** from connection (whoami or resource connection/context) unless the row has a different context from getDashboardViewData:
```
// Get connection context first (whoami or resource connection/context), then:
batchPutDashboardData({ ... body: { rows: [{ values: [{ item_key: 'fileColKey', value: { context: defaults.defaultFileContext, files: [{ name: 'doc.pdf', url: '...' }] } }] }] } });
// Wrong: { files: [...] } without context → 400
```

**Clearing date/date-time column** — use null, not empty string:
```
batchPutDashboardData({ ... body: { rows: [{ root_index_value: 'row-uuid', values: [{ item_key: 'resolved_at', value: null }] }] } });  // OK
// Wrong: { item_key: 'resolved_at', value: '' }  → 400 (empty string is not valid date-time)
```

**Writing link column** — always object `{ url, text }`, never a string:
```
batchPutDashboardData({ ... body: { rows: [{ values: [{ item_key: 'linkColKey', value: { url: 'https://meet.example.com/abc', text: 'Join meeting' } }] }] } });  // OK
// Wrong: { item_key: 'linkColKey', value: 'https://meet.example.com/abc' }  → link is NOT text
// Wrong: { item_key: 'linkColKey', value: 'Join meeting' }  → always send { url, text }
```

**Linking rows (relation/lookup columns)** — do NOT write lookup item_key in batchPut; use addRelationRows after creating the row:
```
// 1. Create the row with only non-lookup columns (omit flipbookRel, relation columns, etc.)
await dashboardDataApi.batchPutDashboardData({ path: { dashboardId, viewId }, body: { rows: [{ create_new_row: true, values: [{ item_key: 'titleKey', value: 'My Page' }] }] } });
// 2. Link this row to another (e.g. page → flipbook): get relationId from findRelationsByDashboardIds; use root_index_value for row IDs
await dashboardRelationsApi.addRelationRows({ path: { relationId: RELATION_ID }, body: { rows: [{ source_index: flipbookRowId, target_index: pageRowId }] } });
// Wrong: including item_key for a lookup/relation column in batchPut values → 400 (format mismatch)
```

**Writing JSON object value**:
```
batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [
      {
        root_index_value: 'row-uuid-123',
        values: [
          { item_key: 'metadata', value: { tags: ['tag1'], priority: 'high' } }  // object value
        ]
      }
    ]
  }
})
```

**Note**: The object value must match the json_schema for the `metadata` item. If the schema expects `{ type: 'object', properties: { tags: { type: 'array', items: { type: 'string' } }, priority: { type: 'string', enum: ['low', 'medium', 'high'] } } }`, then the value must conform to that structure.

**Mixed create and update in one request**:
```
batchPutDashboardData({
  dashboardId: '550e8400-e29b-41d4-a716-446655440000',
  viewId: '660e8400-e29b-41d4-a716-446655440001',
  body: {
    rows: [
      {
        root_index_value: 'existing-uuid-1',  // Update existing
        values: [
          { item_key: 'email', value: 'updated1@example.com' }
        ]
      },
      {
        create_new_row: true,  // Create new row
        values: [
          { item_key: 'email', value: 'new1@example.com' }
        ]
      },
      {
        root_index_value: 'existing-uuid-2',  // Update another existing row
        values: [
          { item_key: 'status', value: 'active' }
        ]
      }
    ]
  }
})
```

---

## Version

- **Version**: 1.12.0
- **Category**: core
- **Last synced**: 2026-04-28
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
