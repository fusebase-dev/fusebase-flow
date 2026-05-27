Calling third-party services in runtime is pretty similar to how MCP tools are called:

```ts
import { createClient, McpManagerApi } from '@fusebase/fusebase-gate-sdk'

...

function createMcpManagerApi(featureToken: string): McpManagerApi {
  return new McpManagerApi(
    createClient({
      baseUrl: GATE_BASE_URL,
      defaultHeaders: { 'x-app-feature-token': featureToken },
    }),
  )
}
```

```ts
const SERVER_GLOBAL_ID = "f63f95b7-de70-48ff-bcf4-9586ae105e7d";

const api = createMcpManagerApi(featureToken)
const response = await api.callMcpManagerServerTool({
  path: { serverId: SERVER_GLOBAL_ID },
  body: {
    toolName: "TODOIST_CREATE_TASK",
    args: {
      content: "Buy milk"
    }
  },
})
```

`args` has the exact same shape as the corresponding tool in the MCP, so use the MCP to get its shape (that's why the MCP connection is necessary).
`SERVER_GLOBAL_ID` is the ID of the MCP server in our MCP service. Each integration (authorization) requires its own server.
- In the case of shared integration, the app would require only one server ID
<% if (it.flags?.includes("managed-integrations-personal-auth")) { %>
- If the app has to support personal authorizations, a server for each of them has to be created.
In this context, "server" is just one established integration with a concrete user's account. We will cover the creation of a server later.
<% } %>

Pay attention that the response of such a tool call may differ from the actual MCP tool call result. More specifically, the response will be wrapped in the following type:
```ts
type CallToolResult = {
    _meta?: Record<string, unknown>;
    content: Array<
      | { type: "text"; text: string }
      | { type: "image"; data: string; mimeType: string }
      | { type: "audio"; data: string; mimeType: string }
      | {
          type: "resource";
          resource:
            | { uri: string; mimeType?: string; text: string }
            | { uri: string; mimeType?: string; blob: string };
        }
    >; // always present (can be empty)
    structuredContent?: Record<string, unknown>;
    isError?: boolean;
  };
```

and the actual tool output is inside objects in the `content` array.

For example, if the MCP tool's output looks like this:
```json
{
  "successful": true,
  "error": null,
  "data": {
    "next_cursor": "..." | null,
    "tasks": [ ... ]
  },
  "version": "20260504_00",
  "auth_refresh_required": false,
  "mercury_last_http_status_code": 200,
  "is_latest_version": true,
  "log_id": "log_..."
}
```

the output of the "manual" tool call from the code will look like this:
```json
{
  "content": [
    {
      "type": "object",
      "object": {
        "successful": true,
        "error": null,
        "data": {
          "next_cursor": null,
          "tasks": [...]
        },
        "version": "20260504_00",
        "auth_refresh_required": false,
        "mercury_last_http_status_code": 200,
        "is_latest_version": true,
        "log_id": "log_..."
      }
    }
  ],
  "isError": false
}
```

You need to handle the response shape properly, considering that.
