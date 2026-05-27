---
version: "1.8.9"
mcp_prompt: isolatedSql
last_synced: "2026-05-09"
title: "FuseBase PostgreSQL Database"
category: specialized
---
# FuseBase PostgreSQL Database

> **MARKER**: `mcp-isolated-sql-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `isolatedSql` for latest content.

---
## FuseBase PostgreSQL Database (`sql` / `postgres`)

User-facing naming in this guide is **FuseBase PostgreSQL Database**. Internally, the API surface still uses the Gate `isolated-stores` contract and `IsolatedStoresApi` naming.

### Canonical docs

Repo **`docs/isolated-sql-stores.md`** is the **production runbook** (playbooks, permissions, status/apply semantics, MCP vs SDK). Use it for step-by-step operations.

### Before migration work

Load MCP prompt **`isolatedSqlMigrationDiscipline`** (`prompts_search`, groups `isolatedSql` / `isolated`, or by name). It defines bundle ↔ **`fusebase_schema_migrations`** invariants and drift recovery.

### Standard sequence (schema + store)

1. **`listIsolatedStores`** → **`createIsolatedStore`** (`engine` `postgres`, `storeType` `sql`, `source` `{ sourceType: app, sourceId: … }`, `alias`).
2. **`initIsolatedStoreStage`** for `prod` / `dev` (omit `bindingConfig` when Gate auto-provisions).
3. In the app repo, keep schema files under **`postgres/migrations/`** and assemble the bundle with SDK helper **`buildSqlMigrationBundle(...)`**. Do not hand-build migration JSON or copy ad-hoc checksums into chat unless this is an explicitly temporary smoke test.
4. **`getIsolatedStoreSqlMigrationStatus`** with the bundle for this stage: read **`canApply`**, **`isDrifted`**, **`pendingCount`**, **`structuredIssues`**. For lightweight status-only probes, migration entries may use **`sql: ""`** when you only need metadata comparison (`version` / `name` / `checksum`). Optionally pass **`expectedLastAppliedVersion`** / **`expectedLastAppliedChecksum`** from a prior status → **409** if the journal tail changed.
5. Optional: **`applyIsolatedStoreSqlMigrations`** with **`dryRun: true`** — same pre-apply validation as a real apply, **no** SQL / journal writes. Use the same full bundle you would really apply.
6. **`applyIsolatedStoreSqlMigrations`** — pending tail only when prefix matches. **409** + **`data.errorCode`** / **`data.issues`** on drift or head mismatch. Prod: automatic checkpoint may run before pending migrations.
7. Verify: **`listIsolatedStoreSqlTables`**, **`getIsolatedStoreSqlStats`**, or **`queryIsolatedStoreSql`** (read-only, **one** statement per call).

Default stage is **`prod`** when stage is omitted by higher-level orchestration. `dev` and `prod` are **different databases** — repeat the sequence per stage with the **same logical version line**.

### Data path (no DDL)

Prefer structured APIs: **`getIsolatedStoreSqlStats`**, **`countIsolatedStoreSqlRows`**, **`selectIsolatedStoreSqlRows`**, **`insertIsolatedStoreSqlRow`**, **`batchInsertIsolatedStoreSqlRows`**, **`importIsolatedStoreSqlRows`**, **`updateIsolatedStoreSqlRows`**, **`deleteIsolatedStoreSqlRows`**. Raw: **`queryIsolatedStoreSql`** (read); **`executeIsolatedStoreSql`** — DML only, **no DDL**; schema only via **`applyIsolatedStoreSqlMigrations`**.
Runtime app path does **not** require a custom backend by default. Frontend/browser code can call Gate SDK methods such as **`selectIsolatedStoreSqlRows`**, **`countIsolatedStoreSqlRows`**, and other allowed structured operations directly with the feature token. Add a feature backend only when you need privileged logic, external secrets, heavy orchestration, or non-user-context work.

### Structured SQL limits

- `select` default `limit=100`, max `500`. Max **20** filters, **5** sort fields.
- **`batchInsertIsolatedStoreSqlRows`**: at most **`floor(65535 / columnCount)`** rows per call (Postgres bind limit); e.g. **~2621** rows at **25** columns.
- **`update`** / **`delete`** need filters unless **`allowAll=true`**.
- For JSONB columns in structured row APIs (`insert…`, `batchInsert…`, `update…`), pass values as JSON strings (e.g. `JSON.stringify(objOrArray)`) rather than raw JS objects/arrays to avoid Postgres `invalid input syntax for type json`.
- Migration bundles are **schema-only**. Gate rejects top-level `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE` / `MERGE` / `COPY` inside migration SQL.
- Large **data** seeds: **`importIsolatedStoreSqlRows`** (`csv`/`tsv`, **`COPY FROM STDIN`**); default payload cap **64MiB** UTF-8 per call (`ISOLATED_SQL_IMPORT_MAX_PAYLOAD_BYTES`, hard cap **256MiB**); split larger files.
- Small demo seeds or backfills: structured row APIs (`insert…`, `batchInsert…`) after schema apply, not inside migration SQL.

### MCP bundle size

Apply sends **full SQL text** for every migration; JSON grows quickly. Many IDE MCP stacks cap a single **`tool_call`** around **~3,000** characters — parse errors or truncation. **Practical split:** small / single-file migration via MCP for smoke; **real apps → `IsolatedStoresApi` in CI or scripts** reading SQL from disk and building the bundle with **`buildSqlMigrationBundle(...)`**.

### Tokens

Runtime app tokens: usually **`isolated_store.data.write`**, not **`isolated_store.schema.write`** or **`isolated_store.execute`**.

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
- For external apps, treat hardcoded `storeId` values (including app secrets) as an anti-pattern. Discovery flow: `listIsolatedStores` with app `clientId` -> filter by stable alias/aliasLike -> use returned `storeId` for stage/data calls.

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

- **Version**: 1.8.9
- **Category**: specialized
- **Last synced**: 2026-05-09
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
