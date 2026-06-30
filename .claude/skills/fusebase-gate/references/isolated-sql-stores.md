---
version: "1.1.2"
mcp_prompt: none
source: "docs/isolated-sql-stores.md"
last_synced: "2026-06-26"
title: "Isolated SQL stores and migrations (Gate)"
category: specialized
---
# Isolated SQL stores and migrations (Gate)

> **SOURCE**: This file is copied from `docs/isolated-sql-stores.md` in the fusebase-gate repo. Edit that file, then run `npm run mcp:skills:generate`.

---
# FuseBase PostgreSQL Database — production guide (Gate isolated stores)

End-to-end reference for **FuseBase PostgreSQL Database** on the Gate `isolated-stores` contract: MCP tools, `@fusebase/fusebase-gate-sdk` (`IsolatedStoresApi`), permissions, migrations, and failure modes.  
**Contracts:** `src/api/contracts/ops/isolated-stores/isolated-stores.ts`.
For a hierarchy-focused reference, see [isolated-store-hierarchy.md](./isolated-store-hierarchy.md).
That hierarchy reference now also explains the current stage model (`store -> stage instance -> revision -> physical database`) in practical terms.
For the current go/no-go list, see [isolated-stores-release-checklist.md](./isolated-stores-release-checklist.md).

Current stable baseline (2026-04-12):

- new SQL apps can be bootstrapped through Gate with ordered migration bundles and read-only or read/write runtime paths;
- Gate persists the latest applied/adopted SQL migration bundle into stage metadata;
- Studio can render migration status from Gate metadata without local app-repo access;
- remaining issues observed in dev are non-blocking UI/style issues, not isolated-store core flow regressions.

Current rollout position (2026-04-12):

- app-facing PostgreSQL DB path is the primary baseline; old flag-gated wording is legacy;
- production pilot target is our managed apps plus selected client projects, not broad public self-serve release;
- current baseline provider path for `postgres` remains Azure;
- `Neon` is under evaluation as a future provider option, not as a replacement for Gate contracts or the current `v1` rollout path.

---

## 1. Quick decisions

| Goal                      | Use                                                                                                |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| Create store + DB stage   | `createIsolatedStore` → `initIsolatedStoreStage`                                                   |
| Change schema (DDL)       | **Only** `getIsolatedStoreSqlMigrationStatus` + `applyIsolatedStoreSqlMigrations` (ordered bundle) |
| Insert/update/delete rows | Structured row APIs (`insertIsolatedStoreSqlRow`, …) or read-only `queryIsolatedStoreSql`          |
| Seed / backfill data      | Structured row APIs or `importIsolatedStoreSqlRows` (CSV/TSV → `COPY`)                             |
| Inspect RLS posture       | `getIsolatedStoreSqlRlsStatus` (read-only table/policy/index introspection)                        |
| Validate RLS intent       | Optional `rlsManifest` on migration status/apply/adopt; currently warn-only                        |
| Chat / MCP smoke test     | One small migration **or** status + dryRun; big bundles → **SDK/CI**                               |
| Understand drift / 409    | Response `structuredIssues` / error `data.issues`; MCP prompt **`isolatedSqlMigrationDiscipline`** |

Runtime note:

- a custom app backend is **not required** for normal PostgreSQL runtime access;
- browser/UI code can call Gate SDK methods directly with the app token for frontend-safe reads and allowed structured writes;
- add a backend only when you need privileged operations, secret-bearing integrations, heavy orchestration, or non-user-context work.
- public/visitor apps can open with `--access=visitor`, but visitor tokens normally do **not** receive isolated-store permissions. For public portal reads/writes, use an app backend with a service token plus trusted portal/workspace context; do not expect direct visitor-token Gate SDK calls to the store to work.
- A service-token backend must derive the portal/workspace scope from trusted platform auth context, not from arbitrary request body/query data. Prefer `trustedRuntimeContext.portalId` / `trustedRuntimeContext.workspaceId` when the token has `isolated_store.rls.delegate`; if that permission is not available in the target environment, an app-specific `rlsContext` key such as `req_portal_id` is only a reviewed temporary fallback.
- **Portal iframe app tokens** (`fbsfeaturetoken` in a portal brick) get `app.org_id` from the browser token but **not** `app.portal_id`. Read and verify `portalFeatureContextToken` from the iframe URL on the app backend, then use `trustedRuntimeContext.portalId` on Gate SQL calls — see [portal-embed-context.md](./portal-embed-context.md).
- Wire-protocol token names still use legacy `feature` spelling for compatibility: `window.FBS_FEATURE_TOKEN`, cookie `fbsfeaturetoken`, and header `x-app-feature-token`. Use "app token" in prose, but do not rename the current runtime contract.

