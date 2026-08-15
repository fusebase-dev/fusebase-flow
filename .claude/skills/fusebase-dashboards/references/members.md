---
version: "1.0.0"
mcp_prompt: domain.members
last_synced: "2026-07-16"
title: "Members (system dashboard)"
category: specialized
---
# Members (system dashboard)

> **MARKER**: `dashboards-members-system-dashboard-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.members` for latest content.

---
## Context: Members System Dashboard

- Standalone system dashboard with `root_entity` `member` and stable template alias `members`.
- Each row represents an active organization member, including the Owner and other non-client roles. Client-role users belong to the Clients dashboard and are excluded.
- Member rows are owned by organization membership. Dashboard row operations must not create or delete member rows.

---

## Structure

### Members system dashboard data

- `Member name` is structured member identity; `Member email` is the email address; `Role` is Owner, Manager, Member, or Guest; `Workspaces`, `Portals`, and `Groups` are current platform associations.
- `Member name`, `Member email`, `Role`, `Workspaces`, `Portals`, and `Groups` are derived and read-only.
- `Files`, `Member phone`, and `Member address` are dashboard-backed and editable on an existing member row, subject to the live schema and normal value-format rules. `Files` contains files attached as dashboard data; `Member phone` stores a phone value; `Member address` stores multiline text. User-added custom columns are also writable according to their live column configuration.

---

## MCP discovery pattern

- One Members dashboard is intended per organization. Discover the existing dashboard in organization scope with `getDashboards`. If it is missing, create it through the standard system-dashboard template flow using REST or SDK.
- Use the selected dashboard and view plus the live `getDashboardView` schema to discover runtime identifiers. Do not hardcode organization UUIDs or generated column keys.

---

## Rules

- For Members, `batchPutDashboardData` may update writable fields only with `root_index_value` from an existing member row. Do not set `create_new_row: true`.
- For relation or lookup values, follow the standard relation workflow: do not write relation or lookup item keys through `batchPutDashboardData`; use discovered relation IDs and relation-row operations.

---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-07-16
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
