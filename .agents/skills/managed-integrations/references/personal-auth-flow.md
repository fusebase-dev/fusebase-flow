<% if (it.flags?.includes("managed-integrations-personal-auth")) { %>
Personal (user-specific) auth is needed when each user needs to see their own information from a third-party service.

Creating a personal authorization from the frontend involves several steps:

## Step 1: Initiate auth
The user clicks "Connect" on a dedicated page on the frontend. After that, the user is redirected to
`https://app.{FUSEBASE_HOST}/integrations/auth?templateId=<template id>&clientId=<product id>&<returnTo>=<url of redirect>`
- `templateId` -- ID of the template that has to be connected. It can be obtained during app development using the `fusebase integrations list-templates` command.
- `clientId` -- ID of the current product
- `returnTo` -- URL to which the user will be redirected after authorization is completed. It will be explained in more detail later.

## Step 2: Handling authorization completion
After the user authorizes the integration on the `/integrations/auth` page, they will be redirected to `returnTo` with the `serverId` query param.
You must implement a page on the app's side that handles this redirect and passes its URL to the `returnTo` parameter.
On this redirect handler page, you should save `serverId` to local storage.

## Step 3: Using the created integration
After the integration server ID is obtained and saved, you can use it for communication with the third-party service in a way described in the `calling-server-tool` reference.
**Important!**: Unlike the shared authorization case, requests must be made directly from the frontend part of the app, because a special cookie will be attached automatically. **It is crucial** for personal integrations to work properly.

# Important cases
- If the server ID for some template is already present on the frontend, do not start the initialization flow and do not prompt the user to do it. Just use the existing server.
<% } %>
- The `McpManagerApi` client must have `credentials: 'include'` for the authorized server to work properly, for example:

```ts
new McpManagerApi(
  createClient({
    baseUrl: GATE_BASE_URL,
    defaultHeaders: { 'x-app-feature-token': featureToken },
    credentials: 'include',
  }),
)
```
- The app must be able to handle the case when a user's personal authorization expires. The app can tell that this has happened if, when attempting to call an integration tool, it receives an HTTP 403 response. In this case, delete the saved server information and prompt the user to authorize again.
