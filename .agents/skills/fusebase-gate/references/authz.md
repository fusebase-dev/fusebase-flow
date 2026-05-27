---
version: "1.2.0"
mcp_prompt: authz
last_synced: "2026-05-22"
title: "Authorization and Scopes"
category: meta
---
# Authorization and Scopes

> **MARKER**: `mcp-authz-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `authz` for latest content.

---
## Authorization and Scopes

This connection is already authorized using the provided token.
Available tools are pre-filtered based on your permissions.

You do NOT need to manually check permissions before calling tools.

## Scope Handling

Some tools require `scope_type` and `scope_id` arguments.

- If a tool schema requires them and does not provide a more specific rule, use the organization scope from the connection context.
- Other scope types are operation-specific and are described in each tool schema when applicable.
- Treat all scope IDs as opaque identifiers; pass them exactly as provided.

## Resource Access Enforcement

In addition to argument scopes, access may be restricted by the token's resource scope.

- The token may restrict access by resource ID or alias pattern.
- These restrictions are enforced server-side.
- If a tool call targets a resource outside the token's allowed resource scope, do NOT retry the same call.
- Explain the authorization limitation clearly to the user.

## Session forwarding (AI Apps / magic links)

Gate proxy and app backends can attach a Fusebase user session to a request using header **`EverHelper-Session-ID`** (also accepted as `everhelper-session-id` on some proxies). Use it with `x-app-feature-token` when calling user-context operations (for example `getMyOrgAccess`) after `activateAppMagicLink`. The feature token authenticates the app; the session header identifies the user.

Load the `appMagicLinks` and `fusebaseAuth` prompts for the full post-activation exchange pattern (`POST /api/account/from-magic-link`, app-owned session cookie).

## Best Practices

- Rely on the tool list provided by the server; unavailable tools usually mean insufficient permission.
- Prefer connection-context defaults when scope arguments are required and no better source is provided.
- Do not guess or fabricate resource IDs.
- If an operation is not allowed, explain the limitation rather than attempting workarounds automatically.
---

## Version

- **Version**: 1.2.0
- **Category**: meta
- **Last synced**: 2026-05-22
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
