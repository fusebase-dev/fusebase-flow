---
name: remote-logs
description: "Use when debugging a deployed app backend. Explains how to fetch build logs and runtime logs using the `fusebase remote-logs` command. Only applicable to apps with a backend/ folder. For local development, use dev-debug-logs skill instead."
---

# Remote Logs

**This skill applies only to apps with a `backend/` folder.** Frontend-only apps do not produce remote logs.

When an app backend has been deployed using `fusebase deploy`, you can fetch logs from the cloud:

1. **Build logs** - Output from the container image build process
2. **Runtime logs** - Live stdout/stderr and system logs from the running backend

## Important Distinction

| Context | Command | What It Reads |
|---------|---------|---------------|
| **Local development** | `fusebase dev start` | Log files in `<app>/logs/dev-*/` |
| **Deployed backend** | `fusebase remote-logs` | Cloud build and runtime logs |

If the app is running locally via `fusebase dev start`, use the **dev-debug-logs** skill instead.

## Commands

### Build Logs

Fetch build/deployment logs from the most recent deploy:

```bash
fusebase remote-logs build <appId>
```

Output includes:
- Build status (`in_progress`, `failed`, `finished`)
- Full build log (Dockerfile execution, npm install, etc.)
- Deploy job ID for reference

### Runtime Logs

Fetch live logs from the running backend:

```bash
# Default: last 100 console (stdout/stderr) entries
fusebase remote-logs runtime <appId>

# Specify tail count (0-300)
fusebase remote-logs runtime <appId> --tail 200

# Get system logs instead of console logs
fusebase remote-logs runtime <appId> --type system

# Filter to a specific container (backend or sidecar)
fusebase remote-logs runtime <appId> --container api
fusebase remote-logs runtime <appId> --container my-sidecar
```

Options:
- `--tail <n>` - Number of log entries (0-300, default: 100)
- `--type <type>` - Log type: `console` (stdout/stderr) or `system` (service/infrastructure logs)
- `--container <name>` - Filter logs to a specific container. Use `api` for the main backend, or the sidecar name for sidecar containers

### Log Format with Sidecars

When an app backend has sidecar containers, runtime logs include output from all containers. Each log line is prefixed with the container name:

```
[api]: Backend server started on port 3000
[api]: GET /health 200
[chromium]: Browser ready on port 9222
[chromium]: New page created
```

Use `--container` to filter to a single container output:

```bash
# Show only sidecar logs
fusebase remote-logs runtime <appId> --container chromium

# Show only backend logs
fusebase remote-logs runtime <appId> --container api
```

## When to Use Each Log Type

### Build Logs

Use for:
- Failed deployments (`status: failed`)
- Dockerfile issues
- npm install failures
- Build-time errors and warnings
- Deployment timing issues

### Runtime Logs (console)

Use for:
- Application startup errors
- HTTP request handling issues
- Unhandled exceptions/rejections
- `console.log` debug output from the backend
- Server crash diagnostics
- Sidecar container output (prefixed by container name)

### Runtime Logs (system)

Use for:
- Container health check failures
- Container restart events
- Resource limits (CPU/memory) issues
- Infrastructure events
- Networking/ingress problems

## Prerequisites

1. App **must have a `backend/` folder** — frontend-only apps do not produce remote logs
2. App must be deployed via `fusebase deploy`
3. Deployment must have completed successfully (for runtime logs)
4. API key configured via `fusebase auth`

## Error Messages

| Error | Meaning | Fix |
|-------|---------|-----|
| "No deploy found for App" | App has never been deployed | Run `fusebase deploy` first |
| "No successful deploy found" | Latest deploy failed | Check build logs, fix, redeploy |
| "Missing resource information" | Deploy metadata incomplete | Redeploy the app |

## Example Debug Flow

1. Deploy fails → Check build logs:
   ```bash
   fusebase remote-logs build
   ```

2. App crashes on startup → Check runtime console logs:
   ```bash
   fusebase remote-logs runtime --tail 50
   ```

3. Container keeps restarting → Check system logs:
   ```bash
   fusebase remote-logs runtime --type system
   ```

4. No obvious errors → Check more log entries:
   ```bash
   fusebase remote-logs runtime --tail 300
   ```

5. Sidecar misbehaving -> Check sidecar-specific logs:
   ```bash
   fusebase remote-logs runtime <appId> --container my-sidecar --tail 200
   ```
