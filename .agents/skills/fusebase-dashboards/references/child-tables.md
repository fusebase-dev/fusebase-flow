---
version: "1.0.0"
mcp_prompt: domain.childTables
last_synced: "2026-03-06"
title: "Child Tables"
category: specialized
---
# Child Tables

> **MARKER**: `dashboards-childtables-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.childTables` for latest content.

---
## Concepts

### Child table
- A **child table** is a dashboard linked from a single cell in another dashboard (the **main** or **parent** table).
- One child dashboard per (parent row, child-table-link column). Different parent rows get their own child dashboards for the same column.
- Child tables can be nested: a child dashboard can have its own child-table-link columns.

### Child-table-link column
- Schema item: `source.type === "custom"`, `source.customType === "child-table-link"`, render type `child-table-link`.
- Cell value: `{ title, childTableId, childTableViewId }`. If childTableId is null, the child dashboard has not been created yet.
- The column has an optional **template** (dashboard_id, dashboard_alias, database_id, database_alias) — if set, new children are created from that template; if all empty, an empty custom table is created.

### Main table vs child table
| Main table (parent) | Child table |
|---------------------|-------------|
| Dashboard with at least one child-table-link column | Dashboard created for a specific (parent, parent row, column) |
| Rows are parent rows | Has scopes parent_table and parent_row linking to the parent cell |
| Cell holds childTableId to open the child | Full dashboard: own schema, views, rows; use normal data APIs with its dashboard ID |

### Schema and column keys in child tables (created from template)
- When a child is created **from a template**, its schema is a **copy** of the template; **schema item keys (e.g. nanoid) are unique per dashboard**.
- Different child dashboards have **different keys** for the same logical column (e.g. "Title" may be key `Ji__vDuB` in one child and `NuTmgNZz` in another).
- **Do not** reuse keys from the parent, from another child, or hardcode keys when reading/writing a specific child. Always get **that child's** schema and resolve column keys from it.
- **Workflow**: To read/write child table data: (1) Get that child's schema (e.g. getDashboardView or getDashboardViewData for the child dashboard). (2) Resolve column **by name**: `schema.items.find(item => item.name === "Column Name")` and use `item.key` in batchPutDashboardData / getDashboardViewData. Never assume keys are shared across child dashboards.

## MCP Operation (use with tool_call)

| OpId | Purpose | Key args |
|------|--------|----------|
| **getChildTableLinkDashboard** | Get or create the child dashboard for a child-table-link cell | Body: scope_type, scope_id, dashboard_id (parent), item_key (column key), root_index_value (parent row id) |

**Behavior**: If the cell already has childTableId, returns that dashboard (created: false). If not, creates a new dashboard (from template or empty), writes childTableId and default view id into the cell, returns the dashboard (created: true).

## Typical workflow (via tool_call)

### Get or create child table for a cell
1. Ensure parent dashboard has a child-table-link column and the row exists (e.g. batchPutDashboardData with create_new_row: true).
2. `tool_call({ opId: "getChildTableLinkDashboard", args: { body: { scope_type: "org", scope_id: "<org-id>", dashboard_id: "<parent-dashboard-uuid>", item_key: "<child-table-link-item-key>", root_index_value: "<parent-row-uuid>" } } })`
3. Response `data` is the child dashboard; `data.global_id` is the child dashboard ID. **View ID**: Prefer `response.default_view_id` for the child view (it is always set when a default view exists). Fallback to `data.views?.[0]?.global_id` — `data.views` can sometimes be empty in the response even when a default view exists. Use: `childViewId = response.default_view_id ?? data.views?.[0]?.global_id`.
4. Response `created` is true if a new dashboard was created, false if the cell already had a child.

### Read parent data (including child-table-link column)
1. `tool_call({ opId: "getDashboardViewData", args: { dashboardId: "<parent-id>", viewId: "<view-id>" } })`
2. For each row, the child-table-link column value is `{ title, childTableId, childTableViewId }`. If childTableId is set, use it to load child data.

### Read child table data
1. Get childTableId from parent row cell (see above) or from a previous getChildTableLinkDashboard response.
2. `tool_call({ opId: "getDashboardViewData", args: { dashboardId: "<childTableId>", viewId: "<view-id>" } })` (viewId can be childTableViewId from the cell).

## Rules of thumb

- Create parent dashboard and row first; then call getChildTableLinkDashboard to create the child for that cell.
- Deleting a parent row deletes all child dashboards that have that row as parent_row scope.
- To inspect request/response shape, use tools_describe for getChildTableLinkDashboard.

## Pitfalls

- **Wrong URL (404)**: Do NOT guess REST paths like POST /dashboards/<id>/child-table-link. That endpoint does not exist. The only valid way is the getChildTableLinkDashboard tool (path: POST /dashboards/get-child-table-link-dashboard, all parameters in the body: scope_type, scope_id, dashboard_id, item_key, root_index_value). Use the tool or SDK; do not construct URLs manually.
- **Hardcoded column keys (400 "Item not found in dashboard view")**: When writing/reading **child table** data, never hardcode column keys (e.g. from parent or from another child). Each child created from a template has its own unique schema item keys. Resolve keys from the **child dashboard's** schema (e.g. by column name: `schema.items.find(item => item.name === "Title").key`) and use those keys in batchPutDashboardData / getDashboardViewData.
- **Wrong item_key**: item_key must be the key of a schema item with customType "child-table-link" on the parent dashboard.
- **Wrong root_index_value**: Must be an existing row id in the parent (e.g. row UUID for custom dashboards).
- **Using child before creation**: If the cell has no childTableId, get dashboard data or call getChildTableLinkDashboard first to create the child.
- **Empty data.views**: The response can have `data.views = []` in some cases. Do not assume `data.views[0]` exists. Always prefer `response.default_view_id` for the child view id; fallback to `data.views?.[0]?.global_id`.

## Presenting structure (diagram)

When you create or describe a **database** that has dashboards with **child-table-link** columns, include **child tables in the structure diagram** (see domain.overview: "Presenting database structure"). Draw edges parent dashboard → child table (e.g. "has child" or "child-table-link").
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-03-06
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
