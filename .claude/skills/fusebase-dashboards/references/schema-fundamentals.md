---
version: "1.4.2"
mcp_prompt: domain.dashboardSchema
last_synced: "2026-05-07"
title: "Dashboard Schema"
category: core
---
# Dashboard Schema

> **MARKER**: `dashboards-schema-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.dashboardSchema` for latest content.

---
## Table of contents

- [Concepts](#concepts)
  - [Dashboard Schema](#dashboard-schema)
  - [Schema Items (Columns)](#schema-items-columns)
  - [Source Semantics](#source-semantics)
  - [Alias (Human-Readable Identifier)](#alias-human-readable-identifier)
- [Loading Prompts for Dashboard Schema Operations](#loading-prompts-for-dashboard-schema-operations)
- [Intent-Based Workflow (MANDATORY)](#intent-based-workflow-mandatory)
  - [IMPORTANT: Use Intent Endpoints Only](#important-use-intent-endpoints-only)
  - [Intent vs Full Schema Requests](#intent-vs-full-schema-requests)
  - [Date columns (`type: "date"`): format options](#date-columns-type-date-format-options)
  - [Text columns (`type: "string"`): single-line vs multi-line](#text-columns-type-string-single-line-vs-multi-line)
  - [Intent Workflow](#intent-workflow)
- [Key Generation Rules](#key-generation-rules)
  - [Auto-Generated Keys](#auto-generated-keys)
  - [When to Provide Keys](#when-to-provide-keys)
  - [Examples](#examples)
- [Default Creation and Overrides](#default-creation-and-overrides)
  - [Default Behavior](#default-behavior)
  - [Overrides Only for Selected Item Types](#overrides-only-for-selected-item-types)
  - [Lookup Columns (type: "lookup"): Relation vs Lookup (UX)](#lookup-columns-type-lookup-relation-vs-lookup-ux)
  - [Label Fields (type: "label")](#label-fields-type-label)
  - [WARNING: Do NOT Invent Low-Level Fields](#warning-do-not-invent-low-level-fields)
- [Critical Invariants](#critical-invariants)
  - [INVARIANT: Use UUID (global_id) for byId Operations](#invariant-use-uuid-globalid-for-byid-operations)
  - [INVARIANT: Dashboard Schema is Source of Truth; Views are Projections](#invariant-dashboard-schema-is-source-of-truth-views-are-projections)
  - [RULE: Schema Changes vs View Projection Changes](#rule-schema-changes-vs-view-projection-changes)
  - [Tool Distinction: getDashboard vs describeDashboard](#tool-distinction-getdashboard-vs-describedashboard)
  - [Dashboard Schema Caching (IMPORTANT)](#dashboard-schema-caching-important)
  - [Column type vs display format (CRITICAL)](#column-type-vs-display-format-critical)
- [Working with Schema Items](#working-with-schema-items)
  - [Adding Columns (act through the view; syncs to dashboard)](#adding-columns-act-through-the-view-syncs-to-dashboard)
  - [Modifying Columns (act through the view)](#modifying-columns-act-through-the-view)
  - [Showing/Hiding Columns in a View](#showinghiding-columns-in-a-view)
  - [Custom Columns](#custom-columns)
- [Standalone Dashboards (Non-Custom rootEntity)](#standalone-dashboards-non-custom-rootentity)
  - [Rules for System Dashboards](#rules-for-system-dashboards)
  - [Workflow for System Dashboards (in MCP)](#workflow-for-system-dashboards-in-mcp)
- [Pitfalls](#pitfalls)
- [Notes](#notes)

---
## Concepts

### Dashboard Schema
- Defines the structure of a dashboard (columns and layout).
- Stored as a schema object containing column definitions and metadata.
- Exact shape should be confirmed via `tools_describe`.

### Schema Items (Columns)
- Columns are defined in `schema.items`.
- Each item includes:
  - `key`: Unique identifier (string, typically nanoid length 8; NOT UUID). **Use this as item_key** in getDashboardViewData and batchPutDashboardData — never use display name.
  - `name`: Display name (for UI). To get key from name: `schema.items.find(item => item.name === "Meeting Name")?.key`.
  - `description`: Human-readable description.
  - `source`: How data is sourced (root, custom, assoc, func, lookup).
  - `render`: Presentation and formatting hints.
  - `json_schema`: Validation rules.
  - `readonly`, `hidden`, and other optional flags.
  - Optional `alias`.
- Confirm exact fields via schema inspection.

### Source Semantics
- **`root`**: Value comes from underlying system/root record (common for system dashboards).
- **`custom`**: User-entered values stored per row (common for custom dashboards).
- **Other sources** (assoc, func, lookup): Derived or related data.
- Supported values must be confirmed via schema.

### Alias (Human-Readable Identifier)
- Optional identifier alongside UUIDs.
- Constraints: minLength=5, maxLength=64, pattern=`^[a-z0-9._-]+$`.
- Unique within schema (within a dashboard).
- Can be used to reference items in tools that support it.

## Loading Prompts for Dashboard Schema Operations

**ALWAYS use groups filter when loading prompts**:
- **ALWAYS use**: `prompts_search({ groups: ["data", "rows", "schema"] })`
- **NEVER use**: `prompts_search({})` or `prompts_search` without groups filter
- **Only load additional prompt groups** if operation requires them:
  - Add `"dashboard"` group only if creating new dashboards
  - Add `"filters"` group only if working with view filters
  - Add `"templates"` group only if working with dashboard templates
- **Default groups for schema operations**: `["data", "rows", "schema"]`

## Intent-Based Workflow (MANDATORY)

### IMPORTANT: Use Intent Endpoints Only
- **In MCP, you MUST use Intent-based endpoints for creating/updating dashboards and views.**
- **Legacy full-schema operations are NOT recommended and may be disabled in MCP.**
- **DO NOT call allowed-items tool before creating/updating dashboards.**
- **DO NOT manually construct full schema items with low-level fields.**

### Intent vs Full Schema Requests

**Intent Request (Recommended)**
- Simplified payload: provide `type` and `name` for each column.
- Backend auto-generates: `key` (nanoid), `alias` (if omitted), and all low-level fields.
- Backend enriches Intent into canonical full schema using templates.
- Example: `{ type: "string", name: "Email", required: true }`

**CRITICAL: Intent `type` vs render `edit_type`**
- In items_intent use **`type`** from the allowed enum: `string`, `number`, `boolean`, `email`, `phone`, `date`, `currency`, `label`, `link`, `files`, `time`, `lookup`, `child-table-link`, etc.
- The API does **not** accept `edit_type` values for `type`. Use `type: "string"` for any text column (not `type: "string-single-line"`).
### Date columns (`type: "date"`): format options

- Date columns use render settings to control how the same column is displayed/input in UI.
- Use `render.date_format` with one of: `"date"`, `"date-time"`, `"time"`.
- `"date"`: date only (calendar date).
- `"date-time"`: date + time in one column.
- `"time"`: time only in one column (still the same date-type column, not a separate column).
- If not overridden, backend defaults apply. For writes, always validate against `schema.items[].json_schema` from getDashboardView/describeDashboard.

**Overrides only for selected item types**: In MCP, use **overrides** for **label** columns (`overrides.render`, e.g. labels), **lookup/relation** columns (`overrides.source` required), **string columns that must be multi-line** (`overrides.render` with `multi_line: true` — see Text columns below), and **date** (when you need to change display format). For number, boolean, email, etc., do not use overrides — use only `type` and `name` (unless you need string multi-line).

### Text columns (`type: "string"`): single-line vs multi-line

- **Default**: `type: "string"` alone produces a **single-line** text field (short values, titles, one-line inputs).
- **Long text** (descriptions, notes, comments, multi-line content): turn on **multi-line** editing by setting **`overrides.render`** with the string render shape and **`multi_line: true`** (and `edit_type: "string-multi-line"`). Without this, the UI stays single-line and is unsuitable for paragraphs.
- Typical fields: `_type_string: true`, `type: "string"`, `edit_type: "string-multi-line"`, `is_lookup: false`, `text_wrap: "wrap"`, `multi_line: true`. Confirm exact shape via `tools_describe` and working examples in the API.
- **Example** (Intent add column):
  ```
  {
    type: "string",
    name: "Description",
    overrides: {
      render: {
        _type_string: true,
        type: "string",
        edit_type: "string-multi-line",
        is_lookup: false,
        text_wrap: "wrap",
        multi_line: true,
      },
    },
  }
  ```

**createDashboardIntent: body.scopes is required**
- Request body must include **`scopes`** (array). Use scope from connection context: call **bootstrap** (or read connection context resource) and use **`defaults.toolArgs`** to build scopes, e.g. `scopes: [{ scope_type: defaults.toolArgs.scope_type, scope_id: defaults.toolArgs.scope_id }]`.
- Omitting `scopes` or passing an empty array returns 400.

**Full Schema Request (Legacy - NOT for MCP)**
- Requires complete schema item with all fields: `_type_*`, `edit_type`, `index.fields.path`, etc.
- Must call allowed-items tool to get template definitions.
- Error-prone and verbose.
- **DO NOT USE in MCP workflows.**

### Intent Workflow

**Note on examples**: Examples below sometimes omit required path/query parameters (e.g. dashboardId, viewId). Always pass all required parameters as shown by `tools_describe` for each operation.

**Creating a Dashboard (only when the corresponding MCP tools are visible):**
- **For `rootEntity=custom`**: The dashboard must belong to a database. In default app flows, attach it to an existing project database. Only use database-creation flows if your MCP session explicitly exposes them.
1. Discover: `tools_search(queries: ["create dashboard", "intent"])`
2. Inspect: `tools_describe(name: "createDashboardIntent", schemaMode: "input")`
3. Execute: `tool_call({ opId: "createDashboardIntent", args: { schema: { items_intent: [...] } } })`

**Updating schema or adding columns:**
Act through the view: use updateViewIntent with schema_patch (add, update, remove). Changes automatically sync to the main dashboard.
1. Discover: `tools_search(queries: ["update view", "intent", "schema"])`
2. Inspect: `tools_describe(name: "updateViewIntent", schemaMode: "input")`
3. Execute: `tool_call({ opId: "updateViewIntent", args: { schema_patch: { add: [...], update: [...], remove: [...] } } })`

**Creating a View:**
1. Get dashboard schema to see available columns: tool_call({ opId: "describeDashboard", ... })
2. Discover: `tools_search(queries: ["create view", "intent"])`
3. Inspect: `tools_describe(name: "createViewIntent", schemaMode: "input")`
4. Execute: `tool_call({ opId: "createViewIntent", args: { column_keys: ["key1", "key2"] } })`

**Updating view schema (add/update/remove columns):**
Use updateViewIntent with schema_patch. New columns added via schema_patch.add appear in the view and automatically sync to the dashboard. To add an existing dashboard column to the view, use schema_patch.add with key (and type, name).
1. Discover: `tools_search(queries: ["update view", "intent"])`
2. Inspect: `tools_describe(name: "updateViewIntent", schemaMode: "input")`
3. Execute: `tool_call({ opId: "updateViewIntent", args: { schema_patch: { add: [...], update: [...], remove: [...] } } })`

## Key Generation Rules

### Auto-Generated Keys
- **Column `key` (nanoid)**: Auto-generated by backend if omitted in Intent.
- **Column `alias`**: Auto-generated using slugify if omitted.
- **LLM should omit keys/aliases** unless needed for specific reasons (e.g., patching existing columns by key).

### When to Provide Keys
- **Updates**: Provide `key` when updating existing columns via `updateViewIntent` (schema_patch.update).
- **Stable References**: Only if you need to reference the column by key in other operations.
- **Default**: Omit keys and let backend generate them.

### Examples

**Create without keys (recommended):**
```
createDashboardIntent({
  name: "My Dashboard",
  database_id: null,
  schema: {
    items_intent: [
      { type: "string", name: "Email", required: true },
      { type: "number", name: "Age" }
    ]
  },
  scopes: [{ scope_type: "<from bootstrap defaults.toolArgs>", scope_id: "<from bootstrap defaults.toolArgs>" }]
})
```

**Update using key (via view; syncs to dashboard):**
```
updateViewIntent({
  dashboardId: "<uuid>",
  viewId: "<uuid>",
  schema_patch: {
    update: [
      { key: "existing-key", patch: { type: "string", name: "Updated Name" } }
    ]
  }
})
```

## Default Creation and Overrides

### Default Behavior
- Columns are created from `type` + `name` (and optional properties: `alias`, `required`, `unique`, `readonly`, `hidden`).
- Backend enriches Intent with all low-level fields automatically.

**What `unique: true` means (columns):**
- If `unique: true` is set for a column, the backend treats that column as a **uniqueness constraint** when creating/updating rows for the dashboard (duplicates are rejected).
- Use `unique` columns to make operations **idempotent**: before creating a new row, load existing rows via `getDashboardViewData` and check if a row with the same unique column value already exists; if it does, update that row instead of creating a new one.
- If the API returns a **uniqueness/duplicate** error during a create/update attempt, do NOT blindly retry with `create_new_row: true`. Instead: load existing rows for the view, find the row matching the attempted unique value, then update that row (LLM may not know all existing values).

### Overrides Only for Selected Item Types
- In MCP, **overrides** are allowed only for:
  - **Label columns** (`type: "label"`): use `overrides.render` (e.g. `labels` array with nanoid, name, color).
  - **Lookup/relation columns** (`type: "lookup"`): relation binding must be in `overrides.source` (required; see Lookup Columns below); use `overrides.render` for render config when needed.
  - **Date columns** (`type: "date"`): use `overrides.render` to control display/input format (`date_format`, `date_render`, etc.).
  - **String columns** (`type: "string"`): use **`overrides.render` only** to enable **multi-line** long text (`multi_line: true`, `edit_type: "string-multi-line"`); see **Text columns** above. Do not add arbitrary `overrides.render` for string for other reasons.
- For column types other than label, lookup, date, and string-multi-line (number, boolean, email, etc.) do **not** use overrides — use only `type` and `name` (and optional key, required, hidden, etc.).
- Do not use `overrides.render` or `overrides.source` except for label, lookup, date, or string multi-line as above.

### Lookup Columns (type: "lookup"): Relation vs Lookup (UX)

**CRITICAL: Lookup config goes in overrides.source, NOT overrides.render.** The fields `_type_lookup`, `type`, `selectable`, and `relations` must be inside `overrides.source`. Putting them in `overrides.render` or at the top level of the add item causes INVALID_ARGS (invalid_union or Unrecognized keys).

Both **relation column** and **lookup column** use `type: "lookup"` in the schema. The difference is editable vs read-only (controlled by `selectable` and `readonly`):

- **Relation column** (editable): In the UI the user can add or remove linked rows. Set `selectable: true`, `readonly: false` in `overrides.source`. Exactly one column per relation_id is editable.
- **Lookup column** (read-only): Column only displays data from the related rows. Set `selectable: false`, `readonly: true` in `overrides.source`.

**Flow:** Create the relation via `createDashboardRelation` (see domain.relations for direction: source = table you fetch from, target = view where columns live) → add relation rows via `addRelationRows` → add the first editable relation column → optionally add lookup columns for the same relation.

- **Prerequisites**: Relation must exist; relation rows (addRelationRows) define which rows are linked; without them, cells stay empty.
- **Intent**: Use `type: "lookup"` and **required** `overrides.source`:
  - **`_type_lookup: true`** (required for validation), `type: "lookup"`, `selectable` (true = relation column, false = lookup column), `readonly` (false for relation, true for lookup),
  - `relations`: array of one object with `relation_id`, `dashboard_id` (source dashboard), `view_id` (source view), `item_key` (source column key from that view), `reverse: false`, `relation_type` (e.g. `one_to_many`).
- **Key**: When adding **multiple** lookup columns (e.g. one relation + several lookups), provide an explicit **`key`** for each (e.g. `books-relation`, `book-title-lookup`, `book-year-lookup`) to avoid duplicate key errors. Single column can omit key.
- **Add via view**: Use `updateViewIntent` with `schema_patch.add` (type lookup, overrides.source). Column syncs to the dashboard.
- **Example** (add editable relation column; syncs to dashboard):
  ```
  updateViewIntent({
    dashboardId: "<target-dashboard-uuid>",
    viewId: "<target-view-uuid>",
    schema_patch: {
      add: [{
        type: "lookup",
        name: "Project (Relation)",
        overrides: {
          source: {
            _type_lookup: true,
            type: "lookup",
            selectable: true,
            relations: [{
              relation_id: "<relation-uuid>",
              dashboard_id: "<source-dashboard-uuid>",
              view_id: "<source-view-uuid>",
              item_key: "<source-column-key>",
              reverse: false,
              relation_type: "one_to_many"
            }]
          }
        }
      }]
    }
  })
  ```
- For a **read-only lookup column** (same relation), use the same structure but `selectable: false` (and `readonly: true`).
- To **update** an existing lookup (e.g. change `selectable`/`readonly`), use `schema_patch.update` with the same key and `patch.overrides.source`. The same lookup validation applies (relation must exist, correct direction, dashboard_id/view_id/item_key); see domain.relations for 400 error messages.

### Label Fields (type: "label")
- **REQUIREMENT**: When creating a dashboard with a label field (`type: "label"`), you MUST provide at least one label in the set.
- Labels are defined via `overrides.render.labels` in the Intent request.
- Each label must include:
  - `nanoid`: Unique identifier (generate using `generate_id({ format: "nanoid" })`).
  - `name`: Display name for the label.
  - `color`: Color identifier (e.g., "red", "yellow", "green", "blue", etc.).
- Label field structure:
  ```
  {
    "type": "label",
    "name": "Priority",
    "overrides": {
      "render": {
        "_type_label": true,
        "edit_type": "label",
        "type": "label",
        "is_lookup": false,
        "multi_select": false,
        "labels": [
          { "nanoid": "<generate-nanoid>", "name": "High", "color": "red" },
          { "nanoid": "<generate-nanoid>", "name": "Medium", "color": "yellow" },
          { "nanoid": "<generate-nanoid>", "name": "Low", "color": "green" }
        ]
      }
    }
  }
  ```
- **IMPORTANT**: If you create a label field without providing labels via `overrides.render.labels`, the field will be invalid.
- Generate nanoids for each label using: `generate_id({ format: "nanoid", count: <number-of-labels> })`

### WARNING: Do NOT Invent Low-Level Fields
- **DO NOT** hand-author low-level schema fields like `index.fields.path` or full enriched items outside Intent rules.
- For normal columns, backend enriches `_type_*` and related fields from templates.
- Only provide Intent-level fields: `type`, `name`, `alias?`, `required?`, `unique?`, `readonly?`, `hidden?`, `overrides?`.
  - `unique?: boolean`: when `true`, backend enforces a uniqueness constraint for that column value across rows.
- **Exception**: For label fields, you MUST provide `overrides.render` with the full label structure including `_type_label`, `edit_type`, `type`, `is_lookup`, `multi_select`, and `labels` array.
- **Exception**: For **multi-line string** columns, provide `overrides.render` with the string multi-line shape (`_type_string`, `edit_type: "string-multi-line"`, `multi_line: true`, etc.); see **Text columns** above.

## Critical Invariants

### INVARIANT: Use UUID (global_id) for byId Operations
- ALL byId operations MUST use UUID (`global_id`), NOT internal database PK/numeric ID.
- If user provides a numeric ID, resolve the correct UUID first via list/search tools.
- Dashboard ID = UUID, View ID = UUID, Database ID = UUID.

### INVARIANT: Dashboard Schema is Source of Truth; Views are Projections
- **Dashboard schema** = full list of all possible columns.
- **View** = projection of dashboard (subset of columns, custom ordering, visibility rules).
- When working with views:
  - To get canonical schema, call describeDashboard (discover via tools_search)..
  - describeDashboard returns schema.items with all available columns.
  - Views inherit dashboard schema and may override visibility/ordering.

### RULE: Schema Changes vs View Projection Changes

### Tool Distinction: getDashboard vs describeDashboard

**getDashboard:**
- Returns metadata: name, views list, scopes, timestamps
- Does NOT return schema (columns)
- Use when you need: view IDs, dashboard metadata, checking existence

**describeDashboard:**
- Returns FULL dashboard including schema.items (all columns)
- Use when you need: column definitions, keys, types, structure
- Required for: adding columns, modifying schema, understanding structure
- **Required for writing data**: To call batchPutDashboardData you need item_key for each column; they are in schema.items[].key (nanoid, e.g. UWHaCU7g). After creating a dashboard, call describeDashboard or getDashboardView to get these keys, then use them in batchPutDashboardData.

### Dashboard Schema Caching (IMPORTANT)

**Implement schema caching to avoid redundant API calls**:

1. **Before calling `describeDashboard`**:
   - Check your conversation cache: "Have I already fetched schema for dashboardId X with version Y in this conversation?"
   - Cache key format: `${dashboardId}:${schemaVersion}`
   - Extract `schemaVersion` from `schema.metadata.version` or `schemaVersion` field in the response
   - If cached version exists and matches current `schemaVersion`, reuse the cached schema

2. **After calling `describeDashboard`**:
   - Store the result in your conversation cache
   - Cache key: `${dashboardId}:${schema.metadata.version || schemaVersion}`
   - Store the full dashboard object including schema.items

3. **Cache scope**:
   - Cache expires at conversation scope only (do NOT persist across conversations)
   - Each new conversation starts with an empty cache
   - Cache is valid only for the current conversation session

4. **Example workflow**:
   ```
   // Before calling describeDashboard:
   const cacheKey = `${dashboardId}:${schemaVersion}`;
   if (cachedSchemas[cacheKey]) {
     // Reuse cached schema
     return cachedSchemas[cacheKey];
   }

   // Call describeDashboard
   const dashboard = await tool_call({ opId: 'describeDashboard', args: { dashboardId } });

   // Store in cache
   const version = dashboard.schema.metadata.version || dashboard.schemaVersion;
   cachedSchemas[`${dashboardId}:${version}`] = dashboard;
   ```

5. **Benefits**:
   - Reduces API calls when working with the same dashboard multiple times
   - Faster response times for repeated schema lookups
   - Better user experience with reduced latency

**Schema and column changes: act through the view (CRITICAL):**
- **For updating schema or adding/editing/removing columns**, use **updateViewIntent** with `schema_patch` (add, update, remove).
- **Changes made through the view automatically sync to the main dashboard schema.** New columns added via schema_patch.add appear in the view and in the dashboard.
- To add a **new** column: use `updateViewIntent` with `schema_patch.add` (type, name; key optional). It appears in the view and syncs to the dashboard.
- To add an **existing** dashboard column to the view: use `schema_patch.add` with key (and type, name).
- To update or remove columns: use `schema_patch.update` or `schema_patch.remove`.

**updateViewIntent (schema_patch):**
- Use `schema_patch` with `add`, `update`, `remove` operations.
- Single payload for both view schema and dashboard sync: changes to the view automatically sync to the main dashboard.
- To show/hide column in view: use `schema_patch.update` with `patch.hidden`.

### Column type vs display format (CRITICAL)

- **Column data type cannot be changed** after creation. There is no mechanism to convert existing data (e.g. string → number, files → date, or any other type change). Changing type would require data migration, which is not supported.
- **You can only change the display format** for columns that support overrides (label, lookup, and **string multi-line** via `patch.overrides.render`): use `schema_patch.update` with `patch.overrides.render` where applicable. For other columns you can update name, description, hidden.
- If the user asks to "change column type" or "convert column to number/date/files", explain that the data type is fixed; only the presentation (render) can be updated. To get a different type, they would need a new column and, if desired, manual data entry or a separate export/transform flow.

## Working with Schema Items

### Adding Columns (act through the view; syncs to dashboard)
Use updateViewIntent with schema_patch.add. New columns appear in the view and automatically sync to the main dashboard.
1. Discover: `tools_search(queries: ["update view", "intent"])`
2. Inspect: `tools_describe(name: "updateViewIntent", schemaMode: "input")`
3. Add new column: `tool_call({ opId: "updateViewIntent", args: { schema_patch: { add: [{ type: "string", name: "New Column" }] } } })`
- The column is added to the view and synced to the dashboard in one call.

### Modifying Columns (act through the view)
1. Get current schema: `tool_call({ opId: "describeDashboard", args: { dashboardId: "<uuid>" } })` or getDashboardView for view columns.
2. Locate item by `key` in schema.items.
3. Execute: `tool_call({ opId: "updateViewIntent", args: { schema_patch: { update: [{ key: "<item-key>", patch: { name: "Updated Name" } }] } } })` (or patch overrides.render for label/lookup columns).
- You can update name, description, hidden for any column; **overrides.render** for label, lookup, and string multi-line (see Text columns). You **cannot** change the column's data type (e.g. string → number).
- Changes sync to the dashboard.

### Showing/Hiding Columns in a View
1. Get current view: `tool_call({ opId: "getDashboardView", args: { dashboardId: "<uuid>", viewId: "<uuid>" } })`
2. Execute: `tool_call({ opId: "updateViewIntent", args: { schema_patch: { update: [{ key: "<item-key>", patch: { type: "string", name: "<name>", hidden: true } }] } } })`

### Custom Columns
- Columns for user-entered values are typically `type: "custom"` in Intent.
- Values are provided when creating or updating rows via `batchPutDashboardData`.
- Always confirm expected row payload shape via `tools_describe`.

## Standalone Dashboards (Non-Custom rootEntity)

### Rules for System Dashboards

**When `rootEntity != 'custom'`:**
- **MUST be standalone**: `database_id` MUST be null (not set).
- **Single instance per org**: Only one dashboard with a given `root_entity` can exist per organization.
- **Created from templates**: System dashboards are normally created from static templates; **template creation is not exposed in MCP** — use REST or SDK for that.

### Workflow for System Dashboards (in MCP)

**Before creating a system dashboard:**
1. Check if dashboard already exists: `tools_search(queries: ["get dashboard", "list dashboards"])` or `getDashboards` / `getDashboard`.
2. Filter by `root_entity` and org scope to see if a dashboard for that entity type already exists.

**If dashboard doesn't exist:**
- In MCP you cannot create system dashboards from templates (`createDashboardFromTemplate` is not a tool). Use **createDashboardIntent** only for custom dashboards; for system dashboards use REST or SDK.

**IMPORTANT:**
- DO NOT set `database_id` when creating system dashboards (must be null/omitted).
- For system (non-custom) dashboards, template-based creation is outside MCP.

## Pitfalls

- **Wrong key for update**: When updating an existing column via updateViewIntent (schema_patch.update), use the column key from describeDashboard or getDashboardView. Keys are stable (nanoid), not display names.
- **Changing column type**: Do not attempt to change a column's data type (e.g. string → number, files → date). It is not supported; only render (display format) can be updated.

## Notes

- View schemas may override visibility or presentation of dashboard columns.
- Schema structure, supported fields, and constraints are authoritative in tool schemas.
- **To understand dashboard schema structure: Call describeDashboard (discover via tools_search) to retrieve the actual dashboard object with its full schema.
- **To understand Intent request structure**: Call `tools_describe(name: "createDashboardIntent", schemaMode: "input")` to see required Intent fields.
- Do NOT rely solely on this prompt for schema field names—always inspect actual tool responses via `tools_describe` and `tool_call`.
---

## Version

- **Version**: 1.4.2
- **Category**: core
- **Last synced**: 2026-05-07
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
