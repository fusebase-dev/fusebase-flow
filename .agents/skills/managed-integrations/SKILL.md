---
name: managed-integrations
description: Guide on creating connections to third-party services and integrating them into apps. Use when a user requests functionality involving communication with third-party services
---

We natively support certain third-party service integrations at 2 levels:
1. Via MCP for the development phase
2. Via HTTP calls to our special service for runtime

For more information on integrations during the development stage, check out the `creating-mcp-server` reference.

In this guide, we will cover creating runtime integrations so users can work with Gmail, Asana, Todoist, and other services directly from their own apps, using shared authorization (used by all people with access to the app)<% if (it.flags?.includes("managed-integrations-personal-auth")) { %>, or personal authorization for each user<% } %>.

# Prerequisites
Before integrating any third-party service in the app, make sure that the MCP for this service is connected to you. Check out the `creating-mcp-server` reference for more information.
For example, if an app needs to use Asana, first connect the Asana MCP and verify access to its tools. We will explain why it's needed later.
**Important!**: You must NOT proceed to the next steps until the needed MCP is active. NEVER try to do any workarounds; always ensure that the MCP is active.

# Calling third-party services in runtime
Check out the `calling-server-tool` reference to see how third-party service methods are called.

# Implementation

## Shared authorization
Check out the `shared-auth-flow.md` reference for the shared auth implementation guide.

<% if (it.flags?.includes("managed-integrations-personal-auth")) { %>
## Personal user authorization
Check out the `personal-auth-flow.md` reference for the user-specific auth implementation guide.
<% } %>
