Using these instructions, you can add any supported integration from the list as an MCP server.
Please note that this is **not** the same as custom MCPs, where a user can connect whatever they wish.

# Getting a list of available templates
Use the `fusebase integrations list-templates` script to get a list of available MCP server templates.
Example output:
```
Managed templates
  • Airtable by Composio (id: `ebe4df3f-b8cb-48db-846a-839db922dae0`, app: `airtable`)
  • Asana by Composio (id: `3780787b-2c5d-4a1a-9b9e-6928dc896a95`, app: `asana`)
  ...
```

# Creating a connection to a specific template
After retrieving the list, you can create a new MCP connection to any template.
To do so, use the `fusebase integrations connect --template-name "<template name>"` command. For example:
```sh
fusebase integrations connect --template-name "Todoist by Composio"
```
This starts a process that provides an auth link to the user and automatically stops once the user authorizes.
The output will include the server's ID and URL. Example output:
```
Complete OAuth in browser before timeout: https://backend.composio.dev/api/v3/s/0qv-i1lT
✓ Managed MCP server connected.
  Template   Todoist by Composio
  Server ID  118fbeab-aa48-467e-8dc7-3eb6216cec78
Command:
https://backend.composio.dev/v3/mcp/3de456c3-e58d-4d4e-b55d-03e2c39588c3/mcp?user_id=org-auth-script-scope-10d2d025
```

# Adding the new connection to the config
Once the connection is established and authorized, you can add it to the MCP config.
Note that you must update all MCP configs present in the project.

## Examples

### Claude Code
`.mcp.json`:
```json
{
  "mcpServers": {
    "todoist-composio": {
      "type": "http",
      "url": "https://backend.composio.dev/v3/mcp/c2855da2-2f77-4537-a757-cecc614a6cd2/mcp?user_id=org-u8wk-62fa1635"
    }
  }
}
```

### Codex
`.codex/config.toml`:
```toml
[mcp_servers.todoist-composio]
url = "https://backend.composio.dev/v3/mcp/c2855da2-2f77-4537-a757-cecc614a6cd2/mcp?user_id=org-u8wk-62fa1635"
```

# Important notes
- Immediately after adding an MCP to the coding agent config, it may not be available. In that case, the coding agent (including you) must be restarted. Notify the user and do not continue work until they have done so (you can verify this by checking access to the MCP server).
- You must run the connection command in the background, provide the auth URL to the user, and then wait for the command output once the user authorizes.
- **Do not** proceed until the user completes authorization.
