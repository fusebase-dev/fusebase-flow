---
name: fusebase-dashboards
description: "How to use MCP for working with FuseBase Project Dashboards during LLM development. Use when: 1. Discovering dashboards, views, and schema via MCP; 2. Reading or updating dashboard data; 3. Working with relations, filters, templates, and child tables; 4. Understanding dashboard/view structure before SDK runtime code; 5. Working with system managed databases — Companies, Deals, Meetings (CRM, pipeline, B2B accounts, seeding demo rows, alias-only discovery)."
metadata:
  source: entrypoint
---


# FuseBase Project Dashboards MCP Skill

This document describes how to use **MCP (Model Context Protocol)** for working with **FuseBase Project Dashboards** **during LLM development**. MCP is used for discovery and execution from the LLM; the **SDK** is used only in **runtime code** (feature/browser). See the Fusebase Dashboards SDK skill for SDK usage.

For rules and checklists, see `AGENTS.md`.

- **For runtime SDK code** that reads or writes dashboard data (`getDashboardViewData`, `batchPutDashboardData`, etc.), **`references/data-patterns.md` is required** — it defines the real response/request shapes; use it together with `sdk_describe` (do not infer `data.rows` vs top-level `data` from memory).
- **Default-path rule** — this skill is for existing dashboard surfaces and explicitly dashboard-oriented tasks. It is **not** the default storage-planning skill for new app-owned structured data. Do not ask the user to choose between PostgreSQL and a new dashboard/database unless the user explicitly requested dashboards or the project is extending an existing dashboard surface.

## References

Each reference is in a separate file under `references/`. Load the file when you need that topic.


**meta**

- [Authorization and Scopes](references/authz.md)
- [Bootstrap](references/bootstrap.md)
- [SDK Discovery](references/sdk.md)
- [Tooling](references/tooling.md)

**core**

- [Dashboard Data](references/data-patterns.md)
- [Dashboard Schema](references/schema-fundamentals.md)
- [Domain Overview](references/core-concepts.md)

**specialized**

- [Child Tables](references/child-tables.md)
- [Dashboard Relations](references/relations-guide.md)
- [Dashboard Rows](references/rows.md)
- [Dashboard View Filters](references/filters.md)
- [Dashboard View Representations](references/representations.md)

---


## Managed database routing (Companies, Deals, Meetings)

**System managed dashboards** (Companies, Deals, Meetings) are first-class product surfaces — same category as Workspaces, Portals, Clients. They live in **managed databases** with **fixed template aliases** (not org-specific UUIDs from URLs). Technically `rootEntity: custom`; do **not** treat them as arbitrary user-created custom tables.

When the user mentions any of the intents below, load the matching reference **before** domain tool calls (or use `prompts_search` with group `managedDatabases`):

| User intent (examples)                                           | Load reference / MCP prompt                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------- |
| clients (`root_entity: client`) — no dedicated managed-DB prompt | `references/core-concepts.md` + `references/relations-guide.md` |

**Alias-only discovery rule:** Never hardcode database/dashboard/view UUIDs. Resolve by stable aliases within org scope from bootstrap `defaults.toolArgs`:

| Entity    | Companies      | Deals                                                  |
| --------- | -------------- | ------------------------------------------------------ |
| Database  | `companies_db` | `deals_db`                                             |
| Dashboard | `companies`    | `deals_table` (not `deals`)                            |
| Views     | `companies`    | `deals_pipeline` (default Kanban), `deals_all` (table) |

Meetings DB alias: `meetings`; dashboards: `meetings`, `trackers`.

**Prompt load (Option B):** `prompts_search({ groups: ["managedDatabases", "data", "relations"] })` — add `"childTables"` for Meetings trackers/results.

### CRM demo data recipe (alias-only)

For requests like “seed demo companies and deals”, “fill CRM with sample data”:

1. **`bootstrap`** — read `defaults.toolArgs` (`scope_type`, `scope_id`).
2. **Domain knowledge** — load Companies + Deals references (or `prompts_search` above).
3. **`resolveAliases`** — one call with all aliases for `companies_db` / `companies` and `deals_db` / `deals_table` / `deals_pipeline` (see references for exact `items` shape).
4. **`getDashboardView`** — schema for each dashboard; resolve `item_key` by column **`alias`** (never hardcode keys).
5. **`batchPutDashboardData`** — create company rows (`company_name`, etc.), then deal rows (`deal_name`, `deal_stage`, `deal_value`, …). Use `generate_id` for new row UUIDs. `deal_stage` = `[label-nanoid]` from schema.
6. **`findRelationsByDashboardIds`** — `inversive_search: true` on deals dashboard id from step 3.
7. **`addRelationRows`** — link Companies → Deals (`source_index` = company `root_index_value`, `target_index` = deal `root_index_value`). Do **not** write lookup columns via `batchPutDashboardData`.

