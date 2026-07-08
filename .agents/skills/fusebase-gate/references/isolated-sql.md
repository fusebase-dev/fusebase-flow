---
version: "1.9.0"
mcp_prompt: isolatedSql
last_synced: "2026-07-01"
title: "FuseBase PostgreSQL Database"
category: specialized
---
# FuseBase PostgreSQL Database

> **MARKER**: `mcp-isolated-sql-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `isolatedSql` for latest content.

---
## Table of contents

- [FuseBase PostgreSQL Database (`sql` / `postgres`)](#fusebase-postgresql-database-sql--postgres)
  - [Canonical docs (app integrators)](#canonical-docs-app-integrators)
  - [Before migration work](#before-migration-work)
  - [Standard sequence (schema + store)](#standard-sequence-schema--store)
  - [Data path (no DDL)](#data-path-no-ddl)
  - [Structured SQL limits](#structured-sql-limits)
  - [MCP bundle size](#mcp-bundle-size)
  - [Tokens](#tokens)
  - [PostgreSQL RLS native mode](#postgresql-rls-native-mode)
  - [Troubleshooting (user-facing — no operator commands)](#troubleshooting-user-facing--no-operator-commands)
  - [RLS app-design pitfalls from QA](#rls-app-design-pitfalls-from-qa)
  - [After a failed apply](#after-a-failed-apply)
  - [Managed PostgreSQL (Azure, etc.)](#managed-postgresql-azure-etc)
  - [`executeIsolatedStoreSql` pitfalls](#executeisolatedstoresql-pitfalls)
  - [Version 1 discipline](#version-1-discipline)
  - [Discovery](#discovery)
  - [Manifest / checksums](#manifest--checksums)
  - [UI links (store and table)](#ui-links-store-and-table)

---
## FuseBase PostgreSQL Database (`sql` / `postgres`)

User-facing naming in this guide is **FuseBase PostgreSQL Database**. Internally, the API surface still uses the Gate `isolated-stores` contract and `IsolatedStoresApi` naming.

### Canonical docs (app integrators)

This prompt is the primary guide for app developers. For migration journal rules load **`isolatedSqlMigrationDiscipline`**. For error triage load **`docs/isolated-sql-integrator-troubleshooting.md`** (symptom → checks → support handoff). **Do not** instruct users to run platform Postgres bootstrap, GRANT, or ownership-transfer operations — those are operator-only.

### Before migration work

Load MCP prompt **`isolatedSqlMigrationDiscipline`** (`prompts_search`, groups `isolatedSql` / `isolated`, or by name). It defines bundle ↔ **`fusebase_schema_migrations`** invariants and drift recovery.

### Standard sequence (schema + store)

1. **`listIsolatedStores`** → **`createIsolatedStore`** (`engine` `postgres`, `storeType` `sql`, `source` `{ sourceType: app, sourceId: … }`, `alias`).
2. **`initIsolatedStoreStage`** for **both** `dev` and `prod` at store bootstrap (two calls; omit `bindingConfig` when Gate auto-provisions). Do not skip `prod` at create time.
3. In the app repo, keep schema files under **`postgres/migrations/`** and assemble the bundle with SDK helper **`buildSqlMigrationBundle(...)`**. Do not hand-build migration JSON or copy ad-hoc checksums into chat unless this is an explicitly temporary smoke test.
4. **`getIsolatedStoreSqlMigrationStatus`** with the bundle for this stage: read **`canApply`**, **`isDrifted`**, **`pendingCount`**, **`structuredIssues`**. For lightweight status-only probes, migration entries may use **`sql: ""`** when you only need metadata comparison (`version` / `name` / `checksum`). Optionally pass **`expectedLastAppliedVersion`** / **`expectedLastAppliedChecksum`** from a prior status → **409** if the journal tail changed.
5. Optional: **`applyIsolatedStoreSqlMigrations`** with **`dryRun: true`** — same pre-apply validation as a real apply, **no** SQL / journal writes. Use the same full bundle you would really apply.
6. **`applyIsolatedStoreSqlMigrations`** — pending tail only when prefix matches. **409** + **`data.errorCode`** / **`data.issues`** on drift or head mismatch. Prod: automatic checkpoint may run before pending migrations.
7. Verify: **`listIsolatedStoreSqlTables`**, **`getIsolatedStoreSqlStats`**, or **`queryIsolatedStoreSql`** (read-only, **one** statement per call).

**Runtime default:** when orchestration **omits** a stage (deployed app, many CLI defaults), target **`prod`**; **`fusebase dev start`** uses **`dev`**. **Bootstrap:** always init **both** stages. `dev` and `prod` are **different databases** — repeat migrations per stage with the **same logical version line**.

### Data path (no DDL)

Prefer structured APIs: **`getIsolatedStoreSqlStats`**, **`countIsolatedStoreSqlRows`**, **`selectIsolatedStoreSqlRows`**, **`insertIsolatedStoreSqlRow`**, **`batchInsertIsolatedStoreSqlRows`**, **`importIsolatedStoreSqlRows`**, **`updateIsolatedStoreSqlRows`**, **`deleteIsolatedStoreSqlRows`**. Raw: **`queryIsolatedStoreSql`** (read); **`executeIsolatedStoreSql`** — DML only, **no DDL**; schema only via **`applyIsolatedStoreSqlMigrations`**.
Runtime app path does **not** require a custom backend by default. Frontend/browser code can call Gate SDK methods such as **`selectIsolatedStoreSqlRows`**, **`countIsolatedStoreSqlRows`**, and other allowed structured operations directly with the app token. Add a feature backend only when you need privileged logic, external secrets, heavy orchestration, or non-user-context work.
Runtime app path also does **not** require users to create secrets for Gate-resolved store identity. Do not put `storeId`, database IDs, physical database names, or provider connection details into app secrets/env. Resolve the store through Gate from the app token/source scope and stable alias, or use the platform-provided binding when available.
Public/visitor apps can open with `--access=visitor`, but visitor tokens normally do **not** receive isolated-store permissions. For public portal reads/writes, use an app backend with a service token plus trusted portal/workspace context; do not expect direct visitor-token Gate SDK calls to the store to work.
A service-token backend must derive the portal/workspace scope from trusted platform auth context, not from arbitrary request body/query data. Prefer `trustedRuntimeContext.portalId` / `trustedRuntimeContext.workspaceId` when the token has `isolated_store.rls.delegate`; if that permission is not available in the target environment, an app-specific `rlsContext` key such as `req_portal_id` is only a reviewed temporary fallback.
- **Portal iframe app tokens** (`fbsfeaturetoken` in a portal brick) get `app.org_id` from the browser token but **not** `app.portal_id`. Read and verify `portalFeatureContextToken` from the iframe URL on the app backend, then use `trustedRuntimeContext.portalId` on Gate SQL calls — see [portal-embed-context.md](./portal-embed-context.md).

### Structured SQL limits

- `select` default `limit=100`, max `500`. Max **20** filters, **5** sort fields.
- **`batchInsertIsolatedStoreSqlRows`**: at most **`floor(65535 / columnCount)`** rows per call (Postgres bind limit); e.g. **~2621** rows at **25** columns.
- **`update`** / **`delete`** need filters unless **`allowAll=true`**.
- For JSONB columns in structured row APIs (`insert…`, `batchInsert…`, `update…`), pass values as JSON strings (e.g. `JSON.stringify(objOrArray)`) rather than raw JS objects/arrays to avoid Postgres `invalid input syntax for type json`.
- Under PostgreSQL RLS, `INSERT ... RETURNING` and structured `insert` with `returning` require the inserted row to pass the table's `SELECT` policy. If a row becomes visible only after a second portal/link-table insert, generate the id in app code and insert without `returning`.
- Migration bundles are **schema-only**. Gate rejects top-level `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE` / `MERGE` / `COPY` inside migration SQL.
- Large **data** seeds: **`importIsolatedStoreSqlRows`** (`csv`/`tsv`, **`COPY FROM STDIN`**); default payload cap **64MiB** UTF-8 per call (`ISOLATED_SQL_IMPORT_MAX_PAYLOAD_BYTES`, hard cap **256MiB**); split larger files.
- Small demo seeds or backfills: structured row APIs (`insert…`, `batchInsert…`) after schema apply, not inside migration SQL.

### MCP bundle size

Apply sends **full SQL text** for every migration; JSON grows quickly. Many IDE MCP stacks cap a single **`tool_call`** around **~3,000** characters — parse errors or truncation. **Practical split:** small / single-file migration via MCP for smoke; **real apps → `IsolatedStoresApi` in CI or scripts** reading SQL from disk and building the bundle with **`buildSqlMigrationBundle(...)`**.

### Tokens

Runtime app tokens: usually **`isolated_store.data.write`**, not **`isolated_store.schema.write`** or **`isolated_store.execute`**.
Wire-protocol token names still use legacy `feature` spelling for compatibility: **`window.FBS_FEATURE_TOKEN`**, cookie **`fbsfeaturetoken`**, and header **`x-app-feature-token`**. Use "app token" in prose, but do not rename the current runtime contract.

### PostgreSQL RLS native mode

RLS context alone does not filter rows. For native PostgreSQL enforcement, **`getIsolatedStoreSqlRlsStatus`** must report **`bypassRls=false`** and **`superuser=false`**. If **`bypassRls=true`**, policies may exist but Postgres will not enforce them for runtime reads/writes — label the environment accordingly and do not claim row-level security works.

### Troubleshooting (user-facing — no operator commands)

| Symptom | Check in the app | Escalate to Fusebase support with `storeId` + `stage` when |
|---------|------------------|-------------------------------------------------------------|
| `permission denied for table …` on data APIs | Token has `isolated_store.read` / `data.write`; correct `stage`; RLS policies match runtime context | Permissions and policies verified; error persists |
| Empty UI, rows visible in Studio | `dev` vs `prod`; visitor token vs backend service token; portal scope via `trustedRuntimeContext` | Backend + correct stage still returns zero rows |
| `401` / `403` on store calls | Sync Gate permissions; redeploy backend token; `x-app-feature-token` on server | After sync/redeploy still denied |
| `must be owner of table …` on migration apply | Not fixable in app migrations | Always — include migration `version` |
| `bypassRls=true` in RLS status | Treat as **policies not enforced**; use backend filters or wait for platform | Enforced RLS required and status unchanged |

Full table: **`docs/isolated-sql-integrator-troubleshooting.md`**. Never tell users to run platform bootstrap, GRANT, or ownership-transfer scripts.

Studio/support view-all rows must use the separate read-only RLS-bypass path, not normal runtime reads: **`countIsolatedStoreSqlRowsRlsBypass`** and **`selectIsolatedStoreSqlRowsRlsBypass`**. These require **`isolated_store.rls.bypass`**; Gate sets trusted transaction-local **`app.rls_admin=true`**, so tables that should be visible in Admin must include an explicit admin branch in SELECT policies. Do not grant this permission to app runtime tokens.

### RLS app-design pitfalls from QA

- Treat **`app.client_id`** as token/client scope, not app identity. In managed product flows sibling apps may share the same product-level client id. Do not use `app.client_id` to distinguish sibling apps unless the platform explicitly confirms that the token scope is app-unique.
- Treat standard **`app.*`** RLS settings as **text platform ids**, not UUIDs. Values such as `app.org_id`, `app.user_id`, `app.client_id`, `app.portal_id`, and `app.workspace_id` may be strings like `u37o` or `4164`; scope columns that compare to them should normally be `text` unless a specific custom id is truly UUID-shaped.
- Reserved settings such as **`org_id`**, **`user_id`**, **`client_id`**, **`auth_type`**, **`portal_id`**, **`workspace_id`**, and **`rls_admin`** cannot be supplied through caller-controlled `rlsContext`. They must come from Gate auth/runtime context. For **portal iframe embeds**, browser app tokens do **not** auto-inject `app.portal_id`; verify `portalFeatureContextToken` on the backend ([portal-embed-context.md](./portal-embed-context.md)) before using `trustedRuntimeContext`.
- Visitor tokens normally do not receive isolated-store permissions. If a backend service token reads/writes on behalf of a visitor, the portal/workspace RLS dimension must be derived from trusted platform auth context, not from arbitrary request body/query data. Use **`trustedRuntimeContext.portalId`** / **`trustedRuntimeContext.workspaceId`** for backend-delegated portal/workspace context; it requires **`isolated_store.rls.delegate`** and normal client/runtime tokens must not receive that permission. Treat app-specific settings such as **`app.req_portal_id`** as legacy/temporary workarounds only. See [portal-embed-context.md](./portal-embed-context.md) for iframe handoff tokens.
- RLS policy subqueries are also evaluated under RLS. If a policy uses `EXISTS (select ... from another_table ...)`, make sure the current context can see the referenced rows or use a deliberately reviewed helper pattern.
- Admin/moderation flows need a complete policy matrix. If an admin must delete or update a row, that context must first match the table's `USING` policy for the target row; otherwise `DELETE` / `UPDATE` may affect zero rows even though the admin is allowed in application code.
- Public insert flows need explicit moderation paths. For example, a visitor-created row should usually have portal-scoped read policies plus admin select/delete policies.
- For QA/MCP verification, do not spoof reserved **`portal_id`** through `rlsContext`. Use a real portal-scoped auth context, or a reviewed operator/backend token with **`isolated_store.rls.delegate`** and **`trustedRuntimeContext.portalId`**.

### After a failed apply

Transaction **ROLLBACK** — no journal rows from that attempt. Fix SQL/checksums, retry. A **prod checkpoint** may still exist if created before the failure; it does not prove migrations applied.

### Managed PostgreSQL (Azure, etc.)

**`applyIsolatedStoreSqlMigrations` often fails on the first migration** if SQL contains **`CREATE EXTENSION pgcrypto`** — many hosts do not allow-list it. **Remove it**; use **`DEFAULT gen_random_uuid()`** on PostgreSQL **13+** when **`gen_random_uuid()`** exists without **`pgcrypto`**; else allow-listed **`uuid-ossp`** or app-generated UUIDs.

### `executeIsolatedStoreSql` pitfalls

- **One** statement per call; never `;`-join multiple statements.
- If splitting merged SQL on `;`, **`--` line comments** can swallow the next statement after newlines collapse — strip comments or split carefully.

### Version 1 discipline

Do not **`apply`** throwaway SQL as **v1** on a store that must later use a real **v1** — the journal slot is consumed. Use a disposable store/stage or start with the real first migration.

### Discovery

- **`tools_search`**: parameter **`queries`** (string array, typically 1–10), not a single `query` field.
- Use **`tools_describe`** on **`initIsolatedStoreStage`**, **`getIsolatedStoreSqlMigrationStatus`**, **`applyIsolatedStoreSqlMigrations`** when schemas are unclear.
- Session: **`whoami`** / **`bootstrap`**; context prompts: groups **`authz`**, **`isolated`**, **`isolatedSql`**, **`sdk`** when mirroring in code.
- For external apps, treat hardcoded `storeId` values (including app secrets/env) as an anti-pattern. Discovery flow: `listIsolatedStores` with app `clientId` -> filter by stable alias/aliasLike -> use returned `storeId` for stage/data calls.

### Manifest / checksums

For **local** storage in a repo, keep migration SQL in a **dedicated folder** at **`postgres/migrations/`**. Do not mix with application code — easier ordering, review, and CI checksum checks.
- **MUST flow order:** file-first schema changes (create/update file in `postgres/migrations/` → build the bundle with **`buildSqlMigrationBundle(...)`** from exact file contents → status → apply).
- **Inline SQL:** MCP inline SQL allowed only for one-off smoke/dev tests and explicitly marked temporary.
- **Final gate:** if schema changed, do not finish unless `postgres/migrations/` has matching new/updated migration file and manifest entry.
- **Manifest scope:** manifest should describe the app bundle (bundle version + ordered migrations). Do **not** store environment state there such as `storeId`, `stageDevApplied`, `stageProdApplied`, or other per-stage apply markers.
- Do not ship raw migration SQL in browser runtime just to render status. Runtime UI should read migration status from Gate metadata or a server-side helper, not assemble the bundle in the browser.
- **Required handoff after schema ops:** migration file path, `version`, `name`, `checksum`, `storeId`, `stage`.

Per migration: **`version`**, **`name`**, **`checksum`** — prefer SDK helpers **`buildSqlMigrationBundle(...)`** and **`calculateSqlMigrationChecksum(sql)`** so checksums match Gate canonicalization (`CRLF -> LF`, trailing whitespace trimmed). Checksums are **SHA-256** (`sha256`) hex digests. Optional **`bundleVersion`** on the bundle. Keep repo manifests app-owned and environment-neutral.

### UI links (store and table)

- Store page template: **`https://<org-subdomain>.<fusebase-domain>/studio/<org-ui-id>/isolated-stores/sql/<store-id>`**.
- Replace placeholders with real values from the environment and tool results: org subdomain and fusebase domain, org UI id, and store id.
- Table view adds query param: **`?table=<schema.table_name>`** (example: **`?table=public.fusebase_schema_migrations`**).
- After creating a store or creating a SQL table through MCP, suggest opening the corresponding UI link.
---

## Version

- **Version**: 1.9.0
- **Category**: specialized
- **Last synced**: 2026-07-01
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
