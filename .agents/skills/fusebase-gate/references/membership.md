---
version: "1.0.0"
mcp_prompt: membership
last_synced: "2026-03-31"
title: "Fusebase Gate Membership And Portal Flows"
category: specialized
---
# Fusebase Gate Membership And Portal Flows

> **MARKER**: `mcp-membership-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `membership` for latest content.

---
## Fusebase Gate Membership And Portal Flows

These prompts cover organization member invites, workspace selection, portal discovery, and portal magic-link behavior exposed through Gate.

## Relevant Operations

- getMyOrgAccess: read the authenticated user's org access state without requiring existing org membership.
- listWorkspaces: list workspaces visible in an organization and identify the default workspace.
- listPortals: list portals visible in an organization.
- addOrgUser: create an org invite, workspace invite, or portal invite depending on payload shape.

## Access Status Rules

- Use getMyOrgAccess for session-backed apps that need to distinguish signed-out users from authenticated users whose org membership is still being provisioned.
- Never unlock org UI from addOrgUser success alone; confirm with getMyOrgAccess.
- Do not use listOrgUsers as an authentication gate for onboarding flows.
- `membershipStatus: "ready"` means the current user already has org access.
- `membershipStatus: "none"` means the user is authenticated but does not currently have org membership.
- `membershipStatus: "expired"` or `"disabled"` means a membership record exists but should not grant access.

## Workspace Discovery Rules

- If the caller needs to choose where a member should be invited, call listWorkspaces first.
- The response marks the org default workspace with `isDefault: true`.
- `workspaceId` may be either a real workspace id or the literal alias `default`.
- In Gate, `default` is resolved by `orgId` to the organization's default workspace before calling org-service.

## Portal Discovery Rules

- Use listPortals when the caller needs existing portal domains for the organization.
- A portal belongs to both an `orgId` and a `workspaceId`.
- Portal listing is discovery-only; invitation still happens through addOrgUser.

## Invite Flow Rules For addOrgUser

- Org invite: send `email` and optionally `orgRole`; omit `workspaceId`.
- Workspace invite: send `email`, `workspaceId`, and `workspaceRole`.
- Portal invite: send `email`, `workspaceId`, `workspaceRole`, and `portalUrl`.
- For instant client onboarding without invite confirmation, send `orgRole: "client"` with `autoConfirmClientInvite: true` and omit `workspaceId`.
- `autoConfirmClientInvite` is only valid for org-only client onboarding with `orgRole: "client"` and no `workspaceId`.
- Optional fields for workspace or portal invites: `orgRole`, `encryptRole`, `fullName`, `memberTTL`.
- Do not invent workspace ids or portal domains. Discover them first or use `workspaceId: "default"` when appropriate.

## Response Interpretation

- `target: "org"` means org-only membership flow.
- `target: "workspace"` means workspace membership flow.
- `target: "portal"` means portal magic-link flow.
- `result: "invite"` means an invite record exists, not that the current session already has org access.
- `result: "member"` means org-service returned an active membership record.
- `result: "link"` means org-service returned a portal magic link; inspect `magicLink` and related workspace membership fields.
- After addOrgUser, verify access through getMyOrgAccess before treating the target user as fully provisioned in the org.

## Working Rules

- Always inspect the exact contract with tools_describe or sdk_describe before calling addOrgUser.
- Treat `orgId` as required path input for all membership and portal discovery operations.
- If a write fails, verify caller permissions and org access before assuming a schema problem.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-03-31
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
