---
name: app-sidecar
description: "Guide for managing sidecar containers alongside app backends. Use when: (1) An app backend needs auxiliary services like headless browsers, caches, or other tools, (2) Adding/removing/listing sidecar containers, (3) Configuring sidecar networking, env vars, or resource tiers."
---

# App Sidecar Containers

Sidecars are pre-built Docker images deployed alongside an app backend in the same network namespace (sharing localhost). They enable auxiliary services that the backend communicates with over HTTP or other protocols on localhost.

## Prerequisites

1. App must have a `backend/` folder configured in `fusebase.json`

## Use Cases

| Sidecar | Image Example | Port | Purpose |
|---------|---------------|------|---------|
| Headless browser | `browserless/chrome:latest` | 9222 | Web scraping, PDF generation, screenshots |
| Lightweight browser | `nicholasgriffintn/lightpanda:latest` | 9222 | Fast page parsing |
| Redis cache | `redis:7-alpine` | 6379 | Caching, queues, pub/sub |
| Image processor | `dpokidov/imageproxy:latest` | 8080 | Image resizing/optimization |

## CLI Commands

### Add a Sidecar

```bash
fusebase sidecar add \
  --app <appId> \
  --name <name> \
  --image <dockerImage> \
  [--port <port>] \
  [--tier small|medium|large] \
  [--env KEY=VALUE ...] \
  [--secret KEY|KEY:ALIAS ...]
```

Example:

```bash
fusebase sidecar add \
  --app my-scraper \
  --name chromium \
  --image browserless/chrome:latest \
  --port 9222 \
  --tier medium \
  --env MAX_CONCURRENT_SESSIONS=5 \
  --env CONNECTION_TIMEOUT=30000
```

### Remove a Sidecar

```bash
fusebase sidecar remove --app <appId> --name <name>
```

### List Sidecars

```bash
fusebase sidecar list --app <appId>
```

`--feature` (`-f`) is accepted as a deprecated alias for `--app` (`-a`).

## Whitelisting Secrets

By default, app secrets registered via `fusebase secret create` are injected only into the main backend container (and into cron job containers). Sidecars receive **no** app secrets unless you explicitly whitelist the keys you want each sidecar to see.

Use the repeatable `--secret` option on `fusebase sidecar add` to opt in:

```bash
# Inject the secret as an env var with the same name (DB_PASSWORD)
fusebase sidecar add --app my-scraper --name redis \
  --image redis:7-alpine \
  --secret DB_PASSWORD

# Inject the secret under a different env var name inside the sidecar
# (sidecar sees REDIS_AUTH_TOKEN; the underlying secret remains DB_PASSWORD)
fusebase sidecar add --app my-scraper --name redis \
  --image redis:7-alpine \
  --secret DB_PASSWORD:REDIS_AUTH_TOKEN
```

### Source

Secrets must be **registered** with the app beforehand (or alongside) via:

```bash
fusebase secret create --app <appId> --secret "DB_PASSWORD:Redis auth"
```

Set the actual values in the FuseBase web UI (the URL is printed by `secret create`). Only registered keys may be referenced from `--secret`. See the **app-secrets** skill for the full secret lifecycle.

### Forms

| Form | Stored as | Result inside the sidecar |
|------|-----------|---------------------------|
| `--secret KEY` | string `"KEY"` in `secrets[]` | env var `KEY` = secret value |
| `--secret KEY:ALIAS` | object `{ from: "KEY", as: "ALIAS" }` | env var `ALIAS` = secret value |

Both forms can be mixed in the same sidecar's `secrets` array.

### Validation Rules

- **CLI fail-fast** (during `sidecar add`):
  - empty `KEY` or `ALIAS` is rejected;
  - duplicate target env var name within the same sidecar is rejected (target = `ALIAS` if present, else `KEY`).
- **Deploy-time strict validation** (during `fusebase deploy`): if any referenced secret key is not registered for the app, the API returns a `ValidationError` listing **all** missing keys at once and **no** Azure resources are touched.
- **`env` overrides on collision**: a sidecar may legitimately list the same key in both `--env KEY=VALUE` and `--secret KEY` (`fusebase sidecar add` does not reject this). At deploy time the sidecar's static `env` value wins; the secret value is shadowed for that key only.

### Scope

`--secret` works the same way for backend sidecars and per-job sidecars (`--job <jobName>`). Each sidecar maintains its own independent allowlist — sidecars never share secrets with one another or with the backend.

## Configuration Format

Sidecars are stored in `fusebase.json` under each app's `backend.sidecars` array:

