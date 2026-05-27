Shared authorization means that all users of the app will have access to the same account in the third-party service. It may be useful if you want to show a shared calendar, task board, posts, etc.

Creating a server for shared authorization is straightforward. The command used in the `creating-mcp-server` reference for MCP connection creation returns the server ID alongside the MCP URL. You should use that server ID.
Feel free to create a new server if the server ID was not captured during the MCP connection phase; it is not required to reconnect to the most recent MCP server.

You can save the obtained server ID as an environment variable or hardcode it in the code.
**Important!** Make sure the server is saved in the backend part of the project and not exposed to the frontend. That applies **only** to the shared auth flow.

# Important notes
- It is strictly required to use a project template with both frontend and backend for shared auth flows, and to make requests to the integrations API from the backend only. So if any information from the integration has to be retrieved on the frontend, the request must be proxied through the backend. It is required for security reasons.
