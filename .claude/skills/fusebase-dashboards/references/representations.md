---
version: "1.1.0"
mcp_prompt: domain.representations
last_synced: "2026-04-09"
title: "Dashboard View Representations"
category: specialized
---
# Dashboard View Representations

> **MARKER**: `dashboards-representations-concepts-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `domain.representations` for latest content.

---
# Dashboard View Representations

## Concepts

### What is a Representation?
A **representation** defines how a dashboard view's data is displayed (layout, styling, UI components).
- Each view can have multiple representation instances (different display modes)
- One representation per view can be marked as **default**
- Representations are based on **representation templates**

### Representation Templates
Templates define the structure and behavior of a representation:
- **Managed templates**: System-provided, available to all users (e.g., table, grid, kanban)
- **Custom templates**: Created by orgs, scoped to specific org

### Template Types
Each template has a `type` field:
- `"managed"`: Built-in templates managed by the system
- `"custom"`: User-defined templates, org-scoped

### Representation Instance
When a template is assigned to a view, it creates a **representation instance** with:
- `representationTemplateId`: The template being used. For kanban it's "kanban"
- `is_default`: Whether this is the default representation for the view
- `settings`: Custom configuration for the representation
- `fields_map`: Optional mapping of dashboard fields to representation-specific field roles

## Rules of Thumb

1. **Templates must be verified**: Custom templates can only be used with dashboards in the same org scope.
2. **Managed templates are universal**: Any dashboard can use any managed template.
3. **One default per view**: Only one representation instance per view can have `is_default: true`.
4. **First assignment = auto-default**: When assigning the first representation to a view, it's automatically set as default.
5. **Template ID is UUID**: Use the template's `global_id` (UUID), not its internal integer ID.

## Common Workflows

**Not in MCP**: Listing representation templates (`getDashboardViewRepresentationTemplates`) and assigning a representation to a view (`assignRepresentationToView`) are not exposed as MCP tools. Use the SDK or REST API for these operations. The concepts above still apply when using the API.

### 2. Assign a Representation to a View
**Not in MCP**: Assigning a representation to a view (`assignRepresentationToView`) is not exposed as an MCP tool. Use the SDK or REST API for this.

### 3. Update an Existing Representation
Representation assignment and updates are not in MCP; use SDK or REST.

## Notes

- **Do not hardcode template IDs**—use `tools_search` to find available templates first.
- **Settings and fields_map are optional**: Default behavior is used if omitted.
- **Template scope enforcement**: The system automatically validates that custom templates match the dashboard's org scope.
- **Representation metadata**: Stored per-instance, allowing the same template to be used with different settings on different views.
---

## Version

- **Version**: 1.1.0
- **Category**: specialized
- **Last synced**: 2026-04-09
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