If a managed database is missing: use `getOrCreateDatabase` only when exposed in the session; otherwise report that the managed DB was not found.


## When NOT To Use This Skill

- Do not use this skill for multipart upload details, temp-file endpoints, stored-file endpoints, or display URL construction. Load `file-upload/references/upload-lifecycle.md` for the canonical lifecycle.
- Do not use this skill for Gate file operations, auth, or scopes. Load `fusebase-gate` for `startMultipartFileUpload`, `completeMultipartFileUpload`, and `deleteFile`.
- Do not copy shared upload API blocks into dashboard references. Dashboard guidance only explains how to put an already-uploaded file descriptor into a `files` column.


## Anti-Overlap Checklist

- [ ] Unique scope: dashboard schema, rows, views, relations, and dashboard data.
- [ ] Neighbor links: use `file-upload` for upload lifecycle; use `fusebase-gate` for Gate file operations.
- [ ] No duplicated upload endpoint or payload details in this skill.
- [ ] Only hand off the already-uploaded file descriptor to `batchPutDashboardData`.

---


## Mandatory: verify fusebase-dashboards MCP connection

**Before any work with dashboards**, the LLM **must** verify that the **fusebase-dashboards** MCP server is connected and available.

1. **Check** that MCP tools from the fusebase-dashboards server are present in your tool list (e.g. `tools_list`, `tools_search`, `tool_call`, `bootstrap`, `prompts_list`, `prompts_search`).
2. **If fusebase-dashboards is not available** (tools are missing or calls fail):
   - **Stop** and **inform the user** that the fusebase-dashboards MCP connection is required for working with dashboards.
   - **Suggest** that the user check their **connected MCP servers** in the IDE settings and ensure **fusebase-dashboards** is added and enabled.
   - For config (`.env`, MCP config files, `fusebase init`), see **AGENTS.md** or the `mcp/` directory.
   - Do not proceed with dashboard operations until the connection is available.

**MCP** is for development and dashboard access from the LLM. **SDK** is only for runtime code in the feature.

---


## MCP vs SDK (reminder)

- **MCP tools** (`tools_list`, `tools_search`, `tools_describe`, `tool_call`, `bootstrap`, `prompts_list`, `prompts_search`, etc.) — for performing actions **inside the LLM session**: discovery, schema inspection, and reading/writing dashboard data during development.
- **SDK methods** — for **runtime code** only (feature/browser). The LLM uses `sdk_search` / `sdk_describe` to generate code that the feature will execute; the LLM does not execute SDK.

Do not mix: use either the MCP chain (discovery → tool_call) for development, or the SDK chain (sdk_search → sdk_describe → insert code) for generating feature code. Each operation has the same `opId` in both MCP and SDK.

---


## Part I — Bootstrap and connection context

Right after session initialization, obtain the connection context: who is authenticated, which scopes/permissions apply, and what default arguments to use for tool calls.

### Preferred path (if the client supports MCP Resources)

1. Read the resource **`resource://connection/context`**.
2. From the response, use: `auth`, `defaults.toolArgs` (scope_type, scope_id), `usage`, `capabilities`.

### Alternative (tools only)

1. Call the **`bootstrap`** tool (no arguments).
2. In the response: `connectionContextUri`, `whoamiToolName`, `defaults`, `usage`, `pointers` (tool names for resources_list, resources_get, prompts_list, prompts_search).
3. If full JSON context is needed — call **`whoami`** (returns the same data as the connection/context resource).

### Defaults rule

- If a tool call requires `scope_type` and `scope_id` and the LLM did not provide them — use values from **`defaults.toolArgs`** in the connection context.
- Explicitly passed arguments always take precedence over defaults.
- For database/dashboard operations, org scope is used by default: `scope_type: "org"`, `scope_id` from context.

---


## Part II — Tooling flow (when connection exists)

After the connection is established (session ID set, connection context loaded): have domain knowledge (prompts or skill in context), discover operations, get schemas, execute via `tool_call`.

### II.1 Domain knowledge before domain tool calls

You must have the required domain knowledge (database, dashboard, view, relations, rows, data, etc.) **before any domain tool calls**. Two options:

**Option A — Skill in context (when the project has this skill):**

- If the project has the **fusebase-dashboards** skill (this document and `references/*.md`, generated from MCP prompts), **ensure that skill is in this chat's context**.
- Then you do **not** need to load prompts via MCP.

**Option B — Load prompts via MCP:**

- **Always** use a group filter when loading prompts.
- **Never** call `prompts_search({})` or omit the `groups` parameter.
- Call **`prompts_search`** with **`groups`**: e.g. `prompts_search({ groups: ["data", "rows", "schema"] })` for default dashboard work; add `"managedDatabases"` for Companies/Deals/Meetings/CRM tasks; add `"dashboard"`, `"filters"`, `"templates"`, `"relations"`, `"childTables"` when needed (see table below).
- **CRM / managed DB example:** `prompts_search({ groups: ["managedDatabases", "data", "relations"] })` before working with Companies, Deals, or seeding pipeline data.
- If the result is too large, request **one group at a time** (e.g. `["schema"]` then `["dashboard"]`).

