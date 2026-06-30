---
version: "1.0.0"
mcp_prompt: tooling
last_synced: "2026-02-13"
title: "Tooling"
category: meta
---
# Tooling

> **MARKER**: `mcp-tooling-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `tooling` for latest content.

---
## Tool Discovery and Execution Flow

**Tool names**: Meta-tool names may appear with underscores (e.g. `tools_list`, `tools_describe`, `tool_call`) if the client sanitizes names. Use the exact names returned by `tools.list`.

1. **Discover available operations**: Call `tools.list` (or `tools_list`) to get a lightweight catalog of all operations you are allowed to execute.
   - Each entry includes: name, title, description, input/output hints, and schemaVersion.
   - Note: `tools.list` shows ALL allowed operations, but not all of them are registered as directly callable tools.

2. **Get schema**: For any operation you want to use, call `tools.describe` (or `tools_describe`) with the operation name.
   - **For data operations** (e.g., `batchPutDashboardData`): **ALWAYS use `schemaMode: "summary"`** for 80% faster responses.
     - Example: `tools_describe({ name: "batchPutDashboardData", schemaMode: "summary" })`
     - Returns only top-level required/properties without nested schemas
     - Only use `schemaMode: "input"` or `"full"` if you encounter validation errors requiring deep schema understanding
   - **For other operations**: Returns complete JSON Schema (Draft-07) for both input and output.
   - Both `inputSchema` and `outputSchema` may include `$defs` at the root level.
   - Schemas may contain `$ref` references of the form `#/$defs/XYZ`.
   - You MUST resolve all `$ref` references using the `$defs` object in the same schema where the `$ref` appears.

3. **Execute operations**:
   - **Preferred path**: Use `tool.call` to execute operations. It can execute ANY allowed operation.
   - Use direct tool calls (calling the operation by name) ONLY if your MCP client explicitly knows the operation is registered as a direct tool.
   - If you are unsure whether a tool is registered, do NOT probe/try it — use `tool.call`.

## Schema Resolution Rules

When processing schemas from `tools.describe`:
- `$defs` are included inline within `inputSchema.$defs` and `outputSchema.$defs`.
- All `$ref` values are local references: `#/$defs/XYZ` where `XYZ` is a key in the same schema's `$defs` object.
- To resolve a `$ref`: look up the key in the `$defs` object of the same schema (inputSchema or outputSchema).
- If `$defs` are duplicated in both schemas, treat them as equivalent; still resolve `$ref` within the same schema for simplicity.
- Do NOT attempt to resolve external or absolute `$ref` values.

## Execution Strategy

**Rule 1**: Default to `tool.call` for executing operations.

**Rule 2**: Only use direct tool calls if your client explicitly knows the tool is registered (no guessing, no probing).

**Rule 3**: If a call fails due to schema mismatch (schemaVersion), refresh schema and retry once.

**Rule 4**: Never construct API URLs manually from feature or concept names (e.g. "child-table-link" → /dashboards/.../child-table-link). Real paths may differ (e.g. POST /dashboards/get-child-table-link-dashboard). Always use tools.list → tools.describe → tool.call, or the SDK, to get the correct path and parameters.

**Rule 5 — No direct operation / workarounds**: If you do not see a tool that directly matches the user's requested operation, but you can think of a workaround (e.g. there is no "move dashboard from one database to another", but one could copy the dashboard to the target database and then delete it from the source), **inform the user** and **suggest** the workaround. **Do not execute the workaround automatically.** Let the user decide whether to proceed and confirm the steps (e.g. "There is no single move operation; you could copy the dashboard to the other database and then delete it from the source. Should I do that?" or "I can do A then B as a workaround — confirm if you want me to proceed.").

**tool.call parameters**:
- `opId` (required): The operation name from `tools.list`.
- `args` (optional, default: {}): The operation arguments object, validated against the schema from `tools.describe`.
- `schemaVersion` (optional): A stable hash of the input+output schemas. If provided and mismatched, re-fetch schema via `tools.describe` and retry once.

**Response format** (same for direct calls and `tool.call`):
- `ok: boolean` - true on success, false on error.
- `opId: string` - The operation that was executed.
- `data?: unknown` - The operation result (present when `ok: true`).
- `error?: { message: string, code?: string, issues?: unknown }` - Error details (present when `ok: false`).

## Schema Versioning

- `schemaVersion` is a stable hash computed from the input and output schemas.
- You can cache schemas and use `schemaVersion` to detect when they change.
- On `schemaVersion` mismatch: call `tools.describe` again to get the updated schema, then retry the same `tool.call` once using the new schemaVersion.
- `schemaVersion` is optional, but useful for reducing unnecessary schema re-fetching.

## Dashboard Schema Caching

**For `describeDashboard` operations, implement conversation-scoped caching**:

1. **Before calling `describeDashboard`**:
   - Check conversation cache: "Have I already fetched schema for dashboardId X with version Y in this conversation?"
   - Cache key: `${dashboardId}:${schemaVersion}`
   - If cached version exists and matches, reuse it

2. **After calling `describeDashboard`**:
   - Store result with key: `${dashboardId}:${schema.metadata.version || schemaVersion}`
   - Cache expires at conversation scope only (not persisted across conversations)

3. **Benefits**:
   - Reduces redundant API calls when working with the same dashboard multiple times
   - Faster response times for repeated schema lookups

---

## Version

- **Version**: 1.0.0
- **Category**: meta
- **Last synced**: 2026-02-13
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
