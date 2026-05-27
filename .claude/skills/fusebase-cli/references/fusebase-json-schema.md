# fusebase.json Schema

```json
{
  "orgId": "organization-id",
  "productId": "app-id",
  "apps": [
    {
      "id": "app-id",
      "path": "apps/my-app",
      "dev": {
        "command": "npm run dev"
      },
      "build": {
        "command": "npm run build",
        "outputDir": "dist"
      }
    }
  ]
}
```

## Field Descriptions

| Field | Required | Description |
|-------|----------|-------------|
| `orgId` | Yes | Your Fusebase organization ID |
| `productId` | Yes | The Fusebase App ID (populated automatically by `fusebase init`) |
| `apps` | Yes | Array of app configurations |
| `apps[].id` | Yes | The app ID (must match ID in Fusebase) |
| `apps[].path` | Yes | Relative path to the app's source directory |
| `apps[].dev.command` | No | Command to start the dev server (e.g., `npm run dev`) |
| `apps[].build.command` | Yes | Command to build the app for production |
| `apps[].build.outputDir` | Yes | Directory containing build output (relative to app path) |
| `apps[].backend` | No | Backend config (only if the app has a `backend/` folder). See skill **app-backend**. |
| `apps[].backend.dev.command` | No | Command to start the backend dev mode (e.g., `npm run dev`) |
| `apps[].backend.build.command` | Yes (if backend) | Command to build the backend |
| `apps[].backend.start.command` | Yes (if backend) | Command to start the built backend in production (e.g., `npm run start`) |

## Example fusebase.json

```json
{
  "orgId": "org_abc123",
  "productId": "app_xyz789",
  "apps": [
    {
      "id": "feat_dashboard",
      "path": "apps/dashboard",
      "dev": {
        "command": "npm run dev"
      },
      "build": {
        "command": "npm run build",
        "outputDir": "dist"
      }
    },
    {
      "id": "feat_settings",
      "path": "apps/settings",
      "dev": {
        "command": "npm run dev -- --port 5174"
      },
      "build": {
        "command": "npm run build",
        "outputDir": "dist"
      },
      "backend": {
        "dev": { "command": "npm run dev" },
        "build": { "command": "npm run build" },
        "start": { "command": "npm run start" }
      }
    }
  ]
}
```