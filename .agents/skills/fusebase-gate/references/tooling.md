---
version: "1.1.0"
mcp_prompt: tooling
last_synced: "2026-03-24"
title: "Tooling"
category: meta
---
# Tooling

> **MARKER**: `mcp-tooling-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `tooling` for latest content.

---
## Tool Discovery and Execution Flow

Tool names may appear with underscores if the client sanitizes names. Use the exact names returned by tools.list.

1. Discover available operations: call tools.list or tools_list to get a lightweight catalog of all operations you are allowed to execute.
   - Each entry includes name, title, description, input and output hints, and schemaVersion.
   - tools.list shows all allowed operations, but not all of them are registered as directly callable tools.

2. Get schema: for any operation you want to use, call tools.describe or tools_describe with the operation name.
   - For large or complex operations, prefer schemaMode summary first for faster responses.
   - Use schemaMode input or full only when you need deeper validation details.
   - Both inputSchema and outputSchema may include $defs at the root level.
   - Schemas may contain $ref references of the form #/$defs/XYZ.
   - Resolve $ref references using the $defs object from the same schema where the $ref appears.

3. Execute operations:
   - Preferred path: use tool.call. It can execute any allowed operation.
   - Use direct tool calls only if your MCP client explicitly knows the operation is registered as a direct tool.
   - If you are unsure whether a tool is registered, do not probe or guess. Use tool.call.

## Schema Resolution Rules

When processing schemas from tools.describe:
- $defs are included inline within inputSchema.$defs and outputSchema.$defs.
- All $ref values are local references where the key must exist in the same schema $defs object.
- Resolve a $ref only against the $defs of the same schema, input or output.
- Do not attempt to resolve external or absolute $ref values.

## Execution Strategy

Rule 1: default to tool.call for executing operations.

Rule 2: only use direct tool calls if your client explicitly knows the tool is registered. No guessing and no probing.

Rule 3: if a call fails due to schema mismatch, refresh schema and retry once.

Rule 4: never construct API URLs manually from feature or concept names. Always use tools.list, tools.describe, and tool.call, or the SDK, to get the correct path and parameters.

Rule 5: if there is no exact operation for the requested action, explain the available workaround and ask for confirmation before executing a multi step substitute flow.

tool.call parameters:
- opId is the operation name from tools.list.
- args is the operation arguments object validated against the schema from tools.describe.
- schemaVersion is optional. If provided and mismatched, re fetch schema via tools.describe and retry once.

Response format for direct calls and tool.call:
- ok boolean indicates success.
- opId is the executed operation.
- data is present on success.
- error may include message, code, and issues.

## Schema Versioning

- schemaVersion is a stable hash computed from the input and output schemas.
- You can cache schemas and use schemaVersion to detect changes.
- On schemaVersion mismatch, call tools.describe again and retry once with the new version.
- schemaVersion is optional but useful for reducing unnecessary schema re fetching.
---

## Version

- **Version**: 1.1.0
- **Category**: meta
- **Last synced**: 2026-03-24
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
