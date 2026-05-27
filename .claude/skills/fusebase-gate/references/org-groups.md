---
version: "1.1.0"
mcp_prompt: org_groups
last_synced: "2026-04-13"
title: "Fusebase Gate Org Group Operations"
category: specialized
---
# Fusebase Gate Org Group Operations

> **MARKER**: `mcp-org-groups-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `org_groups` for latest content.

---
## Fusebase Gate Org Group Operations

These operations manage organization groups, group members, and workspace-group assignments exposed by Gate.

## Relevant Operations

- listOrgGroups, createOrgGroup, getOrgGroup, updateOrgGroup, deleteOrgGroup
- listOrgGroupMembers, addMembersToOrgGroup, removeOrgGroupMember
- listUserOrgGroups
- listOrgGroupWorkspaces, listWorkspaceGroups, listOrgWorkspaceGroups, countWorkspaceGroups
- addGroupToWorkspace, updateWorkspaceGroup, deleteWorkspaceGroup

## Identity And Scoping Rules

- Treat `orgId` as required path input for every org-group operation.
- Treat `groupId` and `workspaceId` as opaque ids. Reuse ids returned by earlier responses instead of inventing them.
- On workspace-scoped org-group routes, `workspaceId` may be a real workspace id or the literal alias `default`.
- Gate resolves `workspaceId: "default"` to the org default workspace before calling org-service.
- `userId` for user-group and group-member routes must stay numeric. Do not stringify it.

## Group Lifecycle Rules

- `createOrgGroup` requires a non-empty `name`.
- `createOrgGroup` can attach initial workspace-role assignments in the same request through `workspaces`.
- `updateOrgGroup` requires at least one of `name`, `description`, or `workspaces`.
- When `workspaces` is provided to `updateOrgGroup`, treat it as a replacement of the group's workspace assignments rather than an append-only patch.
- Sending `description: null` clears the description. Empty strings are normalized away before forwarding to org-service.

## Member Management Rules

- Use `listOrgGroupMembers` to inspect current members before mutating membership.
- `addMembersToOrgGroup` requires `body.userIds` as a non-empty array of positive integer user ids.
- Gate de-duplicates repeated `userIds` before forwarding them to org-service.
- `removeOrgGroupMember` removes one numeric `userId` from one `groupId`.
- Use `listUserOrgGroups` when the caller starts from a user and needs the groups that currently include that user.

## Workspace Assignment Rules

- Workspace-group assignment payloads use a workspace `role` field. Do not confuse that field with Gate operation permissions.
- Use `listOrgGroupWorkspaces` to inspect where one group is assigned.
- Set `workspace: true` on `listOrgGroupWorkspaces` when you need workspace details in each workspace-group record.
- Use `listWorkspaceGroups` or `countWorkspaceGroups` when the caller starts from one workspace.
- `addGroupToWorkspace` requires `groupId` and `role`, and optionally accepts assignment `type` of `full` or `partial`.
- `updateWorkspaceGroup` updates the assigned `role`; it is not a generic partial patch for every workspace-group field.
- `deleteWorkspaceGroup` removes one group assignment from the resolved workspace.
- Current workspace role vocabulary is `reader`, `editor`, `admin`, `no-access`, `deny`.
- If you present role options in UI, preserve the current order: `reader`, `editor`, `admin`, `no-access`, `deny`.
- `reader`, `editor`, and `admin` are the normal positive workspace-access roles.
- `no-access` is a special removal role. In org-service-backed updates, it removes an existing workspace assignment rather than persisting a positive assignment.
- `deny` is an explicit negative role. It can override other positive workspace access grants for the same user, including access inherited from another group.

## Access Model

- Read operations require `org.groups.read` and org access.
- Write operations require `org.groups.write` and org access.
- These Gate permissions authorize the operation call itself; they are separate from the workspace `role` values used inside group assignment payloads.
- Gate forwards these calls to org-service with user-scoped internal auth, so permission failures usually mean caller access is wrong rather than the payload shape.

## Working Rules

- Always inspect the exact contract with `tools_describe` or `sdk_describe` before integrating a new org-group flow.
- If the caller does not already know a `groupId`, discover it through `listOrgGroups` or another list response first.
- If the caller does not already know a `workspaceId`, discover it first or use `workspaceId: "default"` only when the org default workspace is intended.
- If a write fails, investigate caller auth context, org access, and workspace/group ownership before assuming the schema is wrong.
---

## Version

- **Version**: 1.1.0
- **Category**: specialized
- **Last synced**: 2026-04-13
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
