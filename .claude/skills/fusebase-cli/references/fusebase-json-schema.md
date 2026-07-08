# fusebase.json Schema

`apps[]` is a **declarative manifest**. Each app entry describes the app
(`subdomain`, `name`, `path`, `dev`, `build`) and **omits the platform app `id`** —
`fusebase deploy` resolves the id at deploy time. The product `id` (`productId`) is
always required.

```json
{
  "orgId": "organization-id",
  "productId": "app-id",
  "apps": [
    {
      "subdomain": "my-app",
      "name": "My App",
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
| `productId` | Yes | The Fusebase product ID (populated automatically by `fusebase init`) |
| `apps` | Yes | Array of app configurations |
| `apps[].subdomain` | Yes | The app's subdomain (`{subdomain}.thefusebase.app`); the deploy match key |
| `apps[].name` | Yes | App title; used when deploy reconcile creates the app |
| `apps[].id` | No | The platform app id. Written **by the CLI** on `fusebase deploy` (write-back after the app is created/bound) — never set it manually or via an AI agent. The platform owns app ids |
| `apps[].path` | Yes | Relative path to the app's source directory |
| `apps[].dev.command` | No | Command to start the dev server (e.g., `npm run dev`) |
| `apps[].build.command` | Yes | Command to build the app for production |
| `apps[].build.outputDir` | Yes | Directory containing build output (relative to app path) |
| `apps[].backend` | No | Backend config (only if the app has a `backend/` folder). See skill **app-backend**. |
| `apps[].backend.dev.command` | No | Command to start the backend dev mode (e.g., `npm run dev`) |
| `apps[].backend.build.command` | Yes (if backend) | Command to build the backend |
| `apps[].backend.start.command` | Yes (if backend) | Command to start the built backend in production (e.g., `npm run start`) |

## Deploy reconcile

`fusebase deploy` resolves every `apps[]` entry to a real platform app id before deploying:

1. Entry has a legacy `id` → trust it as-is.
2. Else `subdomain` matches an existing platform app → **bind** to it.
3. Else → **create** the app from the declaration (`name` + `subdomain` + `path`).

`fusebase app create` only writes the declarative `apps[]` entry (subdomain/name/path, no `id`);
the platform app is created on the first `fusebase deploy`. After a successful deploy, the resolved
id is written back into the matching entry, so the next deploy takes the legacy fast path. You still
never hand-author an id — the platform owns it.

> **Never invent or hand-write an app `id`.** Writing your own `id` and then running
> `fusebase app create` causes a double-registration conflict (a freshly created platform
> app whose id ≠ the one in the file). Add a declarative record (`subdomain`/`name`/`path`,
> no `id`) and run `fusebase deploy` or `fusebase app create` — the CLI/platform owns ids.

## Example fusebase.json

```json
{
  "orgId": "org_abc123",
  "productId": "app_xyz789",
  "apps": [
    {
      "subdomain": "dashboard",
      "name": "Dashboard",
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
      "subdomain": "settings",
      "name": "Settings",
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
