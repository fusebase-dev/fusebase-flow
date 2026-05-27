---
name: app-secrets
description: "Guide for creating and using secrets in Fusebase Apps app backends. Use when: (1) An app backend needs API keys, passwords, or other sensitive config, (2) Creating secrets via the CLI, (3) Accessing secrets at runtime in backend code, (4) Deciding what should be a secret vs. a regular env var."
---

# App Secrets

Secrets are encrypted key-value pairs stored in Fusebase and injected into the app backend at runtime as environment variables. Use them for sensitive config that must not be committed to source control (API keys, passwords, tokens, etc.).

**Secrets are only available in the app server** (`backend/` directory). They are NOT accessible in the browser/SPA — never try to read secrets from the frontend.

## Creating Secrets

Use the CLI to register secret keys (values are set on the FuseBase website):

```bash
fusebase secret create --app <appId> --secret "KEY:description" [--secret ...]
```

- `appId` — get it from `fusebase.json` (`apps[].id`); `--feature` is accepted as a deprecated alias for `--app`
- Each `--secret` is `KEY` or `KEY:human-readable description`
- Pass multiple `--secret` flags to create several secrets at once
- After running, the CLI prints the URL where you can fill in the actual values

**Examples:**

```bash
# Single secret
fusebase secret create --app abc123 --secret "OPENAI_API_KEY:OpenAI API key"

# Multiple secrets at once
fusebase secret create --app abc123 \
  --secret "STRIPE_SECRET_KEY:Stripe secret key" \
  --secret "DB_PASSWORD:Database connection password" \
  --secret "WEBHOOK_SECRET:Webhook signing secret"
```

After running, open the printed URL and fill in the secret values.

## Accessing Secrets at Runtime

Secrets are injected as environment variables into the app backend process. Read them via `process.env`:

```typescript
// backend/src/index.ts or any backend file
const apiKey = process.env.OPENAI_API_KEY
if (!apiKey) {
  throw new Error('OPENAI_API_KEY is not set')
}
```

Validate required secrets at backend startup so the backend fails fast with a clear error rather than failing silently on the first request:

```typescript
// backend/src/config.ts
function requireEnv(key: string): string {
  const value = process.env[key]
  if (!value) throw new Error(`Missing required environment variable: ${key}`)
  return value
}

export const config = {
  openaiApiKey: requireEnv('OPENAI_API_KEY'),
  stripeSecretKey: requireEnv('STRIPE_SECRET_KEY'),
}
```

## Local Development

`fusebase dev start` **downloads secrets from Fusebase** and injects them into the backend process as environment variables — **the exact same secrets used in production**. There is **no need** for a `.env` file or the `dotenv` package.

- ❌ Do NOT create a `backend/.env` file for secrets
- ❌ Do NOT add `dotenv` as a dependency
- ❌ Do NOT use `import 'dotenv/config'` in backend code
- ✅ Use `fusebase secret create` to register secrets, set values via the printed URL, and they will be available via `process.env` in both dev and production

## Runtime Persistence

Secrets are **read-only** at runtime — the backend cannot update secret values programmatically. They are set via the CLI or the Fusebase web UI.

Secrets (env vars) are best for **shared, deploy-time credentials** (API keys, service-account tokens). They are **not suitable** for per-user or dynamically obtained tokens because they cannot be written at runtime and the backend is stateless (no filesystem, no in-memory persistence across restarts).

**For per-user credentials obtained at runtime** (e.g. OAuth refresh tokens from a callback), use **httpOnly cookies** instead — see skill **app-backend**, "Stateless Backend" section. The cookie is sent by the browser on every request; the backend reads it and stays stateless. The env-var secret can serve as a fallback.


## Checklist

- [ ] `fusebase secret create` run with all required keys and descriptions
- [ ] Secret values filled in via the app secret manager on the FuseBase website
- [ ] Secrets validated at backend startup (fail fast with a clear error)
- [ ] No `backend/.env` file — secrets are injected by `fusebase dev start` automatically
- [ ] No `dotenv` dependency in backend code
- [ ] No secrets referenced in SPA/browser code