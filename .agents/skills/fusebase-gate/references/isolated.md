---
version: "1.3.0"
mcp_prompt: isolated
last_synced: "2026-05-08"
title: "FuseBase PostgreSQL Database"
category: specialized
---
# FuseBase PostgreSQL Database

> **MARKER**: `mcp-isolated-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `isolated` for latest content.

---
## FuseBase PostgreSQL Database

These prompts cover the common control-plane model for FuseBase PostgreSQL Database, implemented through the Gate `isolated-stores` contract.

## Core Model

- A FuseBase PostgreSQL Database is a logical app-owned SQL database.
- Internally, this product surface uses the Gate `isolated-stores` domain and opIds.
- A store belongs to an org and to a source scope such as `app`.
- Each store has stage instances such as `prod` and `dev`.
- Each stage instance binds to its own physical database.
- Revisions and checkpoints are attached to a stage instance, not to the whole store.

## Working Flow

1. Create the PostgreSQL database store.
2. Initialize a stage such as `prod` or `dev`.
3. Use SQL tools for `sql/postgres` stores.
4. Create checkpoints before risky changes.
5. Restore a revision only when the revision has a physical `file://` snapshot.
6. Use store stats operations when you need database-level summaries instead of per-table calls.

## Access Rules

- Always send `orgId`, `storeId`, and `stage` exactly as returned by previous operations.
- Treat hardcoded `storeId` values in external app code, env files, or app secrets as an anti-pattern.
- Resolve the target store at runtime via `listIsolatedStores` with `clientId`, then filter by stable app-level `alias` (or `aliasLike`) and use the returned `storeId`.
- Persist app-owned alias and client binding (`clientId`) as configuration; do not persist provider/runtime store ids as long-lived app secrets.
- `listIsolatedStores` accepts optional query `clientId` to narrow stores by `app` source scope `sourceId`; token callers must use their own client scope id when setting it.
- **Empty `listIsolatedStores`** is expected until at least one `createIsolatedStore` for that `orgId`. Flow: create store → `initIsolatedStoreStage` (`dev` / `prod`) → then PostgreSQL SQL ops. If the list stays empty after create, check **wrong `orgId`**, or **`clientId` filter** (omit the query to list all org stores, or pass the exact app client id matching the store’s `source.sourceId`).
- Token control-plane ownership is checked through the `client` scope of the token.
- Runtime access can also be narrowed by `resourceScope` on `isolated_store_stage_instance`.

### Source scope quick table

- `listIsolatedStores({ orgId })` -> lists all stores visible to the org-scoped caller.
- `listIsolatedStores({ orgId, clientId: <matching appId> })` -> lists only stores whose app source scope matches that exact app id.
- `listIsolatedStores({ orgId, clientId: <different appId> })` -> empty list is expected.
- Feature token from a different app must not see or manage the store through app-scoped ownership.
- Heuristic: store visible without `clientId` but missing with `clientId` -> wrong app binding or wrong client id filter. Missing in both cases -> check wrong `orgId`, token scope, or registry state before assuming deletion.

## Stage Rules

- Default stage is `prod` when stage is omitted by higher-level orchestration.
- `dev` and `prod` are separate stage instances with separate physical databases.
- Do not assume data written to `dev` exists in `prod`.
- **SQL schema:** follow the **`isolatedSql`** prompt and repo **`docs/isolated-sql-stores.md`** (status → optional dryRun → apply). Load **`isolatedSqlMigrationDiscipline`** before editing migration bundles.
- Use `listIsolatedStoreStages` and `listIsolatedStoreRevisions` to inspect the current state before restore flows.
- Revision `metadata.snapshotStats` can contain preview stats captured at checkpoint time.
- For SQL checkpoints, revision `metadata.snapshotMigrations` can also capture the stage migration journal head and applied migration list at checkpoint time.

## Tool Selection

- For database store or stage lifecycle, use the generic isolated store operations.
- For `sql/postgres`, load the `isolatedSql` prompt group and prefer structured row operations before raw SQL.
- For database-level summaries, prefer `getIsolatedStoreSqlStats` over manually stitching list/describe/count calls.

## UI deep links (store view)

- Store page template: `https://<org-subdomain>.<fusebase-domain>/studio/<org-ui-id>/isolated-stores/<store-type>/<store-id>`.
- Replace placeholders with real values: org subdomain and fusebase domain, org UI id, store type (`sql`), and store id.
- SQL table view adds query param: `?table=<schema.table_name>` (example: `?table=public.fusebase_schema_migrations`).
- After creating a store or creating a SQL table through MCP, suggest opening the matching UI link for quick verification.

## SQL schema hard gate

- For isolated SQL schema changes, enforce file-first order: `postgres/migrations/` file update -> checksum from file -> status -> apply.
- Inline SQL in MCP is only for one-off smoke/dev tests and must be marked temporary.
- Do not mark work done if schema changed but no matching new/updated migration file and manifest entry exists under `postgres/migrations/`.
- After schema ops, include artifact fields: migration file path, `version`, `name`, `checksum`, `storeId`, `stage`.

## MCP workflow (chat-driven tool_call)

- Isolated store operations declare `requiredPrompts` / prompt groups. Before the first domain calls, run `prompts_search` with the groups listed on `tools_describe` for that operation (commonly `authz`, `sdk`, `isolated`, and for SQL also `isolatedSql`).
- Discovery: `tools_search` takes `queries` as an array of strings (1–10). Do not send a singular `query` field — input validation will fail.
- Transient Gate errors (`fetch failed`, unreachable internal host) are worth retrying once or twice before treating the environment as down.

## Stage lifecycle

- To remove the entire store (all stages plus registry row), use `deleteIsolatedStore` on `/:orgId/isolated-stores/:storeId` instead of deleting each stage manually.
- After `deleteIsolatedStoreStage`, the stage disappears from `listIsolatedStoreStages`. Recreate it with `initIsolatedStoreStage` using the same `stage` name.
---

## Version

- **Version**: 1.3.0
- **Category**: specialized
- **Last synced**: 2026-05-08
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
