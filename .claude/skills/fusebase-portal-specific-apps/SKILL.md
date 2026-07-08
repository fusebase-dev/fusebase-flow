---
name: fusebase-portal-specific-apps
description: How to develop apps that interact with Fusebase portals where they are embedded. Use when a task requires showing data based on the current parent portal or listing portal pages where the current app is embedded.
---

# Apps in portals
A "portal" is a user-customized website configured in the Fusebase web UI. Portals can display different blocks, including blocks that render apps/apps in an `iframe`.
In this case, information about the current portal is automatically added to the auth context, so requests from the embedded app/app carry portal information automatically.

# Developing portal-specific apps
When the user asks for an app that should show different information based on the portal where it is embedded, use a Fusebase database table with a view filter that uses the `{{CurrentPortal}}` dynamic value. See the `filters` reference in the `fusebase-dashboards` skill for details.
**Important!** You **should not** take a portal ID explicitly as a parameter (query, path, input, etc.); it should be resolved automatically when the view is configured correctly.

## Receiving portal-specific entries
Requests for the data in this view automatically receive the current portal in context, and that value is substituted into the view filter. 

## Writing from a portal
If you need to add an entry to the table with a portal-based filter, you need to ensure that the row you have created contains the current portal. Get it via the `/auth/context` request described in the `app-dev-practices` skill. When the app runs within the portal, the response may contain `runtimeContext.portalId`. If it is not present, then the app is currently running outside of the portal; therefore, the current portal should not be written to a filter column.

## Listing all portal pages where this app is embedded

If runtime code needs to show all portal pages where the current app is embedded, use Fusebase Gate from the app runtime:

- Use `@fusebase/fusebase-gate-sdk`, not MCP.
- Authenticate with the app token via `x-app-feature-token`.
- Use `AppEmbedTargetsApi.listAppPortalEmbeds`.
- Do not use a service-token fallback for user-facing runtime reads.
- The result is org-scoped and returns one entry per portal page; multiple embeds on the same page are deduped by the platform.
- Before publishing an app that calls this operation, run `fusebase app update <appId> --sync-gate-permissions`.

# Important considerations
- When possible, always use a relation column that links to portal dashboards instead of a plain-text column for portal IDs.
- Pay attention to setting a filter on a column that has a relation to the portal dashboard (or portal ID in case you implemented a column of text type for that).
- **Important!** If you are using a relation column for portals, be sure to set the correct render type for this column.
