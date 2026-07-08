---
version: "1.2.0"
mcp_prompt: users
last_synced: "2026-07-03"
title: "Fusebase Gate Users Operations"
category: specialized
---
# Fusebase Gate Users Operations

> **MARKER**: `mcp-users-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `users` for latest content.

---
## Fusebase Gate Users Operations

These operations manage organization membership flows and safe member removal exposed by Gate.

## Scope

- listOrgUsers returns organization members for a specific org.
- addOrgUser can create an org invite, workspace invite, or portal invite depending on payload shape.
- removeOrgMember removes an organization member by numeric `userId`.
- removeWorkspaceMember removes a workspace member by `workspaceId` plus numeric `userId`.
- removePortalMember is a portal-named alias for removing the underlying workspace member by `workspaceId` plus numeric `userId`.
- scheduleClientAccountDeletion schedules delayed account deletion only for target users whose role in the org is `client`.

## Access Model

- Reading users requires org.members.read and org access.
- Adding/removing users and scheduling client account deletion require org.members.write and org access.
- Write operations are executed against org-service using user-scoped internal auth, so caller permissions matter.

## Working Rules

- Always discover exact params and response contracts through tools_describe or sdk_describe before writing integration code.
- Treat orgId as required path input for all org-user operations.
- For addOrgUser, send the request body under body with the exact schema expected by the operation.
- For removeOrgMember, pass the numeric user id from listOrgUsers.
- For removeWorkspaceMember/removePortalMember, pass the target workspace id and numeric user id. Gate resolves internal membership ids.
- For scheduleClientAccountDeletion, pass body.userId as the numeric target user id; Gate validates the target is a Client-role org member before calling user-service.
- scheduleClientAccountDeletion is delayed/soft first; do not describe it as immediate hard deletion.
- A 201 from addOrgUser is not proof that the current session or target user already has org access.
- A 201 from addOrgUser is not proof that the user can receive **App** self-service magic links: org membership does not update App `accessPrincipals`. After inviting a member, set `fusebase app update <appId> --access=…` or use `createAppMagicLink` with `addToAccessPrincipals` (see `appMagicLinks` / `fusebaseAuth` prompts).
- For access gating after provisioning, verify with getMyOrgAccess instead of inferring from addOrgUser success.
- `autoConfirmClientInvite` is only valid for org-only invites with `orgRole: "client"`.
- For workspace or portal flows, load the membership prompt group and inspect the operation contract before constructing payloads.
- If org-service rejects writes with access errors, investigate caller auth context or org membership privileges before changing payload shape.

## Typical Workflow

1. Use tools_describe or sdk_describe for the org-user operation you plan to call.
2. Confirm required permissions and input contract.
3. Use listOrgUsers to discover target roles/ids before removal or client account deletion.
4. If a write fails, debug auth context before assuming a contract mismatch.
---

## Version

- **Version**: 1.2.0
- **Category**: specialized
- **Last synced**: 2026-07-03
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
