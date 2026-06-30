---
version: "1.1.0"
mcp_prompt: domain.filters
last_synced: "2026-04-17"
title: "Dashboard View Filters"
category: specialized
---
# Dashboard View Filters

> **MARKER**: `dashboards-filters-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.filters` for latest content.

---
## Table of contents

- [Concepts](#concepts)
  - [Filter Structure](#filter-structure)
  - [Filter Layers](#filter-layers)
  - [Filter Object Schema](#filter-object-schema)
  - [Filter Condition](#filter-condition)
  - [Supported Operators](#supported-operators)
- [Rules of Thumb](#rules-of-thumb)
- [Common Workflows](#common-workflows)
  - [1. Read Current View Filters](#1-read-current-view-filters)
  - [2. Update Optional Filters](#2-update-optional-filters)
  - [3. Apply Multiple Conditions](#3-apply-multiple-conditions)
  - [4. Use Array Filters](#4-use-array-filters)
  - [5. Portal-Scoped Data (`{{CurrentPortal}}`)](#5-portal-scoped-data-currentportal)
- [Notes](#notes)

---
# Dashboard View Filters

## Concepts

### Filter Structure
View filters are composed of **required** and **optional** sections:
- **Required filters**: Cannot be removed or overridden by users; always applied to queries. **Important!** Never add any filters to the `required` section, since they will be ignored.
- **Optional filters**: Can be adjusted, added, or removed by users

### Filter Layers
Filters are inherited and merged from multiple layers:
1. `template.filters` (base layer)
2. `dashboard.filters` (dashboard overrides)
3. `view.filters` (view overrides, highest priority)

**Final filters** = merged required + merged optional

### Filter Object Schema
**Exact field names** (API and MCP use the same format): use `logic`, `key`, `operator` — **not** `op`, `item_key`, or `eq`. Wrong names return 400.
```typescript
{
  required: { filters: { logic: "AND" | "OR", conditions: [...] } },
  optional: { filters: { logic: "AND" | "OR", conditions: [...] } }
}
```
`logic` must be `"AND"` or `"OR"` (uppercase; lowercase is accepted and normalized).

### Filter Condition
Each condition has (use these exact names):
- `key`: Schema item **key** from `schema.items[].key` (the column identifier). **Not** `item_key`.
- `operator`: Comparison operator (see below). **Not** `op`. For equality use `"is"`, not `"eq"`.
- `value`: Value(s) to compare against (not needed for `empty`/`not_empty`)
- `payload`: Optional metadata (e.g., time zone, date range)

### Supported Operators
**Exact match:**
- `is`, `is_not`

**Text matching:**
- `contains`, `contains_not`, `starts_with`, `ends_with`

**Existence:**
- `empty`, `not_empty`

**Array matching:**
- `has_any_of`, `has_none_of`

**Numeric comparison:**
- `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal`

## Rules of Thumb

1. **Required filters are immutable at runtime**: Users cannot change or remove them via UI.
2. **Filter logic**: Each filter section has `logic: 'AND' | 'OR'` (uppercase) controlling how conditions are combined.
3. **Empty operators**: `empty` and `not_empty` do not require a `value` field.
4. **Array operators**: `has_any_of` and `has_none_of` expect an array of values.
5. **Field keys**: Use the schema item **key** (`schema.items[].key`), not the display name or raw field name. Get available keys from the dashboard/view schema.

## Common Workflows

### 1. Read Current View Filters
To see existing filters, fetch the view:
```
tools_search(queries: ["get view", "fetch view"])
tools_describe(name: "<found tool name>")
tool_call({ opId: "<exact name>", args: { dashboardId, viewId } })
```

### 2. Update Optional Filters
To add or modify optional filters:
```
tools_search(queries: ["update view filters"])
tools_describe(name: "<found tool name>")
tool_call({
  opId: "<exact name>",
  args: {
    dashboardId,
    viewId,
    filters: {
      optional: {
        filters: { logic: "AND", conditions: [{ key: "status", operator: "is", value: "active" }] }
      }
    }
  }
})
```

### 3. Apply Multiple Conditions
Combine conditions with AND or OR logic:
```typescript
{
  logic: "AND",
  conditions: [
    { key: "status", operator: "is", value: "active" },
    { key: "priority", operator: "greater_than", value: 3 }
  ]
}
```

### 4. Use Array Filters
Filter by multiple values:
```typescript
{  key: "tags", operator: "has_any_of", value: ["urgent", "bug", "feature"] }
```

### 5. Portal-Scoped Data (`{{CurrentPortal}}`)
`{{CurrentPortal}}` is a special dynamic value that is resolved automatically in each request for data.
Use it when a feature must display different information depending on the portal it is embedded in. This way, the feature will only "see" data for the current portal.
The filtered column must be either a text column with a portal ID, or, ideally, a relation to the portals dashboard.
```typescript
{
  optional: {
    filters: {
      logic: "AND",
      conditions: [
        { key: "portalId", operator: "is", value: "{{CurrentPortal}}" }
      ]
    }
  }
}
```

## Notes

- **Do not hardcode filter field names**—get dashboard schema via `getDashboard` to see available item keys.
- **Filter merging**: When updating, provide only changed sections; existing filters remain unless explicitly overridden.
- **Time zones**: For date filters with `payload.timeZone`, the system applies timezone conversion automatically.
- **Validation**: Invalid or unknown field names (e.g. op, item_key, eq) return **400** with a clear message. Use exactly: logic, key, operator. Inspect schema via getDashboard for available item keys.
---

## Version

- **Version**: 1.1.0
- **Category**: specialized
- **Last synced**: 2026-04-17
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
