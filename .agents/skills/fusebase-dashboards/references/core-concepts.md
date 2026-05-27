---
version: "1.6.0"
mcp_prompt: domain.overview
last_synced: "2026-04-17"
title: "Domain Overview"
category: core
---
# Domain Overview

> **MARKER**: `dashboards-core-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.overview` for latest content.

---
## Table of contents

- [Concepts](#concepts)
  - [Database](#database)
  - [Dashboard](#dashboard)
  - [Dashboard types (by `root_entity`)](#dashboard-types-by-rootentity)
  - [View](#view)
  - [Alias (human-readable identifier)](#alias-human-readable-identifier)
  - [Resolving aliases to UUIDs (resolveAliases)](#resolving-aliases-to-uuids-resolvealiases)
- [Rules of thumb](#rules-of-thumb)
- [Critical Invariants](#critical-invariants)
  - [INVARIANT: Use UUID (global_id) for all byId operations](#invariant-use-uuid-globalid-for-all-byid-operations)
- [Working with the System](#working-with-the-system)
- [Loading Prompts for Dashboard Operations](#loading-prompts-for-dashboard-operations)
  - [Intent-Based Workflow (MANDATORY for Dashboards/Views)](#intent-based-workflow-mandatory-for-dashboardsviews)
  - [Generating IDs](#generating-ids)
- [Understanding Entity Schemas](#understanding-entity-schemas)
- [Presenting database structure (diagram)](#presenting-database-structure-diagram)
  - [What to include](#what-to-include)
  - [Example (Mermaid)](#example-mermaid)
  - [Rules](#rules)

---
## Concepts

### Database
- Top-level container concept.
- Can contain multiple dashboards.
- Identified by a UUID (`global_id`).
- May have an optional human-readable alias.
- **When creating a database** (createDatabase or getOrCreateDatabase when it creates):
  - If **productId** is available (e.g. from fusebase.json or runtime env), set **alias** to `app_${productId}_{name}` where **name** is a slug derived from the database title or the requested name (lowercase, valid alias chars: letters, numbers, dots, underscores, hyphens). The total alias length must be 5–64 chars. Example: title "My Feedback" with productId "abc123" → alias `app_abc123_my_feedback`.
  - If productId is not available, do NOT include the `alias` field unless the user explicitly requests it; omit it from the create request.
- **Opening in the Thefusebase UI**: To link the user to this database in the browser, use:
  `https://{{orgDomain}}/dashboard/{{orgId}}/tables/databases/{{databaseId}}`
  - **orgDomain**: The organization’s **CNAME** when a custom domain is configured; otherwise **`{orgSubdomain}.{FUSEBASE_WEB_CLIENT_HOST}`** (org subdomain on the Fusebase tenant host; pay attention that `{FUSEBASE_WEB_CLIENT_HOST}` may be different from `{FUSEBASE_HOST}`, used in `https://app.{FUSEBASE_HOST}/...` and `https://app-api.{FUSEBASE_HOST}/...` in these prompts). Ensure you know the exact value of `FUSEBASE_WEB_CLIENT_HOST`.
  - **orgId** and **databaseId**: UUIDs (`global_id`) for the organization and database (same as in MCP tools and SDK).

### Dashboard
- Effectively a "table" of rows.
- Can belong to a database (`database_id` set) or be standalone (`database_id` is null).
- Identified by a UUID (`global_id`) and optional alias.
- Has a `root_entity` that defines where rows come from.
- Contains a schema that defines columns.

### Dashboard types (by `root_entity`)
- **`custom` dashboards**:
  - Rows are user-owned.
  - Users can typically create and delete rows.
  - Common for dashboards inside databases.
  - **MUST have a database**: A dashboard with `rootEntity=custom` must belong to a database (`database_id` set). If the database does not exist, create it first (e.g. getOrCreateDatabase or createDatabase), then create the dashboard in that database.

- **System dashboards** (non-custom `root_entity`):
  - Rows come from system or external sources (e.g. portals, workspaces, users, forms).
  - **MUST be standalone**: `database_id` MUST be null (not set).
  - **Single instance per org**: Only one dashboard with a given `root_entity` can exist per organization.
  - **Created from templates**: Creating a dashboard from a template is not available in MCP (use REST/SDK). In MCP, use **createDashboardIntent** for from-scratch dashboards or **copyDashboardFromDashboard** to copy from an existing dashboard.
  - Row creation/deletion is typically not allowed.
  - Editing of custom columns may be allowed depending on permissions and column settings.
  - Supported `root_entity` values should be confirmed via schema enums.
  - **IMPORTANT**: When creating a system dashboard:
    - DO NOT set `database_id` (must be null/omitted).
    - Check if dashboard already exists in org before creating (use `getDashboards` or `getDashboard`).
    - Template-based creation is not in MCP — use REST or SDK for that.

### View
- A projection of a dashboard.
- Does not store rows; all data lives in the parent dashboard.
- Controls column visibility and row filtering.
- Identified by a UUID (`global_id`) and optional alias.
- May override presentation aspects of dashboard columns.
- To work with views, discover the appropriate tools via `tools.search`, inspect schemas via `tools.describe`, then execute.

### Alias (human-readable identifier)
- Optional identifier used alongside UUIDs.
- Type: string | null.
- Constraints:
  - minLength: 5
  - maxLength: 64
  - pattern: `^[a-z0-9._-]+$`

- Uniqueness rules:
  - Database alias: unique within org scope.
  - Dashboard alias:
    - If `database_id` is set: unique within that database.
    - If standalone: unique within org scope.
  - View alias: unique within a dashboard.

- Tools may accept IDs or aliases depending on schema.
- Always confirm accepted identifiers via `tools.describe`.

### Resolving aliases to UUIDs (resolveAliases)

Use the **resolveAliases** operation to resolve human-readable aliases (or existing UUIDs) to canonical `global_id` and alias in one call. This avoids multiple list/get calls when you know aliases and scope.

- **Execute via**: `tool_call({ opId: "resolveAliases", args: { scope, items } })`
- **Request**:
  - `scope`: org scope where to resolve — `{ scope_type: "org", scope_id: "<org scope uuid>" }`.
  - `items`: array of items to resolve. Each item has:
    - `entity_type`: `"database"` | `"dashboard"` | `"view"`.
    - At least one of `alias` or `id` (entity alias string or its global_id).
    - For **dashboard**: provide parent with `database_id` or `database_alias`.
    - For **view**: provide parent with `database_id` or `database_alias` and `dashboard_id` or `dashboard_alias`.
- **Response**: `data.results` — same order as `items`. Each result:
  - `entity_type`, `id` (resolved global_id or null), `alias` (resolved alias or null), `resolved` (boolean).
  - If `resolved === false`: `error_code` is set (e.g. `ALIAS_NOT_FOUND`, `ID_NOT_FOUND`, `PARENT_NOT_FOUND`, `SCOPE_MISMATCH`).
- **When to use**: Before calling other ops that require UUIDs (e.g. getDashboardView, batchPutDashboardData) when you have aliases and org scope; or to validate that an alias/id exists in scope.

## Rules of thumb

- One database can contain many dashboards.
- One dashboard can have many views.
- Standalone dashboards are often system dashboards.
- Database dashboards are often `custom` dashboards.
- Row ownership depends on `root_entity`.

## Critical Invariants

### INVARIANT: Use UUID (global_id) for all byId operations
- ALL byId operations MUST use UUID (`global_id`), NOT internal database PK or numeric ID.
- When a user provides a numeric ID:
  - DO NOT use it directly in byId operations.
  - MUST resolve the correct UUID first via list/search tools.
- Examples:
  - Get dashboard by ID → use `dashboardId: '<uuid>'`, NOT `dashboardId: 123`
  - Get database by ID → use `databaseId: '<uuid>'`, NOT `databaseId: 456`
  - Get view by ID → use `viewId: '<uuid>'`, NOT `viewId: 789`
- If unsure whether an ID is a UUID, check format: UUIDs are strings like `'550e8400-e29b-41d4-a716-446655440000'`.

## Working with the System

- Discover operations via `tools_search`.
- Inspect required inputs and outputs via `tools_describe`.
- Execute via `tool_call` (required for business operations).
- Confirm exact field names, enums, and constraints via schemas.

## Loading Prompts for Dashboard Operations

**ALWAYS use groups filter when loading prompts**:
- **ALWAYS use**: `prompts_search({ groups: ["data", "rows", "schema"] })`
- **NEVER use**: `prompts_search({})` or `prompts_search` without groups filter
- **Only load additional prompt groups** if operation requires them:
  - Add `"dashboard"` group only if creating new dashboards
  - Add `"filters"` group only if working with view filters
  - Add `"templates"` group only if working with dashboard templates
  - Add `"relations"` group only if working with dashboard relations
- **Default groups for dashboard operations**: `["data", "rows", "schema"]`

### Intent-Based Workflow (MANDATORY for Dashboards/Views)

**For creating/updating dashboards and views, use Intent endpoints:**
1. Discover: `tools_search(queries: ["create dashboard", "intent"])`
2. Inspect: `tools_describe(name: "<found tool>", schemaMode: "input")`
3. Execute: `tool_call({ opId: "<exact name>", args: { ... } })`

**IMPORTANT:**
- Use Intent endpoints (`createDashboardIntent`, `createViewIntent`, `updateViewIntent`). For schema or column changes act through the view via updateViewIntent; changes automatically sync to the main dashboard.
- DO NOT use legacy full-schema operations in MCP.
- DO NOT call allowed-items tool before creating/updating dashboards.
- Provide simplified Intent payloads (type + name), backend enriches automatically.
- Keys and aliases are auto-generated if omitted.

### Generating IDs

- Use the `generate_id` meta tool to generate UUIDs or nanoids for create operations.
- For global_id fields (dashboardId, viewId, databaseId, etc.): use `format: 'uuid'`.
- For compact keys or aliases: use `format: 'nanoid'`.
- Example: `generate_id({ format: 'uuid', count: 1 })` → `{ ids: ['550e8400-e29b-41d4-a716-446655440000'], format: 'uuid', count: 1 }`
- Can generate multiple IDs at once (up to 100).

## Understanding Entity Schemas

- To understand dashboard structure and schema: Call `getDashboard` (discover via `tools_search`).
- To understand database structure: Call `getDatabase` (discover via `tools_search`).
- To understand view structure: Call `getDashboardView` (discover via `tools_search`).
- The tool responses contain the actual entity structure—use these as the authoritative schema reference.
- Do NOT rely solely on prompts for field names—always inspect actual tool outputs.

## Presenting database structure (diagram)

**After creating a database or when the user asks for the structure**, render the database structure as a **diagram** in the response (e.g. Mermaid).

### What to include
1. **Database** as the top-level container; **dashboards** (tables) as nodes—use dashboard name or alias as label.
2. **Relations** (if any): For each relation between dashboards, draw an edge **source → target** and label it with the relation type (`one_to_one`, `one_to_many`, `many_to_many`). Get relations via `findRelationsByDashboardIds` for each dashboard, or from expanded database/dashboard data.
3. **Child tables** (if any): For each dashboard that has a **child-table-link** column in its schema, draw an edge **parent dashboard → child table** (e.g. "has child" or "1:N per row"). Child tables are dashboards linked from a cell; the schema item has `customType: "child-table-link"`.

### Example (Mermaid)
```
erDiagram
  DATABASE ||--o{ DashboardA : contains
  DATABASE ||--o{ DashboardB : contains
  DashboardA ||--o{ DashboardB : one_to_many
  DashboardA ||--o{ ChildTable : "child-table-link"
```

### Rules
- Prefer a diagram in the same response as the create/get result so the user sees structure at a glance.
- If there are no relations and no child-table-link columns, a simple list or tree of database → dashboards is enough; a minimal diagram still helps.
- Use clear labels: dashboard names/aliases, relation types, and "child" for child-table links.
---

## Version

- **Version**: 1.6.0
- **Category**: core
- **Last synced**: 2026-04-17
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
