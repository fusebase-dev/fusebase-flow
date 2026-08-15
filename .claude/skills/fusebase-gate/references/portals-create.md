---
version: "1.1.0"
mcp_prompt: portals-create
last_synced: "2026-08-05"
title: "Fusebase Gate Portals — Create Operations"
category: specialized
---
# Fusebase Gate Portals — Create Operations

> **MARKER**: `mcp-portals-create-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `portals-create` for latest content.

---
## Fusebase Gate Portals — Create Operations

These operations create new portals in an organization.

## Relevant Operations

- createPortal — creates a new v2 portal. Required fields: `workspaceId` (the workspace
  the portal belongs to), `domain` (the full portal domain, e.g.
  `my-portal.p.dev-thefusebase.com` in dev or `my-portal.p.thefusebase.com` in prod).
  Optional fields: `name` (portal display name), `theme` (color theme key, see below).
  The portal is created with version=2 using modern infrastructure. For `*.p.<env-domain>`
  domains (P_SUB type), the portal reaches "ready" status synchronously. For
  custom/org-subdomain domains, status starts as "pending" and transitions to "ready"
  asynchronously — use getPortal to poll.
  Note: v2 portals do not return admin credentials at creation time.

- duplicatePortal: creates a new portal as a full copy of an existing portal.
  Required path param: `portalId` (the source portal to copy).
  Required body fields: `workspaceId`, `domain` (the new portal's full domain).
  Optional: `name` (display name for the new portal).
  All content is copied: settings, theme, menu structure, pages, and blocks.
  Status is 'ready' immediately for P_SUB domains; 'pending' for custom/CNAME domains
  or if content copy is still in progress — use getPortal to poll until 'ready'.
  Note: theme is inherited from the source portal; do NOT ask the user to pick a theme.

## Theme Selection Rule

  When the user invokes createPortal WITHOUT specifying a theme, ALWAYS ask which color
  scheme they want before calling the operation. Present the list below and wait for
  their answer. Do not proceed with a default silently.

  Available themes (use the key as the `theme` value):
  - `light_purple`     — The Light Purple
  - `soft_light`       — Soft Light
  - `quite_green`      — Quite Green
  - `space_gray`       — The Space Gray
  - `carbon`           — Carbon
  - `oxford`           — Oxford
  - `ultramarine`      — Ultramarine
  - `milky_blue`       — Milky Blue
  - `shades_of_green`  — Shades of Green
  - `savvy_red`        — Savvy Red
  - `light_orange`     — The Light Orange
  - `light_blue`       — The Light Blue
  - `lemon_drop`       — Lemon Drop

## Identity And Scoping Rules

- `orgId` is a required path parameter for all portals operations.
- `portalId` is the opaque portal identifier returned by `listPortals`. Do not invent portal IDs.
- Write operations (`createPortal`, `duplicatePortal`) require `org.write` permission scoped to the organization.

## Workspace Occupancy Rule

- Before calling `createPortal` or `duplicatePortal`, verify whether the target `workspaceId` already has a portal.
- If the workspace already contains at least one portal, do NOT create or duplicate another portal in that workspace.
- In that case, ask the user to create a new workspace first (`createWorkspace`) and then continue with
  `createPortal` or `duplicatePortal` using the newly created workspace ID.
- Do not bypass this rule even if the user asks to force creation in an occupied workspace.

- Use `duplicatePortal` instead of `createPortal` when the user wants to copy content from an existing portal.
- After `duplicatePortal` (or `createPortal`) with a custom/CNAME domain, poll `getPortal` until `status` is `'ready'`.
---

## Version

- **Version**: 1.1.0
- **Category**: specialized
- **Last synced**: 2026-08-05
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
