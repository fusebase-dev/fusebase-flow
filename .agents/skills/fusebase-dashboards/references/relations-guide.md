---
version: "1.2.1"
mcp_prompt: domain.relations
last_synced: "2026-04-17"
title: "Dashboard Relations"
category: specialized
---
# Dashboard Relations

> **MARKER**: `dashboards-relations-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.relations` for latest content.

---
## Table of contents

- [Concepts](#concepts)
- [1. Creating a relation between tables](#1-creating-a-relation-between-tables)
- [2. Direction: source vs target](#2-direction-source-vs-target)
- [3. Creating columns: relation vs lookup](#3-creating-columns-relation-vs-lookup)
- [4. Creating relation rows (linking rows)](#4-creating-relation-rows-linking-rows)
- [5. Relation types](#5-relation-types)
- [MCP Operations (use with tool_call)](#mcp-operations-use-with-toolcall)
- [Typical workflows (via tool_call)](#typical-workflows-via-toolcall)
  - [List relations for a dashboard](#list-relations-for-a-dashboard)
  - [Create a relation and add row mappings](#create-a-relation-and-add-row-mappings)
  - [Get one relation and its row mappings](#get-one-relation-and-its-row-mappings)
  - [Replace or remove row mappings](#replace-or-remove-row-mappings)
  - [Delete a relation](#delete-a-relation)
  - [Full flow: relation + columns + rows](#full-flow-relation--columns--rows)
- [Rules of thumb](#rules-of-thumb)
- [Validation (400) when adding or updating lookup columns](#validation-400-when-adding-or-updating-lookup-columns)
- [Pitfalls](#pitfalls)
- [Presenting structure (diagram)](#presenting-structure-diagram)

---
## Concepts

Relations link two dashboards and enable lookup/relation columns. **Execute all relation operations via** `tool_call({ opId: "<opId>", args: { ... } })`.

---
## 1. Creating a relation between tables

Use **createDashboardRelation** with the correct **direction** (see section 2).

Steps:
1. Decide which dashboard is **source** (data is fetched from) and which is **target** (view where columns live).
2. `tool_call({ opId: "createDashboardRelation", args: { body: { source_dashboard_id: "<source-uuid>", target_dashboard_id: "<target-uuid>", relation_type: "one_to_many" } } })`.
3. From the response take `data.global_id` (relation ID) for use in columns and relation rows.

---
## 2. Direction: source vs target

The backend **always fetches lookup data from the SOURCE dashboard**. Wrong direction causes "Dashboard view not found".

| Concept | Meaning | Example (Authors view shows Book title/year) |
|--------|--------|---------------------------------------------|
| **source_dashboard_id** | Dashboard you **fetch data FROM** (table whose columns you display) | **Books** |
| **target_dashboard_id** | Dashboard you are **ON** (view where relation/lookup columns live) | **Authors** |
| **source_index** (relation rows) | Row ID in the **source** dashboard | Book row UUID |
| **target_index** (relation rows) | Row ID in the **target** dashboard | Author row UUID |

Rule: **For lookup columns on dashboard B showing data from dashboard A**, create relation with `source_dashboard_id = A`, `target_dashboard_id = B`.

---
## 3. Creating columns: relation vs lookup

Both use `type: "lookup"` in the schema. Difference is **editable vs read-only**:

- **Relation column** (editable): User can add/remove linked rows in the UI. Schema: `selectable: true`, `readonly: false`. Names often like "Books (Relation)".
- **Lookup column** (read-only): Column only displays data from related rows. Schema: `selectable: false`, `readonly: true`. Names often like "Book Title (Lookup)".

**Rule:** For a given `relation_id`, **exactly one** column is editable; all others using the same relation are read-only lookups.

**Overrides only for selected item types**: In MCP, use overrides only for **label** and **lookup/relation** columns. For lookup columns, relation binding must be in overrides.source; use overrides.render for render config when needed.

**Add via updateViewIntent** with `schema_patch.add`, `type: "lookup"`, and **required** `overrides.source`:
- **`_type_lookup: true`** (required for validation), `type: "lookup"`, `selectable`, `readonly`,
- `relations`: one object with `relation_id`, `dashboard_id` (source), `view_id` (source view), `item_key` (source column key), `reverse: false`, `relation_type`.
- Provide an explicit **`key`** for each column (e.g. `books-relation`, `book-title-lookup`) when adding multiple lookup columns.

Order: Add the **first editable relation column**, then optionally **read-only lookup columns** for the same relation (same relation_id, different item_key).

---
## 4. Creating relation rows (linking rows)

Relation rows define which source row links to which target row. Without them, lookup/relation cells stay empty.

Steps:
1. Get row IDs: **getDashboardViewData** for both dashboards; use `root_index_value` from each row.
2. For each link: **source_index** = row ID in **source** dashboard, **target_index** = row ID in **target** dashboard.
3. `tool_call({ opId: "addRelationRows", args: { relationId: "<id>", body: { rows: [{ source_index: "<source-row-uuid>", target_index: "<target-row-uuid>" }, ...] } } })`.

Example (Authors view, Books source): to show "Pride and Prejudice" and "Emma" for Jane Austen, add two rows with target_index = Jane's row UUID and source_index = each book's row UUID.

Update/delete: **updateRelationRows** (replace mappings for given target indices), **deleteRelationRows** (remove by source_index/target_index or all).

---
## 5. Relation types

- **one_to_one**: One source row ↔ one target row.
- **one_to_many**: One source row can link to many target rows; each target row links to one source (e.g. Author → Books).
- **many_to_many**: Many-to-many (e.g. Tags ↔ Content).

Row mappings always use (source_index, target_index) regardless of type.

---
## MCP Operations (use with tool_call)

| OpId | Purpose | Key args |
|------|--------|----------|
| **findRelationsByDashboardIds** | List relations for a dashboard | target_dashboard_id (required), source_dashboard_id, inversive_search, include_rows |
| **createDashboardRelation** | Create a relation between two dashboards | Body: source_dashboard_id, target_dashboard_id, relation_type |
| **getDashboardRelationById** | Get one relation and optionally its row mappings | relationId, include_rows (default true) |
| **addRelationRows** | Add row mappings to a relation (does not remove existing) | relationId, body.rows: [{ source_index, target_index }, ...] |
| **updateRelationRows** | Replace row mappings for given target indices | relationId, body.rows: [{ source_index, target_index }, ...] |
| **deleteRelationRows** | Remove row mappings | relationId, optional query: source_index, target_index (omit to delete all) |
| **deleteDashboardRelation** | Soft-delete relation and all its row mappings | relationId |

**Note**: There is no "update relation" (e.g. change relation_type) — only create, get, delete relation; row mappings are updated via add/update/delete relation rows.

## Typical workflows (via tool_call)

### List relations for a dashboard
1. `tool_call({ opId: "findRelationsByDashboardIds", args: { target_dashboard_id: "<dashboard-uuid>", include_rows: true } })`
2. Optionally pass `source_dashboard_id` to filter, or `inversive_search: true` to also match relations where this dashboard is the source.
3. Response `data[]` contains `global_id`, `source_dashboard_id`, `target_dashboard_id`, `relation_type`, and (if include_rows) `relation_rows`.

### Create a relation and add row mappings
1. Create: `tool_call({ opId: "createDashboardRelation", args: { body: { source_dashboard_id: "<uuid>", target_dashboard_id: "<uuid>", relation_type: "one_to_many" } } })`
2. From the response take `data.global_id` (relation ID).
3. Add mappings: `tool_call({ opId: "addRelationRows", args: { relationId: "<relation-id>", body: { rows: [{ source_index: "<source-row-uuid>", target_index: "<target-row-uuid>" }, ...] } } })`
4. Source/target row UUIDs come from the dashboards (e.g. `getDashboardViewData` → `root_index_value`, or rows created via `batchPutDashboardData` with `create_new_row: true`).

### Get one relation and its row mappings
1. `tool_call({ opId: "getDashboardRelationById", args: { relationId: "<relation-uuid>", include_rows: true } })`
2. Response `data.relation_rows` is the list of { source_index, target_index } mappings.

### Replace or remove row mappings
- **Replace** mappings for specific target rows: `tool_call({ opId: "updateRelationRows", args: { relationId: "<id>", body: { rows: [...] } } })` (replaces only the target indices present in `rows`; others unchanged).
- **Remove** some mappings: `tool_call({ opId: "deleteRelationRows", args: { relationId: "<id>", source_index: "<uuid>", target_index: "<uuid>" } })` or omit query params to remove all mappings for the relation.

### Delete a relation
1. `tool_call({ opId: "deleteDashboardRelation", args: { relationId: "<relation-uuid>" } })`
2. Soft-deletes the relation and all its row mappings.

### Full flow: relation + columns + rows
1. **createDashboardRelation** (correct direction: source = table you fetch from, target = view where columns live).
2. **addRelationRows** to link rows (source_index = source dashboard row, target_index = target dashboard row). Get IDs from getDashboardViewData → root_index_value.
3. **updateViewIntent** (schema_patch.add): add one **relation column** (selectable: true) with overrides.source including _type_lookup: true and relations[{ relation_id, dashboard_id, view_id, item_key, relation_type }]; use explicit key.
4. **updateViewIntent** (schema_patch.add): optionally add **lookup columns** (selectable: false) for the same relation_id, other item_key; explicit key for each.
5. **getDashboardViewData** returns relation/lookup cells filled from relation rows. If view was cached before adding columns, use cacheStrategy: "reset" once to re-index.

## Rules of thumb

- **Order**: Create relation → add relation rows → add relation column → add lookup columns.
- **Direction**: source = fetch from, target = view with columns. Relation rows: source_index = source row, target_index = target row.
- **Lookup source**: Always include `_type_lookup: true` in overrides.source; use explicit `key` when adding multiple lookup columns.
- Row IDs must be valid root index values (e.g. getDashboardViewData → root_index_value).
- Use `tools_describe` for exact parameter names and types.

## Validation (400) when adding or updating lookup columns

When you add (schema_patch.add) or **update** (schema_patch.update) a lookup/relation column via **updateViewIntent**, the backend validates: relation exists, correct direction (target = this dashboard), relations[0].dashboard_id = relation.source_dashboard_id, valid UUIDs for relation_id/dashboard_id/view_id, source view exists, item_key exists in source view. On failure you get **400** with a clear message:
- **Relation not found** — relation_id does not exist or was deleted; create the relation first with createDashboardRelation.
- **Relation direction is wrong** — target_dashboard_id of the relation is not this dashboard; create relation with source = dashboard you fetch from, target = this dashboard.
- **Lookup relation mismatch** — relations[0].dashboard_id must equal the relation's source_dashboard_id.
- **Invalid relation_id / dashboard_id / view_id** — value is not a valid UUID.
- **Source view not found** — view_id is not a view of the source dashboard; use getDashboardView on the source dashboard to get a valid view_id.
- **Source column not found** — item_key is not in the source view schema; use getDashboardView or describeDashboard on the source dashboard to get valid item_key values.
Fix the payload (or create the relation / add rows first) and retry.

## Pitfalls

- **Lookup config in wrong place**: Put `_type_lookup`, `selectable`, and `relations` in **overrides.source**, NOT in overrides.render. If you put them in overrides.render, the API returns INVALID_ARGS / invalid_union ("Unrecognized keys: _type_lookup, selectable, relations") because render is for display only (edit_type, is_lookup, type) and does not accept relation config. Same for putting relations/selectable on the top level of the add item — they are not allowed there; use overrides.source.
- **Wrong direction**: For lookup columns on dashboard B showing data from dashboard A, use source_dashboard_id=A, target_dashboard_id=B. Reversing source/target causes "Dashboard view not found" because the backend fetches from the source dashboard.
- **Circular relations**: Avoid A → B → A unless intentional.
- **Mismatched row IDs**: source_index and target_index must exist in their dashboards; use `getDashboardViewData` or row APIs to get valid IDs.
- **Lookup before relation**: Create the relation and mappings before adding lookup items that reference it.
- **No update-relation metadata**: You cannot change relation_type after creation; delete and recreate if needed.
- **Soft deletes**: Deleted relations are soft-deleted; they no longer appear in find/get.

## Presenting structure (diagram)

When you create or describe a **database** that has relations, include the **relations in the structure diagram** (see domain.overview: "Presenting database structure"). Draw edges source → target and label with relation_type (one_to_one, one_to_many, many_to_many).
---

## Version

- **Version**: 1.2.1
- **Category**: specialized
- **Last synced**: 2026-04-17
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