Runtime configuration rule:

- the isolated store is a Gate-resolved resource bound to the app by source scope and permissions, not a value the app owner must copy into secrets;
- do **not** register `storeId`, database IDs, physical DB names, or provider connection details with `fusebase secret create`;
- runtime code should resolve the target store through Gate using the app token/client scope and stable store `alias` (or consume the platform-provided binding when available), then use the returned `storeId` only in-memory for that request/session;
- `storeId` is acceptable in MCP/operator logs, Studio links, and CLI migration commands, but that does not make it runtime app configuration.

---

## 1.1 Current managed-store capability summary

For `sql/postgres`, the current managed-store path already supports:

- app-bound store registration
- dedicated `dev` / `prod` stage databases
- migration status / dry-run / apply with a stage-local journal
- structured row CRUD
- batch insert and CSV/TSV import via `COPY`
- stage stats, table introspection, counts, and query/select paths
- read-only RLS status introspection for Studio/support visibility
- transaction-local RLS runtime context on SQL runtime calls
- warn-only RLS manifest validation on migration status/apply/adopt
- checkpoints and full stage restore (prod auto-checkpoint before migrations uses **admin** or **RLS-bypass** credentials for `pg_dump` when split roles + `FORCE RLS` are enabled — not the runtime role). **Azure server setup** (roles, secrets, Helm, `BYPASSRLS`): [isolated-postgres-azure-operations.md](./isolated-postgres-azure-operations.md)
- provider-switchable snapshot storage (`local_file` or `azure_blob`)
- Studio migration/status rendering via bundle metadata persisted by Gate

What it does not yet fully productize:

- app release pipeline delivery of migration bundles
- first-class snapshot preview API
- completed SQL RLS enforcement layer
- blocking RLS validation and runtime/migrator role split
- production-grade retention policy and pruning workflow for stored snapshots

For the next production-pilot cut, the main remaining tasks are:

- backup / restore path that is safe enough for managed apps and selected client projects;
- migration / copy flow for managed apps;
- minimal frontend/backend execution split that does not rely only on skills;
- a stable operator-facing path into store management (Studio path is acceptable for the pilot).

The concrete release gate for these items is tracked in [isolated-stores-release-checklist.md](./isolated-stores-release-checklist.md).

Items that can wait for public-release hardening:

- full frontend/backend token split;
- public account / NX-facing store UI;
- autoscaling / multi-instance provider work;
- polished external snapshot UX.

---

## 1.2 Provider note — Neon vs current Gate path

`Neon` is worth evaluating as a PostgreSQL provider option, but it does **not** replace the need for the current Gate-owned contract.

What Neon brings officially that is relevant here:

- serverless Postgres access over `HTTP` / `WebSockets`;
- compute autoscaling;
- branching / point-in-time restore primitives;
- agent-oriented packaging;
- AWS and Azure deployment regions.

What still has to remain Gate-owned even if Neon is adopted underneath:

- app/store binding;
- token permissions and `resource_scope`;
- stage lifecycle semantics (`dev` / `prod`);
- migration discipline and stage-aware apply flow;
- frontend-safe structured operations vs backend-only privileged execution;
- store control-plane lifecycle and Studio-facing metadata.

Practical comparison:

