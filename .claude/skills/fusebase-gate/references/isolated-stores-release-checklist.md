---
version: "1.0.0"
mcp_prompt: none
source: "docs/isolated-stores-release-checklist.md"
last_synced: "2026-05-06"
title: "Isolated stores release checklist"
category: specialized
---
# Isolated stores release checklist

> **SOURCE**: This file is copied from `docs/isolated-stores-release-checklist.md` in the fusebase-gate repo. Edit that file, then run `npm run mcp:skills:generate`.

---
# Isolated stores release checklist

Short go/no-go checklist for releasing the current `Gate` isolated stores baseline.

## Blockers

- `Gate` registry visibility matches direct registry DB state in the target environment.
- `Studio` isolated stores list matches `listIsolatedStores` for the same org.
- `MCP` and SDK calls see the same stores and stages as `Studio`.

## Required

- End-to-end operator flow passes on the target environment:
  - `createIsolatedStore`
  - `initIsolatedStoreStage`
  - `getIsolatedStoreSqlMigrationStatus`
  - `applyIsolatedStoreSqlMigrations`
  - `createIsolatedStoreCheckpoint`
  - `restoreIsolatedStoreRevision`
- Azure Blob snapshot storage is enabled and verified:
  - `snapshotRef` is `azure-blob://...`
  - snapshot download works through `downloadIsolatedStoreRevisionSnapshot`
  - restore works from a blob-backed snapshot
- Generated SDK includes the current isolated-store ops, including snapshot download.
- OpenAPI / generated client artifacts are regenerated from the current contracts.
- Production env config is fixed and documented:
  - registry DB connection
  - isolated Postgres admin/runtime connection
  - snapshot storage provider config

## Operational checks

- Runbook exists for:
  - Azure Blob env setup
  - creating a checkpoint
  - downloading a dump
  - restoring a stage
- Basic monitoring or alerting exists for:
  - failed checkpoint
  - failed snapshot upload
  - failed restore
  - migration drift / apply failure
- Permission split is verified for:
  - runtime app token
  - operator token
  - MCP token

## Nice to have

- Clean repo-wide `tsc` baseline in `fusebase-gate`
- Snapshot retention / pruning workflow
- Backup/download visibility in Studio
- RLS enforcement layer for SQL stores

## Release recommendation

Release only after all blocker and required items are green in the target environment.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-05-06