```json
{
  "apps": [
    {
      "id": "my-scraper",
      "path": "apps/my-scraper",
      "backend": {
        "dev": { "command": "npm run dev" },
        "build": { "command": "npm run build" },
        "start": { "command": "npm run start" },
        "sidecars": [
          {
            "name": "chromium",
            "image": "browserless/chrome:latest",
            "port": 9222,
            "tier": "medium",
            "env": {
              "MAX_CONCURRENT_SESSIONS": "5"
            },
            "secrets": [
              "BROWSERLESS_TOKEN",
              { "from": "DB_PASSWORD", "as": "REDIS_AUTH_TOKEN" }
            ]
          }
        ]
      }
    }
  ]
}
```

## Networking

Sidecars share the backend's network namespace — all containers communicate via `localhost`:

```typescript
// Backend code calling a sidecar
const browser = await fetch("http://localhost:9222/json/version");
const redis = await fetch("http://localhost:6379");
```

Each sidecar should expose a different port. The `port` field is informational for documentation; the actual port is determined by the sidecar image configuration.

**Port 3000 is reserved for the backend app** — do not configure sidecars to listen on port 3000. If a sidecar image defaults to port 3000 (e.g. `browserless/chrome`), override it via environment variables. For example, browserless uses `PORT` env var:

```bash
fusebase sidecar add --app my-scraper --name chromium \
  --image browserless/chrome:latest --port 9222 \
  --env PORT=9222
```

## Resource Tiers

Each sidecar can have its own resource tier:

| Tier | CPU | Memory |
|------|-----|--------|
| small | 0.5 | 1Gi |
| medium | 1 | 2Gi |
| large | 2 | 4Gi |

Default tier is `small` if not specified. Choose based on the sidecar's workload — headless browsers typically need `medium` or `large`.

> ⚠️ Total CPU/memory across the backend (small tier: 0.5 / 1 Gi) + all sidecars must stay within **2.0 CPU / 4.0 Gi** (Azure Container Apps limit). See the **Total Resource Budget** section in the `app-backend` skill.

Worked examples (numbers match the `app-backend` skill):

- backend (small) + chromium (medium) + redis (small) = 2.0 CPU / 4.0 Gi ✓
- backend (small) + chromium (medium) + lightpanda (medium) = 2.5 CPU / 5 Gi ✗ → Azure rejects deploy, downgrade one sidecar to small.

Cron jobs are **excluded** from this budget — each cron job runs as its own container.

## Environment Variables

Sidecar env vars are isolated — they are NOT shared with the backend or other sidecars. Use them for sidecar-specific configuration:

```bash
fusebase sidecar add --app my-app --name redis --image redis:7 \
  --env REDIS_MAXMEMORY=256mb --env REDIS_MAXMEMORY_POLICY=allkeys-lru
```

