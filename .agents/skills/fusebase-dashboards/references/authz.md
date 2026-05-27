---
version: "1.0.0"
mcp_prompt: authz
last_synced: "2026-02-13"
title: "Authorization and Scopes"
category: meta
---
# Authorization and Scopes

> **MARKER**: `mcp-authz-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `authz` for latest content.

---
## Authorization and Scopes\n\nThis connection is already authorized using the provided token.\nAvailable tools are pre-filtered based on your permissions.\n\nYou do NOT need to manually check permissions before calling tools.\n\n## Scopes in Tool Arguments\n\nMany tools require `scope_type` and `scope_id` arguments.\n\n- For **databases, dashboards\n  the required scope is **organization scope**:\n  - `scope_type = "org"`\n  - `scope_id` is provided by the connection context\n\nIf a tool requires `scope_type` and `scope_id` and you do not see other instructions:\n- Use the organization scope from the connection context.\n\nOther scope types (e.g. `database`, `block`, `parent_row`, etc.)\nare tool-specific and are described in each tool's schema when applicable.\n\n## Resource Access Enforcement\n\nIn addition to argument scopes, access is restricted by the token's resource scope.\n\n- The token may restrict access by resource ID or alias pattern.\n- These restrictions are enforced server-side.\n\nIf a tool call targets a resource outside the token's allowed resource scope:\n- The server will return an authorization error.\n- Do NOT retry the same call.\n- Explain to the user that access to the requested resource is not allowed.\n\n## ID Formats\n\n- `scope_id` for organization scope is an opaque string.\n  Treat it as-is and do not validate or modify it.\n\n- IDs for databases, dashboards, views, rows, and similar internal resources\n  are **UUID strings** and must be passed exactly as provided by tools or responses.\n\n## Best Practices\n\n- Rely on the tool list provided by the server; unavailable tools mean insufficient permission.\n- Prefer organization scope when required and not otherwise specified.\n- Do not guess or fabricate resource IDs.\n- If an operation is not allowed, explain the limitation clearly to the user.
---

## Version

- **Version**: 1.0.0
- **Category**: meta
- **Last synced**: 2026-02-13
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
