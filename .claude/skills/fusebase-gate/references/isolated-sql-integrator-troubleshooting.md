---
version: "1.0.0"
mcp_prompt: none
source: "docs/isolated-sql-integrator-troubleshooting.md"
last_synced: "2026-07-01"
title: "FuseBase PostgreSQL Database — integrator troubleshooting"
category: specialized
---
# FuseBase PostgreSQL Database — integrator troubleshooting

> **SOURCE**: This file is copied from `docs/isolated-sql-integrator-troubleshooting.md` in the fusebase-gate repo. Edit that file, then run `npm run mcp:skills:generate`.

---
# FuseBase PostgreSQL Database — integrator troubleshooting

> **Audience:** app developers and coding agents building on Gate isolated SQL stores.
> **Not for operators:** platform Postgres role grants, ownership transfer, and bootstrap scripts are internal. If an environment needs platform alignment, contact Fusebase support — do not instruct users to run operator commands.

Use this guide when runtime SQL, migrations, or RLS behave unexpectedly. Pair with MCP prompt **`isolatedSql`**, **`isolated-sql-migration-discipline`**, and **`getIsolatedStoreSqlRlsStatus`**.

---

## Before you escalate

Collect (no secrets):

- **`orgId`**, **`storeId`**, **`stage`** (`dev` | `prod`)
- Gate **`errorCode`** / HTTP status from the failing call
- Raw Postgres message if present (one line)
- App token **permissions** relevant to isolated stores (`isolated_store.read`, `isolated_store.data.write`, `isolated_store.schema.write`, `isolated_store.rls.delegate`, `isolated_store.rls.bypass`)
- Output of **`getIsolatedStoreSqlRlsStatus`** (`bypassRls`, `superuser`, `currentUser` — diagnostic only)

**Do not** tell users to run platform bootstrap scripts, change Postgres roles, or transfer table ownership.

---

## Symptom → likely cause → what to do

| Symptom                                                                      | Likely cause                                                             | App-side checks                                                                                                                                                         | Contact support when                                                                                            |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `permission denied for table …` on **data** APIs                             | Missing token permission; wrong stage; RLS policy blocks row             | Confirm token includes `isolated_store.data.write` / `read`; same `stage` as data; policy `USING` matches runtime context (`app.org_id`, portal scope, custom settings) | Token and policies look correct but error persists on simple `SELECT`/`INSERT`                                  |
| Empty UI / zero rows but Studio shows data                                   | Wrong **stage**; RLS filters all rows; visitor token without store perms | `dev` vs `prod`; probe with scoped backend + `trustedRuntimeContext`; visitor flows need service backend                                                                | Confirmed correct stage + backend token + policies still return zero rows unexpectedly                          |
| `401` / `403` on store APIs                                                  | App token missing isolated-store permissions or wrong auth path          | `fusebase feature update --sync-gate-permissions`; backend uses `x-app-feature-token`; redeploy after manifest change                                                   | Permissions synced and redeployed; still denied                                                                 |
| `must be owner of table …` on **migration apply**                            | Platform store schema posture (not fixable in app SQL)                   | Do not hand-edit ownership in migrations                                                                                                                                | Always — include `storeId`, `stage`, migration `version`                                                        |
| `409` + drift / `structuredIssues` on status or apply                        | Journal vs bundle mismatch; parallel edits                               | Re-run status with bundle from `postgres/migrations/`; follow migration discipline prompt                                                                               | Drift recovery unclear after following discipline                                                               |
| `getIsolatedStoreSqlRlsStatus`: **`bypassRls=true`** or **`superuser=true`** | Runtime DB role not subject to RLS on this environment                   | Label env **“policies not enforced”**; use explicit filters in backend until native RLS is active; do not claim row-level security works                                | Product requires enforced RLS on this stage and status stays `bypassRls=true` after platform confirms readiness |
| `INSERT … RETURNING` / structured insert with `returning` returns nothing    | RLS `SELECT` policy hides new row until follow-up insert                 | Generate id in app; insert without `returning`; fix policy matrix                                                                                                       | —                                                                                                               |
| Policies exist but admin cannot `DELETE`/`UPDATE`                            | Admin context does not satisfy table `USING`                             | Add explicit admin branch to policies                                                                                                                                   | —                                                                                                               |
| `Invalid token resourceScope` (dashboard, not SQL)                           | Unrelated to SQL store — token scope mismatch                            | See Gate authz / feature permissions                                                                                                                                    | —                                                                                                               |

---

## RLS status (app interpretation)

- **`bypassRls=false`** and **`superuser=false`**: PostgreSQL can enforce policies on the active runtime connection — proceed with policy design and scoped tests.
- **`bypassRls=true`**: Policies may appear in catalog introspection but **will not filter** runtime reads/writes. Treat as environment limitation; use backend filtering for demos or wait for platform confirmation.
- **`rlsContext`** sets transaction-local settings only; it does not replace policies or token permissions.

---

## Support message template (copy for users)

```
Store: <storeId>
Stage: dev|prod
Operation: <e.g. selectIsolatedStoreSqlRows / applyIsolatedStoreSqlMigrations>
HTTP/status: <code>
Gate errorCode: <if any>
Postgres hint: <one line>
Token permissions (isolated_store.*): <list>
getIsolatedStoreSqlRlsStatus: bypassRls=…, superuser=…
```

Ask platform to **verify store runtime readiness** — not to paste internal bootstrap commands.

---

## Related docs (app-facing)

| Topic                        | Where                                                         |
| ---------------------------- | ------------------------------------------------------------- |
| MCP / SDK sequence           | MCP prompt `isolatedSql` → skill `references/isolated-sql.md` |
| Migration journal discipline | `references/isolated-sql-migration-discipline.md`             |
| Portal embed scope           | `references/portal-embed-context.md`                          |

Operator runbooks (`isolated-sql-stores.md`, `isolated-postgres-azure-operations.md`, `isolated-sql-rls-plan.md`) are for platform staff only.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-07-01
