---
version: "1.1.0"
mcp_prompt: bootstrap
last_synced: "2026-03-16"
title: "Bootstrap"
category: meta
---
# Bootstrap

> **MARKER**: `mcp-bootstrap-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `bootstrap` for latest content.

---
You are connecting to a Model Context Protocol (MCP) server for Fusebase Platform (shared runtime: tokens, health, authz, and consumer-defined operations).

## Initial Setup

1. Load the connection context by reading the resource: resource://connection/context
   - If your client does not support resources, call the whoami tool instead.
   - The connection context contains:
     - Server capabilities and version
     - Your authentication context (user ID, org ID, scopes, permissions)
     - Default tool arguments (scope_type, scope_id)
     - Usage instructions

## Defaults Rule

If a tool call requires `scope_type` and `scope_id` and you did not provide them:
- Use the values from `defaults.toolArgs` in the connection context.
- If you provide these arguments explicitly, they always take precedence over defaults.

## Important Notes

- The organization scope (`scope_type = "org"`) is the default and most common scope.
- Use the organization `scope_id` from the connection context when a tool requires scope arguments and no other scope is specified.

- Treat all `scope_id` values as opaque strings.
  Do not validate, transform, or infer meaning from their format.

- IDs for internal resources (e.g. tokens, orgs) are UUID strings and must be passed exactly as returned by tools or responses.

- Tool availability already reflects your permissions.
  If a tool is not available, you are not allowed to use it.

## Context before tool calls

You must have the required context before calling platform operations. Two options:

1. **Prompts** — Load via `prompts_search` with a groups filter:
   - Use groups relevant to the operation (e.g. `prompts_search({ groups: ["authz", "bootstrap", "tooling"] })`).
   - **NEVER** use `prompts_search({})` or omit `groups` when the tool's requiredPrompts suggest groups.

2. **Skill in context** — If the project has the fusebase-gate skill (generated from these prompts), ensure that skill is in this chat's context; then you do not need to load prompts.

Do not call operations until you have the required context (from prompts or from the skill).

## MCP Tools vs SDK Methods

This server provides **two parallel execution surfaces** for the same operations:

1. **MCP Tools** (`tools_list`, `tools_search`, `tools_describe`) - For MCP execution
2. **SDK Methods** (`sdk_list`, `sdk_search`, `sdk_describe`) - For direct HTTP API usage via SDK

**DECISION RULE**:
- Use **MCP tools** when you are executing actions inside an MCP session.
- Use **SDK methods** when generating or reasoning about application code, tests, or integrations.
- Never mix MCP tool calls and SDK calls in the same execution path.

**Key facts**:
- MCP tools and SDK methods are mirrors of the same operations.
- Every MCP tool has a corresponding SDK method with the same `op.id`.
- Input schemas are identical between MCP tools and SDK methods.
- SDK may expose more operations than MCP (MCP is a subset).

**To explore available SDK APIs**:
1. Use `sdk_search` to find relevant methods by keywords.
2. Use `sdk_describe` to inspect schemas and HTTP details.
3. Use the SDK usage hints to generate code.

Proceed by loading the connection context first, then discover available tools.
---

## Version

- **Version**: 1.1.0
- **Category**: meta
- **Last synced**: 2026-03-16
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
