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
If you need to add an entry to the table with a portal-based filter, you need to ensure that the row you have created contains the current portal. Get it via the `/auth/context` request described in the `app-dev-practices` skill. If `runtimeContext.portalId` is not present, you have no portal to write — leave the filter column empty. (Absence usually means "outside a portal", but not always; see "Detecting portal context" below.)

## Detecting portal context

`Boolean(runtimeContext?.portalId)` from `/auth/context` is the instant "am I inside a portal?"
signal — no server round-trip needed to decide what to render.

- Opened from a portal embed → `runtimeContext.portalId` and `runtimeContext.workspaceId` are
  present for **every** portal role (client, manager, anonymous visitor) and **every** portal
  access mode. The portal context token lives on the portal block, not on the viewer's session,
  so role and access mode never affect it.
- Opened directly by the app's own URL, or run locally via `fusebase dev start` → both absent.
- **Legacy portal blocks** added before April 2026 carry no portal context token, so the fields
  are absent even inside a portal. Fixable per block in the portal customizer — see below.
- A block **copied from another portal** keeps the source portal's token, so `portalId` can name a
  different portal than the one displaying the app. That covers block copy-paste, duplicating a
  page from another portal ("Create from another portal"), duplicating a whole portal or creating
  one from a template (then *every* app block carries the template portal's id), and synced-copy
  propagation into another portal's page. Same fix.

Both are fixed by making the block's app selection actually **change**: pick a different app in
that block and then the intended one again. Re-picking the *same* app does nothing — the App
picker ignores an unchanged value, so no token is minted. If the product has only one app, delete
the app block and add it again.

Because of the last two cases, do not turn a missing `portalId` into an unrecoverable dead end —
degrade to the standalone UI rather than a hard "open me from a portal" wall.

See "Portal context contract" in the `app-dev-practices` skill for the full contract.

**It is a UX hint, not an authorization fact.** Access to portal data must still be authorized
server-side by verifying the `portalFeatureContextToken`.

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
