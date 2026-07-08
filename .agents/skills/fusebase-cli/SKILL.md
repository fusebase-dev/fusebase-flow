---
name: fusebase-cli
description: "Complete guide for using the Fusebase CLI (fusebase) tool to initialize, develop, and deploy Fusebase Apps apps. Use when: 1. Initializing new Fusebase Apps projects, 2. Creating or configuring apps, 3. Running apps locally or deploying them 4. Setting up app permissions for dashboards."
---

# Fusebase CLI (fusebase)

This skill describes how to use the Fusebase CLI tool to manage and deploy Fusebase Apps apps.

## Overview

The Fusebase CLI (`fusebase`) is a command-line tool for:

- Initializing new Fusebase Apps projects
- Managing app development with hot reload
- Deploying apps to the Fusebase platform

## Installation & Authentication

The `fusebase` CLI is installed globally. Always invoke it as `fusebase <command>` — **never use `npx fusebase`**.

Before using the CLI, authenticate with your API key:

```bash
fusebase auth
```

This stores credentials in `~/.fusebase/config.json`.

## Project Configuration (fusebase.json)

Every Fusebase Apps project requires a `fusebase.json` file in the project root. This file defines the app and its apps.

For details on the `fusebase.json` schema, see references/fusebase-json-schema.md.

<% if (it.flags?.includes("declarative-manifest")) { %>
### Declarative manifest — never invent an app `id`

`apps[]` is **declarative**: an app entry carries `subdomain` + `name` and **omits the
platform app `id`**. `fusebase deploy` reconciles each entry against the platform — it binds
to the app with a matching `subdomain`, or creates it if missing. The product `id`
(`productId`) is always required; only the per-app `id` is omitted.

> ⚠️ **Never invent or hand-write an `apps[].id`.** The platform owns app ids. Writing your
> own `id` and then running `fusebase app create` causes a **double-registration conflict** —
> the platform creates a brand-new app whose id no longer matches the one you wrote. Add a
> declarative record (no `id`) and run `fusebase deploy` (or `fusebase app create`); old apps
> that already carry a real `id` keep working unchanged.

**Canonical declarative app record** (add this to `apps[]` by hand — note: no `id`):

```json
{
  "subdomain": "my-app",
  "name": "My App",
  "path": "apps/my-app",
  "dev": { "command": "npm run dev" },
  "build": { "command": "npm run build", "outputDir": "dist" }
}
```
<% } %>

## App Permissions

Apps can have permissions that define which dashboard views they can access. This is **required** when creating apps that interact with specific dashboards.

### Permission Format

Permissions are specified as a semicolon-separated string:

```
dashboardView.dashboardId:viewId.privileges[;dashboardView.dashboardId2:viewId2.privileges2;...]
```

Where:

- `dashboardView` - The permission type (currently only `dashboardView` is supported)
- `dashboardId` - The dashboard's global ID (UUID from MCP or Fusebase UI)
- `viewId` - The view's global ID (UUID from MCP or Fusebase UI)
- `privileges` - Comma-separated: `read`, `write`, or `read,write`

### Setting Permissions

**Always set permissions during app creation** using `--permissions`. This is the correct time — do not skip it and do `app update` later.

```bash
fusebase app create --name="Sales Report" --subdomain=sales-report --path=apps/sales-report --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist --permissions="dashboardView.dash123:view456.read,write"
```

**Only use `app update` when changing existing permissions** (e.g. adding a new view, changing privileges):

```bash
fusebase app update <appId> --permissions="dashboardView.dash123:view456.read;dashboardView.dash789:viewABC.read,write"
```

### When to Use `app update` for Permissions

Only use `app update --permissions` when:

- App already exists and needs access to **additional** dashboard views
- Changing from read-only to read-write (or vice versa) on an existing app
- Restricting access to fewer views on an existing app

**Do NOT** use `app update` to set permissions that should have been set at creation time.

## CLI Commands

### Version

```bash
fusebase version   # Print CLI version (from package.json)
fusebase -V        # Same
```

### Initialize a New Project

```bash
fusebase init [options]
```