App secrets (registered via `fusebase secret create`) are **not** injected into sidecars by default. To grant a sidecar access to specific secrets, whitelist them with `--secret` on `fusebase sidecar add` (see [Whitelisting Secrets](#whitelisting-secrets) above). On collision between a sidecar's `env` and a whitelisted secret with the same env var name, the static `env` value wins.

## Limitations

- **Max 3 sidecars per app** — enforced by the CLI and API
- **Pre-built images only** — sidecars use existing Docker images, no custom builds from source
- **Sidecar names must be unique** within an app
- **Sidecars do not run locally** — `fusebase dev start` does not start sidecar containers. For local development, run the sidecar image manually with Docker
- **Port 3000 is reserved** — the backend app listens on port 3000; sidecars must not bind to it or they will crash with `EADDRINUSE`
- **No shared volumes** — sidecars and backend communicate only via network

## Debugging

### View All Container Logs

```bash
fusebase remote-logs runtime <appId>
```

Output includes logs from all containers, prefixed by name:

```
[api]: Server started on port 3000
[chromium]: Browser ready on port 9222
```

### Filter to a Specific Container

```bash
# Backend logs only
fusebase remote-logs runtime <appId> --container api

# Specific sidecar
fusebase remote-logs runtime <appId> --container chromium
```

### Sidecar Not Available

If a sidecar fails to start, logs will show:

```
[chromium]: (sidecar not available)
```

Check the system logs for container startup issues:

```bash
fusebase remote-logs runtime <appId> --type system
```

## Deployment

Sidecars are deployed automatically with `fusebase deploy`. The CLI reads the sidecar config from `fusebase.json` and passes it to the deploy API. No additional steps are needed.

```bash
fusebase deploy
# Output includes:
# Deploying app "my-scraper" with sidecars: chromium
```
<% if (it.flags?.includes("job-sidecars")) { %>

## Job Sidecars

Cron jobs (declared under `apps[].backend.jobs[]`) are deployed as **separate Azure Container Apps Jobs**, not as part of the backend container app. They do **not** share the backend's network namespace, so a job cannot reach the backend's sidecars on `localhost`.

To give a job its own auxiliary container (for example a headless browser used only by a screenshot cron), declare sidecars **on the job**.

### Add a Sidecar to a Job

```bash
fusebase sidecar add \
  --app <appId> \
  --job <jobName> \
  --name <name> \
  --image <dockerImage> \
  [--port <port>] \
  [--tier small|medium|large] \
  [--env KEY=VALUE ...]
```

Example — give a `screenshots` cron its own headless browser:

```bash
fusebase sidecar add \
  --app my-scraper \
  --job screenshots \
  --name chromium \
  --image browserless/chrome:latest \
  --port 9222 \
  --tier medium \
  --env PORT=9222
```

`--job` works the same way for `remove` and `list`:

```bash
fusebase sidecar remove --app my-scraper --job screenshots --name chromium
fusebase sidecar list --app my-scraper --job screenshots
```

When `--job` is omitted, all three subcommands target backend sidecars exactly as before.

### Configuration Format

Job sidecars live under each job entry in `fusebase.json`:

```json
{
  "apps": [
    {
      "id": "my-scraper",
      "backend": {
        "jobs": [
          {
            "name": "screenshots",
            "type": "cron",
            "cron": "*/1 * * * *",
            "command": "npm run cron:screenshots",
            "sidecars": [
              {
                "name": "chromium",
                "image": "browserless/chrome:latest",
                "port": 9222,
                "tier": "medium",
                "env": { "PORT": "9222" }
              }
            ]
          }
        ]
      }
    }
  ]
}
```

### Networking and Scope

- Each cron job replica runs as an independent Azure Container Apps Job. Its sidecars share the network namespace of **that job replica only** — they are reachable on `localhost:<port>` from the job's main container.
- Job sidecars are isolated from the backend container app's sidecars and from sidecars in other jobs.
- Sidecar names are unique **within a scope**. The same name (e.g. `chromium`) may exist on the backend and on a job — they are separate containers in separate replicas.

### Per-Job Limits

- Each job has its own **3-sidecar cap**, independent of the backend's cap.
- The backend can still have up to 3 sidecars; each job can add up to 3 more on top of that.

### Termination Semantics

Azure Container Apps Jobs determine replica completion from the **main job container's exit**. When the main container exits, the replica is torn down and any non-exiting sidecars (headless browsers, Redis, etc.) are killed with it. No custom shutdown logic is needed in the sidecar.

If the main job container is still running at `replicaTimeout=3600s` (1 hour, fixed), Azure kills the replica regardless. Plan job logic to finish well within that ceiling.

### Example: Screenshots Cron with Headless Browser

The cron's main container runs `npm run cron:screenshots`, which does its work against `http://localhost:9222` exposed by the `chromium` sidecar:

```typescript
// backend/src/jobs/screenshots.ts
async function main() {
  const res = await fetch("http://localhost:9222/screenshot", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ url: "https://example.com" }),
  });
  if (!res.ok) throw new Error(`screenshot failed: ${res.status}`);
  // ... handle screenshot bytes ...
  process.exit(0);
}

main().catch((err) => {
  console.error("[screenshots] Failed:", err);
  process.exit(1);
});
```

When `process.exit(0)` runs, the replica completes and `chromium` is torn down with it.

### Local Dev

`fusebase dev start` does **not** start cron jobs nor any sidecars (backend or job). Job sidecars take effect only after `fusebase deploy`.
<% } %>

## Checklist

- [ ] App has a `backend/` folder and `backend` block in `fusebase.json`
- [ ] Added sidecar(s) via `fusebase sidecar add`
- [ ] Verified sidecar count is at most 3
- [ ] Backend code uses `localhost:<port>` to communicate with sidecars
- [ ] Tested sidecar locally with Docker (optional but recommended)
- [ ] Deployed and verified with `fusebase remote-logs runtime`
- [ ] Total CPU/memory = backend (small, 0.5/1 Gi) + Σ sidecar tiers ≤ 2 CPU / 4 Gi (Azure cap)
<% if (it.flags?.includes("job-sidecars")) { %>
- [ ] If a cron job needs an auxiliary container, attached sidecars to the **job** (not the backend) using `fusebase sidecar add --job <jobName>`
- [ ] Verified job sidecar count is at most 3 per job (independent of backend cap)
<% } %>