- if the question is infra/provider ergonomics, `Neon` may be stronger than a self-managed path on:
  - cost elasticity
  - provisioning speed
  - built-in branch/restore primitives
- if the question is app/runtime contract, `Neon` does not remove the need for `Gate`;
- `HTTP` transport itself is not a blocker:
  - toolized SQL over MCP / HTTP is already a normal pattern
  - in current tests we have not seen codegen regressions caused by the Gate HTTP path
  - MCP agents here should not treat raw SQL as the primary contract anyway

Current recommendation:

- keep Azure as the near-term production-pilot baseline;
- treat Neon as a provider experiment for a later hardening step;
- do not let provider selection delay the current migration / backup / managed-app rollout tasks.

---

## 2. Permissions (typical)

| Capability              | Permission                                                                             |
| ----------------------- | -------------------------------------------------------------------------------------- |
| Row CRUD, import, query | `isolated_store.read` + `isolated_store.data.write` (as designed for your token)       |
| **Apply migrations**    | `isolated_store.schema.write` (operators / CI — not normal end-users)                  |
| Raw DML escape hatch    | `executeIsolatedStoreSql` — **no DDL**                                                 |
| RLS break-glass bypass  | `isolated_store.rls.bypass` — reserved for future explicit audited support/admin paths |
| RLS context delegation  | `isolated_store.rls.delegate` — backend/operator-only trusted portal/workspace context |
| List/create stores      | Control-plane permissions on isolated-store ops                                        |

Schema **never** goes through `executeIsolatedStoreSql`.
Operator migration calls do not require a session-backed user anymore: token-auth requests with the right permission can apply migrations through HTTP/SDK, and Gate records a stable token actor label in the audit fields when no concrete `userId` is present.
After a successful SQL migration apply or baseline adoption, Gate stores the latest bundle and schema name in the stage `provisioningMetadata`. Studio can use that metadata to show migration status without access to the app repo.

For the midsize-target PostgreSQL Row-Level Security path and the recommended Gate integration model, see [isolated-sql-rls-plan.md](./isolated-sql-rls-plan.md).

RLS validation is currently warn-only. `getIsolatedStoreSqlMigrationStatus`, `applyIsolatedStoreSqlMigrations`, and `adoptIsolatedStoreSqlMigrationBaseline` may include `rlsManifest`; Gate returns `status.rlsValidation` with table/column/index/policy warnings but does not reject apply on those warnings yet. apps-cli sends `rlsManifest` only when its `postgres-rls` flag is enabled. The manifest supports `tenant`, `user`, `owner_collaborator`, `scoped`, `none`, and `technical` table classifications.

RLS verification must check the runtime database role, not only the SQL context. `getIsolatedStoreSqlRlsStatus` returns the active runtime `currentUser`, `bypassRls`, and `superuser` flags. If `bypassRls` is `true`, PostgreSQL policies are visible in introspection but are not enforced for runtime queries; scoped demos must either use explicit `WHERE current_setting(...)` filters as a temporary workaround or wait for the runtime role split.

For server-backed isolated Postgres stores, Gate can run schema operations with a separate migrator role when `ISOLATED_PG_MIGRATOR_USER` and `ISOLATED_PG_MIGRATOR_PASSWORD` are configured. Runtime query/data APIs still use the runtime role; migration apply/baseline/checksum repair use the migrator role. New auto-provisioned databases use `provisioningMetadata.roleModel = "split"` when this is active.

Existing legacy databases need an operator bootstrap before they can be treated as production-grade RLS environments. Configure a distinct `ISOLATED_PG_RUNTIME_USER` / `ISOLATED_PG_RUNTIME_PASSWORD`, keep schema writes on `ISOLATED_PG_MIGRATOR_USER` / `ISOLATED_PG_MIGRATOR_PASSWORD`, then run:

```bash
npm run isolated-pg:bootstrap-rls-runtime -- --database <stage_database> --schema public
```