Options:

- `--name <name>` - App title/name (if not provided, will prompt interactively)
- `--org <orgId>` - Organization ID (skips org selection if provided)
- `--ide <preset>` - IDE preset: `claude-code`, `cursor`, `vscode`, `opencode`, `codex`, or `other` (single choice; generates all supported IDE configs by default)
- `--force` - Overwrite existing IDE config files/folders
- `--git` - After setup, initialize local Git and sync with configured GitLab remote (creates/uses remote project, configures `origin`, pushes current branch)
- `--skip-git` - Skip local Git initialization and GitLab sync (overrides both `--git` and global `git-init`)
- `--git-tag-managed` - If app is managed, add `managed` topic in GitLab during sync
- In interactive init, CLI also shows a suggested GitLab repository name and lets you edit it before sync
- Global flag `git-init` also enables the same post-init Git offer automatically (`fusebase config set-flag git-init`)
- Global flag `git-debug-commits` enables strict debug/deploy traceability section in the `git-workflow` skill (deploy preflight, commit-per-fix, SHA/tag references)
- Global flag `app-business-docs` includes the `app-business-docs` skill (English `docs/en/business-logic.md` maintenance)
- Global flag `mcp-gate-debug` includes the `mcp-gate-debug` skill (post–Gate MCP debug summary; isolated stores emphasis)
- Global flag `isolated-stores` enables isolated stores functionality (SQL/NoSQL), including required Fusebase Gate references and `isolated_store.*` permissions in `fusebase env create`
- Global flag `portal-specific-apps` includes portal-specific prompts/guidance (`fusebase-portal-specific-apps` skill, `{{CurrentPortal}}` filter references, and `/auth/context` portal runtime context notes)

This command **always creates a new app** on Fusebase and initializes the project. It will:

- Prompt for organization selection (or use `--org` if provided)
- Create a new app with the specified name
- Generate `fusebase.json` configuration
- Set up the basic project structure with template files

If the current directory is not empty and you decline the confirmation prompt, initialization stops without creating the app or local config.

Examples:

```bash
# Initialize interactively (prompts for all values)
fusebase init

# Initialize with app name specified
fusebase init --name="My App"

# Initialize with all options (fully non-interactive, assumes single org)
fusebase init --name="My App" --org=org_abc123
```

### Local Git and GitLab sync (optional)

```bash
fusebase git
fusebase git sync [--git-tag-managed]
```

`fusebase git` runs local `git init` and ensures a baseline **`.gitignore`** with common ignores (`node_modules/`, `dist/`, `.env` files, logs, caches, OS/IDE noise).
`fusebase git sync` connects the current local repo to GitLab (from global config in `~/.fusebase/config.json`) and pushes the current branch.
Equivalent flag form: `fusebase git --git-sync` (with optional `--git-tag-managed`).

To configure GitLab values in global CLI config:

```bash
fusebase config gitlab
fusebase config gitlab --show
fusebase config gitlab --host gl.nimbusweb.co --group vibecode --token glpat_xxx
fusebase config gitlab --clear-token
```

Required global config keys in `~/.fusebase/config.json`:

- `gitlabHost`
- `gitlabToken`
- `gitlabGroup`

GitLab repo naming:

- Format: `app-<base>-<env>`
- Base priority: app title (with Cyrillic transliteration fallback) → current folder name → app subdomain

Use `fusebase init --git` to run the same flow automatically after app setup.

### Development Mode

#### Start the Dev Server

```bash
fusebase dev start [FEATURE_ID_OR_PATH]
```

FEATURE_ID_OR_PATH - id of the app of relative path to it, for example if an app is in `apps/my-app`, you can pass `my-app` or `apps/my-app`.

Starts the development environment:

- **UI Server (port 4173)**: Displays apps in iframes for testing
- **API Proxy (port 4174)**: Proxies API requests with authentication

The dev server automatically:

- Injects your API credentials
- Delivers app tokens to iframes via `postMessage`
- Refreshes tokens when apps are selected
- Creates per-session debug logs under the selected app directory's `logs/dev-<timestamp>/`:
  - `browser-logs.jsonl`
  - `access-logs.jsonl`
  - `backend-logs.jsonl`
  - `frontend-dev-server-logs.jsonl`