**Invariant:** Do not call domain operations until you have this knowledge (from the skill in context or from prompts).

**Prompt groups (summary):**

| Group            | Purpose                                                               |
| ---------------- | --------------------------------------------------------------------- |
| tooling          | Discovery and execution (tools.list → describe → call)                |
| authz            | Permissions, scopes, ID formats                                       |
| bootstrap        | Connection context and defaults                                       |
| database         | Database entities and operations                                      |
| dashboard        | Dashboards, types, root_entity                                        |
| view             | Views (dashboard projections)                                         |
| schema           | Dashboard schema and columns                                          |
| relations        | one_to_many, many_to_many relations                                   |
| filters          | View filters                                                          |
| representations  | Cell display                                                          |
| rows             | Rows (custom rows)                                                    |
| data             | Reading/writing cell data                                             |
| templates        | Templates and creating from templates                                 |
| childTables      | Child-table-link columns, get-or-create child dashboard               |
| managedDatabases | System managed DBs: Companies, Deals, Meetings (alias-only discovery) |

### II.1a Prompts and skills (version check)

The MCP server is the **source of truth** for prompt content. The skill folder `fusebase-dashboards` (e.g. in `.claude/skills/` or `generated/claude_skills/`) contains the entrypoint and versioned reference files for IDE/agent loading.

**Version check without loading full prompt bodies:**

1. **Get versions** — Call **`prompts_list`** once. It returns for each prompt: `name`, `title`, `description`, `groups`, and **`version`** (semver). No message bodies; lightweight.
2. **Compare with skills** — Each skill's frontmatter has `mcp_prompt` (e.g. `domain.childTables`) and `last_synced` (date). Match by `mcp_prompt` to the list entry; compare `version` or regeneration date to see if the skill is up to date.
3. **When to load the prompt** — Use **`prompts_search`** (or native get_prompt) only when you need the actual content (e.g. by `groups` or by name). If operations fail or the skill is stale, the **VERSION CHECK** block in that skill's SKILL.md says: load MCP prompt `{mcp_prompt}` for latest content.

**Rule:** Use `prompts_list` for version checks; use `prompts_search` only when you need prompt text.

**Why:** Version checks stay cheap: less data over the network (no full prompt bodies) and fewer tokens used. Load full prompt content only when you actually need it.

---

### II.2 Operation discovery

Operations cannot be guessed by name or REST path. Explicit discovery is required.

**Step 1 — catalog or search:**

- **`tools_list`** — full list of available operations (short descriptions, no full schemas).
- **`tools_search`** — search by keywords. Example:
  `tools_search({ queries: ["create", "database"] })` or
  `tools_search({ queries: ["getDashboardView", "view"] })`.

Use **the exact names returned by `tools_list` / `tools_search`**.

**Step 2 — operation schema:**

- Call **`tools_describe`** with the operation name (as in the list/search result):
  - `tools_describe({ name: "<op name>" })` — returns a compact input schema by default.
  - For **data operations** (e.g. `batchPutDashboardData`) prefer:
    `tools_describe({ name: "batchPutDashboardData", schemaMode: "summary" })` — faster and sufficient for most cases.
  - `schemaMode`: `"input"` (default), `"output"`, `"both"`, `"summary"`, `"full"`. Use `"full"` only when needed (large payload).

Response includes: `inputSchema`, `outputSchema`, `schemaVersion`, `requiredPrompts` (groups/names), and **`promptsInvariant`** — reminder to have the required knowledge (from prompts or from this skill in context) before using the tool.

**Step 3 — execution:**

- All **domain (business) operations** must be executed **only via `tool_call`**.
- Direct invocation by tool name is allowed only for meta/built-in tools explicitly listed in the `tools_list` response (e.g. bootstrap, whoami, ping, tools_list, tools_search, tools_describe, tool_call, generate_id, prompts_list, prompts_search, resources_list, resources_get). Do not guess or call unknown operations by name — use **`tool_call`** only.

---

### II.3 Executing operations

**Universal way for domain operations:**

```json
tool_call({
  "opId": "<exact name from tools_list/tools_search>",
  "args": { ... }
})
```

Optional:

- **`schemaVersion`** — if provided and it does not match the server's current schema version, the server returns `SCHEMA_VERSION_MISMATCH`; then call `tools_describe` again and retry `tool_call` once with updated arguments.

**Response format** (for both tool_call and direct built-in calls):

- `ok: boolean`
- `opId: string`
- `data?: unknown` — on success
- `error?: { message, code?, issues? }` — on error

