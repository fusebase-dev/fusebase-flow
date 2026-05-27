---
version: "1.1.4"
mcp_prompt: isolatedSqlMigrationDiscipline
last_synced: "2026-05-09"
title: "Fusebase Gate — Isolated SQL migration discipline"
category: specialized
---
# Fusebase Gate — Isolated SQL migration discipline

> **MARKER**: `mcp-isolated-sql-migration-discipline-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `isolatedSqlMigrationDiscipline` for latest content.

---
## Isolated SQL — migration discipline (anti-drift)

Use **before** building, editing, or sending a bundle to **`getIsolatedStoreSqlMigrationStatus`** / **`applyIsolatedStoreSqlMigrations`**. For full playbooks see repo **`docs/isolated-sql-stores.md`**.

## What drift is

**Drift** = the ordered **applied prefix** of your bundle (versions already in **`fusebase_schema_migrations`**) does not match the journal: same order and, for each applied row, same **`version`**, **`name`**, and **`checksum`** (and, for real apply bundles, the same canonical **`sql`** bytes Gate validates against the checksum).

On apply: **HTTP 409**, **`data.errorCode`** **`isolated_sql_migration_drift`**, **`data.issues[]`** (journal vs bundle fields; checksum rows may include **`bundleSqlContentSha256`** — not raw SQL). On status: **`isDrifted`**, **`structuredIssues`**, **`canApply`** false.

## Invariants

1. **Repo + manifest** own canonical SQL; store migration **`.sql`** files under **`postgres/migrations/`**, not alongside random app code, so history stays clear. The journal records what ran — **never hand-edit** journal rows to force a match.
2. **Immutable applied prefix** — do not change **`name` / `checksum` / `sql`** for versions already applied to a stage you keep.
3. **Fixes = new tail versions** only (K+1, K+2, …), never rewrite applied files.
4. **Prefix alignment** — first **N** bundle entries must match journal **1..N**; **pending** = tail after **N**.
5. **dev / prod** — same logical version line and SQL per version; **separate** DBs and journals. Prod may lag dev.
6. **MUST flow order** — for any schema change: create/update files in **`postgres/migrations/`** first, assemble the bundle with SDK helper **`buildSqlMigrationBundle(...)`**, then run status, then apply.
6a. **Schema-only bundles** — migration bundles are for schema SQL only. Top-level `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE` / `MERGE` / `COPY` belong in structured seed/import flows after schema apply.
6b. **Status-only probes may omit SQL content** — `getIsolatedStoreSqlMigrationStatus` can compare metadata with `sql: ""` for each entry when you only need drift/pending/head visibility. Real apply / dryRun still require the full SQL bundle.
7. **Inline SQL restriction** — inline SQL in MCP `tool_call` is allowed only for one-off smoke/dev tests and must be explicitly marked temporary.
8. **Final gate** — do not mark work done when schema changed but no new/updated migration file or manifest entry exists under **`postgres/migrations/`**.
9. **Manifest is app-owned, not environment state** — do not store `storeId`, `stageDevApplied`, `stageProdApplied`, or similar per-stage apply markers in the migration manifest. Stage state belongs to Gate journals and deployment logs.
10. **Browser runtime is not the source of truth** — do not ship raw migration SQL into the browser just to compute bundle status. Assemble bundles in scripts / backend / CI and let runtime UI read Gate-owned migration status.

## Required artifact after schema ops

Always leave these fields in the handoff/log: migration file path, **`version`**, **`name`**, **`checksum`**, **`storeId`**, **`stage`**. Keep these in handoff or operator logs, not in the manifest itself.

## Fixing drift (allowed)

- **Journal is truth** — restore bundle prefix from last good commit / backup to match journal, then append new versions.
- **Disposable dev** — recreate stage or empty DB, re-apply from v1. **Not** for prod without operator decision.
- **Forbidden** — mutating or deleting rows in **`fusebase_schema_migrations`**, or DDL via **`executeIsolatedStoreSql`** to paper over mismatch.

## Checklist (every status / apply)

- [ ] Versions strictly increasing; one entry per version.
- [ ] Bundle assembled with **`buildSqlMigrationBundle(...)`** from exact file contents.
- [ ] **`checksum`** = SHA-256 of canonicalized migration SQL (`CRLF -> LF`, trailing whitespace trimmed) produced by **`buildSqlMigrationBundle(...)`**.
- [ ] Avoid manual checksum rewrites in manifests (`checksumNote`, server-only checksum hacks). If checksum mismatches, rebuild bundle from files via SDK helper and re-run status.
- [ ] No silent edits to already-applied files.
- [ ] **Prod:** **`getIsolatedStoreSqlMigrationStatus`** with the intended bundle (full bundle or metadata-only status probe) → then **`applyIsolatedStoreSqlMigrations`** with the full bundle; confirm **`canApply`** / **`pendingCount`**.
- [ ] Optional **`dryRun: true`** on apply, or **`expectedLastAppliedVersion` / `expectedLastAppliedChecksum`** on status or apply (409 if journal head moved). `dryRun` now validates the same bundle rules as real apply.
- [ ] On errors, read **`structuredIssues`** or **`data.issues`** before guessing.

## What prompts do not replace

**CI** (checksum verify script), **code review**, and **live status** — not chat memory. Require checksum verification to pass before done/deploy.

## Managed hosts (UUID / extensions)

Avoid **`CREATE EXTENSION pgcrypto`** on locked-down hosts; prefer **`gen_random_uuid()`** defaults on PG **13+** when available (see **`isolatedSql`** prompt).

## With `isolatedSql`

**`isolatedSql`** = CRUD, limits, snapshots, MCP vs SDK. **This prompt** = journal discipline only. Load **both** for schema work.
---

## Version

- **Version**: 1.1.4
- **Category**: specialized
- **Last synced**: 2026-05-09
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