When debugging local runtime issues after starting the dev server, load skill **dev-debug-logs**. It explains which file to inspect for browser errors, proxied API traffic, frontend dev server output, and backend output.

#### Create and Configure App

```bash
fusebase app create --name <name> --subdomain <subdomain> --path <path> --dev-command <command> --build-command <command> --output-dir <dir> [options]
```

This command **always creates a new app** on Fusebase servers and configures its development parameters. All six core options are required.

**Required Options:**

- `--name <name>` - Name for the new app
- `--subdomain <subdomain>` - Subdomain for the app (e.g., `my-app`); the app is served from the root of this subdomain
- `--path <path>` - Relative path to the app directory (e.g., `apps/my-app`)
- `--dev-command <command>` - Dev server command (e.g., `npm run dev`)
- `--build-command <command>` - Build command (e.g., `npm run build`)
- `--output-dir <dir>` - Build output directory (e.g., `dist`)

**Optional Options:**

- `--access <principals>` - Set access principals, comma-separated (e.g., `visitor`, `orgRole:member`, `visitor,orgRole:guest`)
- `--permissions <permissions>` - Set dashboard view permissions (format: `dashboardView.dashboardId:viewId.read,write;...`)
- `--backend-dev-command <command>` - Backend dev command (e.g., `npm run dev`). Only if the app has a `backend/` folder.
- `--backend-build-command <command>` - Backend build command (e.g., `npm run build`). Only if the app has a `backend/` folder.
- `--backend-start-command <command>` - Backend start command for production (e.g., `npm run start`). Only if the app has a `backend/` folder.
- `--coding-agent <name>` - Coding agent identifier (e.g. `claude_code`, `cursor`, `copilot`, `codex`).  Populate this field with your name.
- `--model <name>` - Model identifier (e.g. `claude-opus-4-6`, `gpt-5`). Populate this field with the model name currently used.

**Examples:**

```bash
# Create an app
fusebase app create --name="Dashboard Widget" --subdomain=dashboard-widget --path=apps/dashboard --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist

# Create app with permissions for specific dashboard views
fusebase app create --name="Sales Report" --subdomain=sales-report --path=apps/sales-report --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist --permissions="dashboardView.dash123:view456.read,write;dashboardView.dash789:viewABC.read"

# Create app with a backend
fusebase app create --name="My App" --subdomain=my-app --path=apps/my-app --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist --backend-dev-command="npm run dev" --backend-build-command="npm run build" --backend-start-command="npm run start"
```

### Update App Settings

```bash
fusebase app update <appId> [options]
```

Update settings for an existing app.

**Options:**

- `--access <principals>` - Set access principals, comma-separated (e.g., `visitor`, `orgRole:member`, `visitor,orgRole:guest`)
- `--permissions <permissions>` - Set dashboard view permissions (format: `dashboardView.dashboardId:viewId.read,write;...`)
- `--sync-gate-permissions` - Analyze Gate SDK calls in the app's runtime code and sync the detected operations as Gate permissions on the app. Required before an app that uses `@fusebase/fusebase-gate-sdk` can be considered fully published.

**Access Principals:**

The `--access` option replaces the entire access principal list. Principals are comma-separated entries of the form `type` or `type:id`:

| Principal      | Example          | Description                                                                                  |
| -------------- | ---------------- | -------------------------------------------------------------------------------------------- |
| `visitor`      | `visitor`        | Any unauthenticated visitor (public access).                                                 |
| `orgRole:<id>` | `orgRole:member` | Org members with the given role. Valid ids: `guest`, `client`, `member`, `manager`, `owner`. |

**Permissions:**
The `--permissions` option specifies which dashboard views the app can access and with what privileges.

Format: `dashboardView.dashboardId:viewId.privileges` separated by semicolons for multiple views.

- `dashboardView` - The permission type (required prefix)
- `dashboardId` - The dashboard's global ID (UUID)
- `viewId` - The view's global ID (UUID)
- `privileges` - Comma-separated list: `read`, `write`, or `read,write`

