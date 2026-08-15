---
name: file-upload
description: "Canonical low-level Fusebase file upload lifecycle and file API guide. Use it when implementing temp -> stored -> display URL flows or building file descriptors for downstream apps."
---

# File Upload

This skill is the single source of truth for the low-level file upload lifecycle.
Load [Upload Lifecycle](references/upload-lifecycle.md) for the canonical `tempStoredFileName -> storedFileUUID -> readUrl / relative url -> file descriptor` flow.

## Hard rules

- **Never** store user file/binary bytes in a FuseBase PostgreSQL isolated store (`base64` / `bytea` / data URL), including “MVP” shortcuts. Upload with this skill / Gate files ops; persist only `storedFileUUID`, `readUrl`, and small metadata in SQL or dashboard cells.
- Needing **`files.write`** is **not** a reason to put attachments in SQL. Sync Gate permissions (`fusebase app update <appId> --sync-gate-permissions`) instead.
- **Visitor / anonymous / public-link apps:** browser visitor tokens usually cannot call `files.write`. Broker upload on the **app feature backend** with `FBS_FEATURE_TOKEN`, then return `storedFileUUID` / `readUrl` to the client.
- Ordinary isolated-SQL write/`execute` paths are **not** the 64MiB `importIsolatedStoreSqlRows` cap — practical bodies are ~100–150 KB. Do not design attachments against SQL payload size.

## When NOT To Use This Skill

- Do not use this skill to describe how to write dashboard cell data. For dashboard `files` columns, load `fusebase-dashboards` and pass the already-uploaded file descriptor to `batchPutDashboardData`.
- Do not use this skill for Gate MCP operation auth, scopes, or operation discovery. For Gate `startMultipartFileUpload`, `completeMultipartFileUpload`, and `deleteFile`, load `fusebase-gate` (prompt/reference **`files`**).
- Do not copy upload endpoint or payload blocks into neighboring skills. Link to [Upload Lifecycle](references/upload-lifecycle.md) and keep only a short handoff.

## Scope

- Owns: temp file creation, stored file creation, display URL rules, and file descriptor terminology.
- Neighbor skills: `fusebase-dashboards` owns dashboard `files` cell writes; `fusebase-gate` owns Gate operation names, auth, and scope.
- Required terminology: `tempStoredFileName`, `storedFileUUID`, `readUrl`, `relative url`, `file descriptor`.

## Anti-Overlap Checklist

- [ ] Keep this skill focused on low-level lifecycle and file APIs.
- [ ] Link neighboring skills instead of duplicating their API blocks.
- [ ] Use one handoff sentence when another skill owns the next step.
- [ ] Do not describe dashboard `batchPutDashboardData` payloads here.
- [ ] Do not describe Gate auth/scope rules here.
- [ ] Never recommend SQL blob / base64 attachment storage.