The bootstrap ensures the runtime role exists with `NOBYPASSRLS`, grants runtime DML/function/sequence privileges, and verifies that connecting as runtime reports `bypassRls=false` and `superuser=false`. Add `--transfer-ownership` only when the operator wants to move existing schema/table ownership to the migrator role; new auto-provisioned databases already use the migrator owner when split env is configured.

Studio/support "show all rows" views must not use normal request scope. Gate exposes separate read-only row endpoints for this mode: `countIsolatedStoreSqlRowsRlsBypass` and `selectIsolatedStoreSqlRowsRlsBypass`. They require `isolated_store.rls.bypass`, ignore request `rlsContext`, set trusted `app.rls_admin=true` in the same transaction, and log the actor/org/store/stage/table. Do not grant this permission to app runtime tokens.

Tables that should be visible in Studio Admin must include an explicit read-only admin branch in their `SELECT` policies, for example: `current_setting('app.rls_admin', true) = 'true' OR (...)`. This is Azure-compatible because Azure Flexible Server does not let the configured administrator create arbitrary `BYPASSRLS` roles. Optional physical `BYPASSRLS` read roles are legacy/operator-specific and must not be required for the normal Studio Admin path. **Server-level role + secret setup on Azure:** [isolated-postgres-azure-operations.md](./isolated-postgres-azure-operations.md).

Backend-mediated visitor flows should not tunnel reserved context through `rlsContext`. For service-token calls that act on a verified visitor portal/workspace context, use `trustedRuntimeContext.portalId` and/or `trustedRuntimeContext.workspaceId` on runtime SQL request bodies. Gate requires `isolated_store.rls.delegate` for this field and maps it to trusted transaction-local `app.portal_id` / `app.workspace_id`. Do not grant this permission to browser/client runtime tokens, and do not fill `trustedRuntimeContext` directly from user-controlled request payloads. For portal iframe embeds, obtain portal scope from verified `portalFeatureContextToken` — see [portal-embed-context.md](./portal-embed-context.md).

Standard `app.*` RLS settings are text platform ids, not UUIDs. Values such as `app.org_id`, `app.user_id`, `app.client_id`, `app.portal_id`, and `app.workspace_id` may be strings like `u37o` or `4164`; scope columns that compare to these settings should normally be `text`. Use UUID only for app-owned ids that are actually UUID-shaped.

Under PostgreSQL RLS, `INSERT ... RETURNING` and structured `insert` with `returning` require the inserted row to pass the table's `SELECT` policy. If a row becomes visible only after a second portal/link-table insert, generate the id in app code and insert without `returning`.

Recommended RLS verification checklist after schema apply:

1. Run migration status and confirm the journal head matches the manifest/bundle.
2. Run RLS status and confirm `bypassRls=false` for real RLS tests.
3. Probe `current_setting('app.project_id', true)` or another custom setting with a sample `rlsContext`.
4. Read scoped data and confirm the result is a subset, not all rows.
5. If `bypassRls=true`, label the environment as "policies not enforced" and do not claim that RLS filtering works.

Anti-pattern: assuming `rlsContext` alone filters rows. `rlsContext` only sets transaction-local PostgreSQL settings; filtering happens only if the runtime role is subject to RLS and table policies use those settings.

Optional-scope policy dimensions should allow "no scope selected" only when that is intended:

```sql
AND (
  NULLIF(current_setting('app.project_id', true), '') IS NULL
  OR project_id = NULLIF(current_setting('app.project_id', true), '')
)
```

---

## 3. Identifiers you must preserve

Every call needs **`orgId`**, **`storeId`**, **`stage`** (`dev` | `prod`) exactly as Gate returned them.  
**`dev` and `prod` are different databases** — same logical migration _sequence_ (version numbers + SQL per version), separate journals.

Preserve these identifiers in the current Gate call chain, operator handoff, or migration logs. Do **not** convert them into app secrets or long-lived runtime env vars. If app runtime needs a store later, resolve it again through Gate from the app token/source scope and stable alias.

---