**Examples:**

```bash
# Make an app publicly accessible (visitor = any unauthenticated user)
fusebase app update аgjg851jguanadi41 --access=visitor

# Allow org members only
fusebase app update аgjg851jguanadi41 --access=orgRole:member

# Allow multiple roles
fusebase app update аgjg851jguanadi41 --access=orgRole:member,orgRole:client

# Public + org members
fusebase app update аgjg851jguanadi41 --access=visitor,orgRole:member

# Remove all access principals (pass empty string), it will allow access for every role in organization, but not for visitors
fusebase app update аgjg851jguanadi41 --access=""

# Grant read access to a single dashboard view
fusebase app update аgjg851jguanadi41 --permissions="dashboardView.dashABC:view123.read"

# Grant read/write access to multiple views
fusebase app update аgjg851jguanadi41 --permissions="dashboardView.dash1:view1.read,write;dashboardView.dash2:view2.read"

# Update both access and permissions
fusebase app update аgjg851jguanadi41 --access=visitor --permissions="dashboardView.dash1:view1.read"
```

### Smart update (`fusebase update`)

```bash
fusebase update
```

Single update command for both CLI and app:

- in app directory (`fusebase.json` exists): runs CLI self-update first (skip with `--skip-cli-update`; local linked/source mode auto-skips), then refreshes agent assets (`AGENTS.md`, `.claude/skills`, `.claude/agents`, `.claude/hooks`, `.claude/settings.json`), then runs selective MCP token refresh + IDE MCP config refresh, then syncs managed SDK deps and runs targeted `npm install`;
- outside app directory: runs only CLI self-update;
- use `--skip-product` to force CLI-only mode even inside an app directory.

