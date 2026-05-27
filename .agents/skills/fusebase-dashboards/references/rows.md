---
version: "1.2.0"
mcp_prompt: domain.rows
last_synced: "2026-04-02"
title: "Dashboard Rows"
category: specialized
---
# Dashboard Rows

> **MARKER**: `dashboards-rows-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.rows` for latest content.

---
## Custom Dashboard Rows

Custom dashboards (`rootEntity === 'custom'`) support custom row entries with persistent sorting and ordering.

### Row Operations

**When to use which operation**:
- **Creating rows** (with or without data): Use **batchPutDashboardData** with `create_new_row: true`. Pass `values: []` for an empty row, or include values to create and fill in one call. This is the preferred method for all row creation.
- **createDashboardRow** is **deprecated**. Use batchPutDashboardData with `create_new_row: true` and `values: []` for empty rows instead.

**Main Operations**:
- **Create rows**: Add new custom rows to a dashboard
  - Use `batchPutDashboardData` with `create_new_row: true`. Use `values: []` for empty row, or pass values to create and fill. `root_index_value` is optional (auto-generated if omitted).
  - **createDashboardRow** is deprecated and kept for backward compatibility only.
  - New rows are automatically added to all existing views, sections, and items.

**IMPORTANT**: Use **batchPutDashboardData** with `create_new_row: true` for all row creation (empty or with data). Do not use createDashboardRow for new code.
- **Row ID verification**: If you only need row UUIDs, `listDashboardRows` is the lightest row-listing operation. For critical live-data verification, prefer a stable read path and avoid depending on paginated row listing unless pagination behavior has already been validated in that environment.

- **Delete rows**: Remove rows from a dashboard (soft delete)
  - Use `deleteDashboardRow` operation
  - Requires `dashboard.write` permission
  - Also deletes child dashboards with `parent_row` scope

**Sorting Operations**:
- **Update row order**: Manually reorder rows for a view, section, or item
  - Use `updateDashboardRowOrder` operation
  - Requires `view.write` permission
  - Requires `view_id`, `section_type`, and `section_key` query parameters
  - Implements lazy loading - creates default orders if none exist

- **Initialize row order** / **Save row order**: Not exposed in MCP. Use SDK or REST if you need to initialize or persist row order.

### Row Ordering Concepts

- **Dynamic sorting**: Users can sort by any field using view filters
- **Saved order**: Persisting sort order is not available in MCP (use SDK/REST if needed).
- **Manual ordering**: Rows can be manually reordered via `updateDashboardRowOrder`
- **View order**: Apply saved order by sorting with `by: 'viewOrder'`

### Section Types

Row ordering operations support three section types:
- **view**: Order applies to entire view (`section_key='view'`, `section_value=view_id`)
- **section**: Order applies to a specific section (`section_key='section'`, `section_value=section_uuid`)
- **item**: Order applies to a specific item (`section_key='item_key'`, `section_value=normalized_value`)

### Important Constraints

- Rows operations are **only available for custom dashboards** (`rootEntity === 'custom'`)
- Row UUIDs must be unique within a dashboard
- Row orders are cached in Redis for performance
- When deleting a row, child dashboards with `parent_row` scope are also deleted

### Usage Flow

**For creating rows** (with or without data):
- Use `batchPutDashboardData` with `create_new_row: true` and either `values: []` (empty row) or `values: [{ item_key, value }, ...]` (create and fill)
- Do not use createDashboardRow (deprecated)

**For row management only** (empty rows, legacy):
1. Create empty rows: `batchPutDashboardData` with `create_new_row: true`, `root_index_value` (optional), `values: []`
2. (Optional) Update order: `updateDashboardRowOrder({ dashboardId, view_id, section_type, section_key, rowOrders: [...] })`
3. Delete rows: `deleteDashboardRow({ dashboardId, rowUuid })`

**Verification guidance**:
- Use `listDashboardRows` when you only need row UUIDs and row existence.
- Use `getDashboardViewData` when verification needs counts plus actual written values, or when the verification path must be as robust as possible for live/demo data.

---

## Version

- **Version**: 1.2.0
- **Category**: specialized
- **Last synced**: 2026-04-02
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