## 3.1 Bundle assembly in the app / agent

If the app or its coding agent can read the migration `.sql` files, prefer the Gate SDK helper instead of hand-building JSON:

- `buildSqlMigrationBundle({ bundleVersion?, migrations })`
- `calculateSqlMigrationChecksum(sql)`

Typical flow:

1. Read ordered `.sql` files from the app repo.
2. Pass `version`, `name`, and exact SQL text into `buildSqlMigrationBundle(...)`.
3. Send the resulting bundle to:
   - `getIsolatedStoreSqlMigrationStatus`
   - `applyIsolatedStoreSqlMigrations`

This keeps checksum generation canonical and avoids agent drift from ad-hoc hashing logic.

---

## 4. Playbook A — New store (first time)

1. **`listIsolatedStores`** (`orgId`, optional `clientId` for app-scoped tokens). Empty list is normal before create.
2. **`createIsolatedStore`** — `storeType: "sql"`, `engine: "postgres"`, `alias`, `source: { sourceType: "app", sourceId: "<app id>" }`.
3. **`initIsolatedStoreStage`** — for **both** `dev` and `prod` (two calls, same `storeId`). Omit `bindingConfig` if Gate auto-provisions (see repo README / `ISOLATED_PG_*`). Do **not** defer `prod` to “when needed” — published apps target `prod`; `fusebase dev start` targets `dev`.
4. **`applyIsolatedStoreSqlMigrations`** — full ordered bundle for **each** `storeId` + `stage` (same logical version line; separate physical databases).

**Stage bootstrap vs runtime default:** always provision **both** stages at create time. When higher-level orchestration **omits** a stage (deployed app runtime, many CLI defaults), the target is **`prod`**. Local **`fusebase dev start`** uses **`dev`**.

**Empty `listIsolatedStores` after create:** wrong `orgId`, or `clientId` filter does not match `source.sourceId` — omit `clientId` to list all org stores.

---

## 5. Playbook B — Schema change (production-safe)

Do this **per stage** you care about (usually **dev** first, then **prod**).

1. **Load context** — MCP: `prompts_search` groups `authz`, `isolated`, `isolatedSql`, `sdk`; before touching bundles load **`isolatedSqlMigrationDiscipline`**.
2. **Build the bundle** from repo files + manifest with SDK helpers: strict increasing **`version`**, stable **`name`**, **`checksum`** = SHA-256 of canonicalized SQL (**`CRLF -> LF`**, trailing whitespace trimmed).
3. **`getIsolatedStoreSqlMigrationStatus`** — same `storeId`, `stage`, and bundle line you want to compare.
   - For lightweight status-only checks, each migration entry may use **`sql: ""`** when you only need metadata comparison (`version` / `name` / `checksum`) and drift/pending/head visibility.
   - For status immediately before apply, you can still send the exact full bundle you plan to apply.
   - Check **`canApply`** / **`isDrifted`**, **`pendingCount`**, **`structuredIssues`**.
   - Optional optimistic lock: pass **`expectedLastAppliedVersion`** / **`expectedLastAppliedChecksum`** from your _previous_ status if you want Gate to **409** when someone else migrated first.
4. **Optional preflight** — **`applyIsolatedStoreSqlMigrations`** with **`dryRun: true`** (same body otherwise): validates the same pre-apply bundle rules as a real apply (including checksum/schema-only checks), **no SQL executed**, no journal writes; response includes full **`status`**.
5. **`applyIsolatedStoreSqlMigrations`** — same bundle; prod may create an automatic **checkpoint** before pending migrations run.
6. **Verify** — `listIsolatedStoreSqlTables`, `getIsolatedStoreSqlStats`, or `queryIsolatedStoreSql` (one statement per call).

**Never** edit **`name` / `checksum` / `sql`** for versions already in **`fusebase_schema_migrations`**; ship fixes as **new higher versions**.

---

## 6. API semantics — status vs apply

### Status (200)