On Windows the CLI self-update is a **cache swap** (updates the cached CLI under `%LOCALAPPDATA%\FuseBase\CLI\` with no admin elevation and no installer download), so the remaining app stages continue in the same run — just like macOS/Linux.

**Windows launcher commands:**

- `fusebase update --launcher` — refreshes the stable launcher `fusebase.exe` via the elevated installer (the only path that prompts for admin). Windows-only; a no-op on macOS/Linux. Run it when the CLI tells you the launcher is too old, or when prompted by the non-blocking "A launcher update is available" nudge.
- `fusebase --previous-version <cmd>` — runs the retained previous cached CLI version for that one invocation (escape hatch when a new version misbehaves or a launcher gate is blocking). The next normal run goes back to the active version.

### Create or update .env (MCP token)

```bash
fusebase env create
```

Creates or overwrites `.env` with `DASHBOARDS_MCP_TOKEN` and `DASHBOARDS_MCP_URL`. Use after `fusebase init` or when the MCP token has expired. Requires `fusebase.json` (with `orgId`) and `fusebase auth` to be set.

On successful create/update, CLI refreshes both Dashboards and Gate MCP tokens. In interactive terminals, it offers to run `fusebase config ide --force` immediately for all IDE MCP configs; if declined, it prints that command as the next step.

### Configure optional MCP integrations

```bash
fusebase integrations
```

This runs an interactive step to enable/disable optional MCP servers from the CLI integrations catalog and any **custom** HTTP MCP servers listed under `fusebase.json` → `mcpIntegrations.custom`.
`required: true` servers are always enabled when you run this command.

Add a custom MCP by URL (checks reachability with HTTP GET unless `--skip-check`):

```bash
fusebase integrations add <name> --url <url> [--type http] [--token <token>]
<% if (it.flags?.includes("managed-integrations")) { %>
fusebase integrations list-templates   # list Gate MCP manager templates using app .env token
fusebase integrations connect-template --template-name <template-name>
<% } %>
fusebase integrations disable <name>   # keep fusebase.json; remove from IDE configs
fusebase integrations enable <name>
fusebase integrations remove <name>    # or: delete
```

During `fusebase init`, only **required** MCP servers (per the catalog, respecting flags) are written to IDE configs; run `fusebase integrations` afterward to add optional servers.

### Create App Secrets

```bash
fusebase secret create --app <%= it.flags?.includes("declarative-manifest") ? "<appPath>" : "<appId>" %> --secret <KEY:description> [--secret ...]
```

Creates secrets (with empty values) for an app and prints the URL where you can set the actual values.

**Required Options:**

- `--app <%= it.flags?.includes("declarative-manifest") ? "<appPath>" : "<appId>" %>` - <%= it.flags?.includes("declarative-manifest") ? "App path (from `apps[].path` in `fusebase.json`)" : "App ID" %> to create secrets for. `--feature` is accepted as a deprecated alias.
- `--secret <KEY:description>` - Secret to create. Format: `KEY` or `KEY:description`. **Repeatable** — pass multiple `--secret` flags to create several secrets at once.

**Examples:**

```bash
# Create a single secret
fusebase secret create --app <%= it.flags?.includes("declarative-manifest") ? "apps/my-app" : "abc123" %> --secret "API_KEY:Third-party API key"

# Create multiple secrets at once
fusebase secret create --app <%= it.flags?.includes("declarative-manifest") ? "apps/my-app" : "abc123" %> \
  --secret "API_KEY:Third-party API key" \
  --secret "DB_PASSWORD:Database connection password" \
  --secret "WEBHOOK_SECRET"
```

After creating the secrets, the CLI prints `https://{org-domain}/dashboard/{orgId}/apps/apps/{appId}/secrets` — open that URL to fill in the actual secret values.

### Scaffold an App

Scaffold a new app from a built-in template.

```bash
# List available templates (with descriptions)
fusebase scaffold

# Scaffold a template into a directory
fusebase scaffold --template <templateId> --dir <path>
```

Available templates:

| Template | Description |
|----------|-------------|
| `spa` | React + Vite SPA — scaffolds directly into `<dir>` |
| `backend` | Node.js + Hono backend — scaffolds into `<dir>/backend/` |

**Rules:**
- Errors if any files in the target directory would be overwritten (no partial writes).
- The `backend` template can be scaffolded on top of an existing SPA — only the `backend/` subfolder must be absent.

Then implement the app. **After the code is complete**, register and start dev — **execute these automatically, do NOT list them as "next steps" for the user**:

```bash
# Register the app (derive name/subdomain from context)
# add --permissions if dashboard access is needed
fusebase app create \
  --name="<App Name>" \
  --subdomain=<app-sub> \
  --path=apps/<name> \
  --dev-command="npm run dev" \
  --build-command="npm run build" \
  --output-dir=dist \
  --coding-agent=<agent> \
  --model=<model>

# Start the dev server
fusebase dev start apps/<name>
```

### Deploy Apps

```bash
fusebase deploy
```

Deploys all apps to Fusebase:

1. Installs dependencies and runs lint for each app (if the app has a `lint` script in `package.json`)
2. Runs each app's build command
3. Uploads the built files from `outputDir`
4. Activates the new version on Fusebase

Options:

- `--force` — ignore hash matches and re-upload + redeploy every app
- `--app <subdomain|id|name|path>` — deploy only the matching app
- `--nocode` — only reconcile infrastructure (bind/create apps on the platform), skip code deployment

The project template includes ESLint (`npm run lint`) and root `npm run typecheck` (TypeScript across apps — catches errors ESLint does not). Run both before saying "Done" so deploy succeeds; see AGENTS.md "Final Gate". Claude Code runs lint and typecheck on Stop via `.claude/settings.json` hooks.

### Isolated SQL Bundle / RLS Manifest

```bash
fusebase isolated-store sql bundle --app <%= it.flags?.includes("declarative-manifest") ? "<appPath>" : "<appId>" %> [--alias <alias>] [--stage dev|prod] [--json|--status|--dry-run|--apply --yes]
```

Use this for app-owned isolated SQL schema work. It reads `apps[].isolatedStores.sql[]` from `fusebase.json`, loads `postgres/migrations/manifest.json`, and computes Gate-canonical checksums from SQL file bytes.

RLS manifest forwarding is experimental. To attach `rlsManifest` from either `rlsManifestFile`, inline config, manifest `rlsManifest`, or `postgres/migrations/rls-manifest.json`, enable:

```bash
fusebase config set-flag postgres-rls
```

Examples:

```bash
fusebase isolated-store sql bundle --app <%= it.flags?.includes("declarative-manifest") ? "apps/client-portal" : "client-portal" %> --json
fusebase isolated-store sql bundle --app <%= it.flags?.includes("declarative-manifest") ? "apps/client-portal" : "client-portal" %> --stage dev --status
fusebase isolated-store sql bundle --app <%= it.flags?.includes("declarative-manifest") ? "apps/client-portal" : "client-portal" %> --stage dev --dry-run
fusebase isolated-store sql bundle --app <%= it.flags?.includes("declarative-manifest") ? "apps/client-portal" : "client-portal" %> --stage dev --apply --yes
```

Gate calls use `GATE_MCP_TOKEN` from `.env`. Do `--status` and `--dry-run` before any real `--apply`.

### Gate MCP Token Scope

`fusebase env create` writes `GATE_MCP_TOKEN` to `.env`. For current apps-cli projects, the Gate MCP token is created with the project `productId` as its `client` scope, not necessarily with a child `apps[].id`.

When debugging isolated-store access:

- call Gate `me` / `whoami` first and use the actual resolved `client` scope;
- compare that value with the store `sourceScopes`;
- if runtime SQL or migration status/apply fails with `403 Token cannot access isolated store`, check for a missing `sourceScopes` entry before changing migrations;
- if authorized, fix by adding the exact resolved client scope with `attachIsolatedStoreSourceScope`.

Do not attach a guessed child app id when `whoami` shows a different product/client scope. Do not recreate the store or rebaseline migrations just to fix a source-scope mismatch.

### Manage Sidecar Containers

Sidecar containers are pre-built Docker images deployed alongside an app's backend container, sharing the localhost network namespace. Max 3 sidecars per app.

```bash
# Add a sidecar to an app backend
fusebase sidecar add \
  --app <appId> \
  --name <name> \
  --image <image> \
  [--port <port>] \
  [--tier small|medium|large] \
  [--env KEY=VALUE ...] \
  [--secret KEY|KEY:ALIAS ...]

# Remove a sidecar by name
fusebase sidecar remove --app <appId> --name <name>

# List configured sidecars
fusebase sidecar list --app <appId>
```

`--feature` (`-f`) is accepted as a deprecated alias for `--app` (`-a`).

**Options for `sidecar add`:**
- `--name` — unique name within the app (used for log filtering and identification)
- `--image` — Docker image reference (e.g. `browserless/chrome:latest`)
- `--port` — port the sidecar listens on (accessible via localhost from the backend)
- `--tier` — resource tier: `small` (default), `medium`, or `large`
- `--env` — environment variables as KEY=VALUE pairs (repeatable)
- `--secret` — whitelist an app secret key (registered via `fusebase secret create`) to inject into the sidecar as an env var, repeatable. Use `KEY` to expose the secret under its own name, or `KEY:ALIAS` to rename it inside the sidecar. On collision between sidecar `env` and a whitelisted secret key, the sidecar's static `env` value wins. Deploy fails with a `ValidationError` listing every missing key if a referenced secret is not registered for the app. See the **app-sidecar** skill ("Whitelisting Secrets") for details.

Sidecars are stored in `fusebase.json` under `apps[].backend.sidecars[]` and deployed on the next `fusebase deploy`.

<% if (it.flags?.includes("job-sidecars")) { %>**Per-job sidecars (`--job <jobName>`):**

Cron jobs declared under `apps[].backend.jobs[]` deploy as **independent** Azure Container Apps Jobs and do **not** share the backend container app's network namespace. To give a specific cron job its own auxiliary container (e.g. a headless browser used only by a screenshot cron), pass `--job <jobName>` to all three subcommands:

```bash
# Add a sidecar to a job
fusebase sidecar add --app <appId> --job <jobName> \
  --name <name> --image <image> [--port <port>] [--tier ...] [--env ...] [--secret ...]

# Remove a sidecar from a job
fusebase sidecar remove --app <appId> --job <jobName> --name <name>

# List sidecars on a job
fusebase sidecar list --app <appId> --job <jobName>
```

When `--job` is omitted, all three subcommands target backend sidecars exactly as before. Each job has its own 3-sidecar cap, independent of the backend cap. Sidecar names are unique per scope — the same name (e.g. `chromium`) may exist on the backend and on a job. Per-job sidecars are stored under `apps[].backend.jobs[].sidecars[]` in `fusebase.json` and deployed on the next `fusebase deploy`. See the **app-sidecar** skill for full details (networking, termination, examples).
<% } %>

### Remote Logs (Deployed Backends)

Fetch logs from deployed app backends. **Only applicable to apps with a `backend/` folder.** Use this for production issues, NOT for local development (for local dev, see the `dev-debug-logs` skill).

#### Build Logs

```bash
fusebase remote-logs build <appId>
```

Fetch the build image logs from the most recent deployment. Shows the container image build output.

#### Runtime Logs

```bash
fusebase remote-logs runtime <appId> [--tail <number>] [--type <console|system>]
```

Fetch runtime logs from the deployed container.

**Options:**

- `--tail <number>` - Number of log lines to fetch (default: 100, max: 300)
- `--type <console|system>` - Log type: `console` for app output, `system` for container system logs (default: `console`)

**Examples:**

```bash
# Get build logs for an app
fusebase remote-logs build abc123

# Get last 100 runtime console logs
fusebase remote-logs runtime abc123 --tail 100

# Get system logs (container lifecycle events)
fusebase remote-logs runtime abc123 --type system
```

## Creating a New App

1. **Scaffold** the app: `fusebase scaffold --template spa --dir apps/my-new-app` (add `--template backend` for a backend).
2. **Implement the app code** — write all source files, components, and logic.

3. **Register and start dev** — **execute these automatically after the code is written; do NOT list them as "next steps" for the user**:

   a. **Run `fusebase app create`** — include `--permissions` now if the app needs dashboard access (do not save it for a separate `app update` step later):

   ```bash
   # Without dashboard access
   fusebase app create --name="My New App" --subdomain=my-new-app --path=apps/my-new-app --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist --coding-agent=codex --model=gpt-5.4

   # With dashboard view permissions (preferred: set at creation)
   fusebase app create --name="My New App" --subdomain=my-new-app --path=apps/my-new-app --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist --permissions="dashboardView.dash123:view456.read,write" --coding-agent=claude_code --model=opus-4.7

   # With a backend
   fusebase app create --name="My New App" --subdomain=my-new-app --path=apps/my-new-app --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist --backend-dev-command="npm run dev" --backend-build-command="npm run build" --backend-start-command="npm run start" --coding-agent=copilot --model=sonnet-4.6
   ```

   This will create the app on Fusebase and add it to `fusebase.json`

   b. **Run `fusebase dev start`** to test locally

## Updating an Existing App

After changing app code, run `fusebase app update <appId>` if any of these need to be updated:

- `--permissions` — dashboard view access added, removed, or modified
- `--access` — access principals (visitor / org roles) changed
- `--sync-gate-permissions` — always include for apps using `@fusebase/fusebase-gate-sdk` at runtime

<% if (it.flags?.includes("cross-app-api-calls-analysis")) { %>
If runtime code calls other apps via Gate `AppApisApi.callAppApi(...)`, refresh local cross-app dependency metadata and optionally sync it:

```bash
fusebase analyze app-apis --feature <appId>
fusebase analyze app-apis --feature <appId> --sync
# repair/reconciliation mode
fusebase analyze app-apis --feature <appId> --sync --force
```

To author a consumer-contract draft for those resolved dependencies, then verify it centrally:

```bash
fusebase app-api-contracts unresolved --app <appId>
fusebase app-api-contracts add-manual-dependency --app <appId> --provider <providerAppId> --operation <operationId>
fusebase app-api-contracts scaffold --app <appId>
fusebase app-api-contracts validate --app <appId>
fusebase app-api-contracts publish --app <appId>
fusebase app-api-contracts verify-consumer --app <appId>
fusebase app-api-contracts verify-provider --app <providerAppId>
```

Use the unresolved/manual flow when `AppApisApi.callAppApi(...)` is dynamic by design and static analysis cannot resolve the target operation.

Contracts are **authored and validated locally but verified centrally** — there is no local runtime verification command. Recommended flow: `scaffold` + `validate` (offline) while authoring, `publish` the validated contracts, then `verify-consumer` to confirm the published remote set. Run `verify-provider` for an org-wide provider regression check against the target deployed environment; it verifies the currently deployed provider runtime, not unpublished local changes.

`validate` is offline: it checks contract structure and dependency linkage only; it does not call the provider.

`publish` re-validates the consumer app's contracts (same checks as `validate`) and, only when they all pass, uploads the full set to central storage via the public API; the server replaces the stored set, so re-publishing is idempotent.

`verify-consumer --app <consumerAppId>` (optional `--provider`/`--operation`) and `verify-provider --app <providerAppId>` operate on the **published central** contract set, not local files. They call the public API (`POST .../app-api-contracts/verify-consumer` and `.../verify-provider`), which runs the verification engine centrally through Gate. `verify-consumer` covers one consumer's published contracts; `verify-provider` is the org-wide inbound check across every published consumer targeting that provider in the target deployed environment. Because they read the published set and call the deployed provider runtime, run `publish` after editing local contracts before re-verifying, and run `verify-provider` only after the provider version you want to check is deployed to that environment.

`validate`, `verify-consumer`, and `verify-provider` accept `--json` for machine-readable output in CI: human/colored output is suppressed, a single JSON document is printed to stdout, and a top-level `ok` flag mirrors the process exit code. `publish` is an action (not a check) and has no `--json` report; branch on its exit code.
<% } %>

```bash
# Update permissions and sync Gate permissions
fusebase app update <appId> --permissions="dashboardView.dash1:view1.read,write" --sync-gate-permissions
```

### List Portal Embeds

```bash
fusebase app portal-embeds <appId>
```

Lists portal pages in the current org where the app is embedded. Output includes portal name, page title when available, and URL. Empty results print `No portal embeds found for this app.`.

## Typical Workflow

1. `fusebase auth` - Authenticate (one-time setup)
2. `fusebase init` - Initialize project
3. `fusebase scaffold --template spa --dir apps/<name>` - Scaffold app files (dependencies are installed automatically)
3a. Implement the app code
4. *(after code is written)* `fusebase app create --name="App Name" --subdomain=app-name --path=apps/app-name --dev-command="npm run dev" --build-command="npm run build" --output-dir=dist [--permissions="..."]` `[--coding-agent=<agent> --model=<model>]` - Register app; **include `--permissions` at this step** if the app needs dashboard access. **Always include `--coding-agent` and `--model`.** **Execute automatically — do NOT list as next steps for the user.**
4a. *(after registering)* `fusebase dev start` - Start dev and test locally. **Execute automatically.**
5. *(if app settings changed)* `fusebase app update <appId> [--permissions="..."] [--sync-gate-permissions]` - Sync updated settings before deploying
6. `fusebase deploy` - Deploy to production
7. `fusebase remote-logs build|runtime <appId>` - Check logs if deployed app has issues (see `remote-logs` skill for more)

## Troubleshooting

### "Not authenticated" error

Run `fusebase auth` to set your API credentials.

### App not showing in dev server

Ensure the app is:

- Registered via `fusebase app create` (so it exists in Fusebase and `fusebase.json`)
- Added to `fusebase.json` with correct `id`
- Has a running dev server (the `dev.command` process is up)

### Build fails during deploy

Check that:

- `npm run lint` passes in the app directory (deploy runs lint before build)
- `npm run typecheck` passes from project root (or fix TypeScript errors from the app’s `tsc` step — ESLint alone may not report them)
- `build.command` is correct
- `build.outputDir` exists after build
- All dependencies are installed in the app directory (`npm install --include=dev`)