**Rules:**

1. By default always use **`tool_call`** to execute domain operations.
2. Direct calls only when the tool is registered (from `tools_list`) and is a meta/built-in tool.
3. Do not construct REST URLs from feature names; always rely on discovery (tools_list → tools_describe → tool_call) or the SDK.
4. When creating entities (dashboard, view, row, etc.) use **`generate_id`** when needed (format: `uuid` for global_id, `nanoid` for short keys/aliases).

---

### II.4 Working with schemas

- In the `tools_describe` response, schemas may contain **`$ref`** like `#/$defs/SomeName`.
- **`$defs`** live in the same schema object (inputSchema or outputSchema) where the `$ref` is used.
- Resolve `$ref` by looking up the key in **`$defs`** of that same schema. Do not use external or absolute `$ref` values.
- For data operations prefer `schemaMode: "summary"`; if validation fails, request a more complete schema (`input` or `full`) if needed.

---

### II.5 Error handling and retry

- **TOOL_NOT_FOUND** — operation is not in the allowed list; do not retry the same opId.
- **SCHEMA_VERSION_MISMATCH** — refresh the schema via `tools_describe` once and retry `tool_call` with correct arguments.
- **INVALID_ARGS** — response may include `issues` (validation details). Fix arguments per schema and retry.
- **EXECUTION_FAILED** — error on the API side; message in `error.message`. Do not retry automatically without changing the request.
- Authorization errors (access outside the token's scope) — do not retry; explain the access limitation to the user.

---

### II.6 MCP vs SDK (in flow)

- **MCP tools** — for performing actions **inside the LLM session** (discovery, tool_call for dashboards/data).
- **SDK methods** — for **application/runtime code** only. Use `sdk_search` / `sdk_describe` when you need to **generate** code for the feature; same `opId` and input schema as the MCP tool.

Do not mix in one scenario: either the MCP chain (discovery → tool_call) or the SDK chain (sdk_search → sdk_describe → code generation).

---

### II.7 Flow diagram summary

Tooling flow **after** the connection is established:

```
                    ┌──────────────────────────────────────────────────────────┐
                    │              LLM / MCP Client (session ready)             │
                    └──────────────────────────────────────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │ 1. Bootstrap (if not done in Part I)               │
                    │    • resource://connection/context  OR             │
                    │    • bootstrap()  → then whoami if needed           │
                    │    • Remember defaults.toolArgs (scope_type, id)    │
                    └─────────────────────────┬───────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │ 2. Have domain knowledge (before domain calls)       │
                    │    prompts_search({ groups: [...] }) OR skill in ctx  │
                    └─────────────────────────┬───────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │ 3. Discovery                                        │
                    │    tools_search(queries: [...])  or tools_list()    │
                    │    → pick op by name from response                  │
                    └─────────────────────────┬───────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │ 4. Operation schema                                 │
                    │    tools_describe({ name: "<op>", schemaMode? })    │
                    │    • data ops: schemaMode: "summary"               │
                    │    • Resolve $ref from $defs in same schema        │
                    │    • Honor requiredPrompts / promptsInvariant       │
                    │      (knowledge from prompts or skill in context)    │
                    └─────────────────────────┬───────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │ 5. Execution                                       │
                    │    tool_call({ opId: "<name>", args: {...} })       │
                    │    • scope_type/scope_id from defaults when needed │
                    │    • On SCHEMA_VERSION_MISMATCH: describe + retry   │
                    └─────────────────────────┬───────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │ 6. Handle response                                 │
                    │    ok ? data : error (message, code, issues)      │
                    └───────────────────────────────────────────────────┘
```

**Short checklist (Part II, connection already exists):**

1. Get context if needed (resource connection/context or bootstrap + whoami).
2. Have domain knowledge: load prompts (with groups) or ensure fusebase-dashboards skill is in chat context.
3. Find operations via tools_search or tools_list.
4. For each operation used — tools_describe (use summary for data ops).
5. Execute domain operations only via tool_call.
6. Handle errors by code (including schema version mismatch with one retry after describe).

---


## Summary

- **MCP = LLM development**: used for discovery and dashboard access from the LLM; configure fusebase-dashboards in your IDE and verify connection before use.
- **SDK = runtime only**: used only in feature code; see the Fusebase Dashboards SDK skill.
- **Connection check**: Always verify fusebase-dashboards MCP is connected; if not, ask the user to check connected MCP servers.
- **Flow**: Bootstrap/context → have domain knowledge (prompts or skill in context) → tools_search/tools_list → tools_describe → tool_call → handle response.
- **Managed DB / CRM**: Route by user intent (Companies / Deals / Meetings references) → `prompts_search({ groups: ["managedDatabases", ...] })` → alias-only `resolveAliases` → data ops. See **Managed database routing** above.