- **`isDrifted`**: bundle prefix does not match journal → **`canApply`** is false, **`structuredIssues`** lists per-version mismatches (journal vs bundle; checksum issues may include **`bundleSqlContentSha256`** — not raw SQL).
- Pending tail: **`pendingMigrations`** when not drifted.
- Status can run with metadata-only bundle entries (`sql: ""`) when the caller only needs drift/head/pending visibility. This is useful for MCP/bootstrap checks that should not resend full SQL text on every probe.

### Apply / dryRun

- **200** — migrations ran (or **dryRun** returned validation only).
- **409** — **`data.errorCode`**:
  - **`isolated_sql_migration_drift`** — prefix mismatch; **`data.issues`** mirrors structured drift rows.
  - **`isolated_sql_journal_head_mismatch`** — optimistic-lock fields disagree with journal tail.
- **`dryRun: true`** now uses the same pre-apply bundle validation pipeline as a real apply. If the full bundle would fail on canonical checksum or schema-only rules, dryRun fails too.

### Auth/source-scope troubleshooting

If status says **`canApply: true`** and **`isDrifted: false`**, but runtime reads or apply fail with auth errors, do not start by editing checksums, re-baselining, or recreating the store.

Check the token/store binding first:

1. Call `me` / `whoami` and record the exact token **`client` scope**. Use the actual resolved scope, not a guessed `apps[].id`; in apps-cli projects the Gate MCP token client scope is commonly the project `productId`.
2. Read the store and inspect **`sourceScopes`**.
3. If the store is missing `{ "sourceType": "app", "sourceId": "<current client scope>" }`, this is a **source scope mismatch**.
4. Use **`attachIsolatedStoreSourceScope`** to add the missing app source scope when you have `isolated_store.control.write`.
5. Verify:
   - `listIsolatedStores({ orgId, clientId: <current client scope> })` returns the store;
   - `getIsolatedStore` shows both old and new `sourceScopes`;
   - a safe data-plane read, for example `selectIsolatedStoreSqlRows` with `limit: 1`, returns 200;
   - `getIsolatedStoreSqlMigrationStatus` still returns `canApply: true`.

What the errors mean:

- **`403 Token cannot access isolated store`** before a SQL/status result usually means the token `client` scope does not match any store `sourceScopes` entry.
- **`400 Authenticated actor was not resolved`** on apply means the request reached the apply route but Gate could not derive an audit actor from that auth context.
- If **dryRun apply** reaches bundle validation, for example `bundle.migrations[0].sql must not be empty`, auth and source-scope checks have already passed; send a full SQL bundle for apply/dryRun.

Guardrails:

- `attachIsolatedStoreSourceScope` is non-destructive. It adds a source-scope row and does not touch stage databases, `fusebase_schema_migrations`, aliases, or existing binding config.
- Do not attach a guessed source id. Attach the exact `client` scope from the token that must use the store.
- A token scoped to `client:A` cannot attach `sourceId:B`; use a matching client-scoped token or a user/operator context with `isolated_store.control.write`.
- Do not run real apply as part of this diagnosis unless the user explicitly asked for it.

### Transactions

Apply uses a **single DB transaction**; failure → **ROLLBACK** (no partial journal rows from that attempt). A **prod checkpoint** may still exist if Gate created it before a failed apply — it is not proof migrations committed.

### Gate-enforced migration contract

Gate validates what it can actually see in the incoming bundle:

- ordered versions;
- `name`, `checksum`, and exact `sql` bytes per version;
- journal drift and optimistic-lock mismatches;
- **schema-only SQL** in migration bundles.

Top-level `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `MERGE`, and `COPY` are rejected in migration bundles.  
Use structured row APIs or `importIsolatedStoreSqlRows` for demo seeds, backfills, and large data loads.

### What Gate cannot enforce from the service boundary

Gate does **not** see the app repo or browser build pipeline, so it cannot prove:

- that a committed `postgres/migrations/manifest.json` exists in the repo;
- that the bundle was assembled from repo files rather than hardcoded in app code;
- that migration SQL was kept out of the browser bundle.

Those constraints should be enforced through repo templates, skills/prompts, code review, and CI checks around the app artifact itself.

---

## 7. MCP vs SDK / CI

- **`applyIsolatedStoreSqlMigrations`** sends **cumulative** SQL (version N includes full text for 1..N in the JSON shape) → payload grows fast.
- Many MCP hosts cap **`tool_call`** JSON (~3k characters is a common order of magnitude). Symptoms: parse errors, truncated JSON.  
  **Rule:** MCP for **small** bundles / smoke; **CI or scripts** with **`IsolatedStoresApi`** reading files from disk for real apps.

---

## 8. Repository discipline (source of truth)

- Keep migration SQL **in a dedicated directory** in the repo — use **`postgres/migrations/`** so tooling and reviewers recognize it; avoid mixing with app source or ad-hoc scripts — ordering, review, and CI checksum checks stay obvious.
- One SQL file per **`version`**; manifest with **`version`**, **`name`**, **`checksum`** aligned with the bytes Gate sends.
- **CI** should verify checksums vs files — prompts are not a substitute.
- **MUST flow:** file-first for schema changes — create/update files in `postgres/migrations/`, build bundle via `buildSqlMigrationBundle(...)` (includes canonical SQL/checksum), run status, then apply.
- Bundle assembly should stay in scripts / CI / backend tooling; do not make browser runtime the source of truth for migration SQL or bundle order.
- **MUST artifact after schema ops:** include migration file path, `version`, `name`, `checksum`, `storeId`, `stage`.
- **Inline SQL in MCP:** only for one-off smoke/dev tests and explicitly marked temporary; not for persistent schema changes.
- **Final gate:** do not finish if schema changed but `postgres/migrations/` has no matching new/updated migration file/manifest entry.
- Do not patch drift by editing `checksum` to a transport-specific value or by storing local-only checksum notes; fix the bundle pipeline and rerun status/apply.

---

## 9. Recovering from drift

- **Journal correct, bundle wrong:** revert bundle prefix to match production journal, then append new versions only.
- **Disposable dev:** recreate stage / empty DB, re-apply from v1.
- **Forbidden:** mutating **`fusebase_schema_migrations`**, or DDL via **`executeIsolatedStoreSql`** to “match” a bad bundle.

---

## 10. Managed PostgreSQL (e.g. Azure)

- **`CREATE EXTENSION pgcrypto`** is often blocked — first **`apply`** fails if migration creates it. Remove it; prefer **`DEFAULT gen_random_uuid()`** on PostgreSQL **13+** when the server exposes **`gen_random_uuid()`** without that extension; else allow-listed **`uuid-ossp`** or app-generated UUIDs.
- `pgvector` / `CREATE EXTENSION vector` is provider-dependent too. Azure Flexible Server docs support it in principle, but only after adding `vector` to the server allowlist (`azure.extensions`) and only if the current managed server exposes it. If `CREATE EXTENSION vector` returns `extension "vector" is not allow-listed`, that is an Azure server configuration/support issue, not a Gate contract issue.

---

## 11. MCP mechanics (once)

- **`tools_search`** requires **`queries`**: string **array** (not a single `query` field).
- Before first use of heavy ops: **`tools_describe`** on `initIsolatedStoreStage`, `getIsolatedStoreSqlMigrationStatus`, `applyIsolatedStoreSqlMigrations`.

---

## 12. Related sources

| What                     | Where                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| MCP prompts (LLM)        | `src/mcp/prompts/isolated.ts`, `isolated-sql.ts`, `isolated-sql-migration-discipline.ts` |
| Regenerated skill copies | `npm run mcp:skills:generate` → `generated/claude_skills/fusebase-gate/references/`      |
| Isolated SQL index       | `docs/isolated-sql-stores.md` (this file), `AGENTS.md`                                   |
---

## Version

- **Version**: 1.1.2
- **Category**: specialized
- **Last synced**: 2026-06-26
