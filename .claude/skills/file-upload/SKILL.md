---
name: file-upload
description: "Canonical low-level Fusebase file upload lifecycle and file API guide. Use it when implementing temp -> stored -> display URL flows or building file descriptors for downstream apps."
---

# File Upload

This skill is the single source of truth for the low-level file upload lifecycle.
Load [Upload Lifecycle](references/upload-lifecycle.md) for the canonical `tempStoredFileName -> storedFileUUID -> readUrl / relative url -> file descriptor` flow.

## When NOT To Use This Skill

- Do not use this skill to describe how to write dashboard cell data. For dashboard `files` columns, load `fusebase-dashboards` and pass the already-uploaded file descriptor to `batchPutDashboardData`.
- Do not use this skill for Gate MCP operation auth, scopes, or operation discovery. For Gate `startMultipartFileUpload`, `completeMultipartFileUpload`, and `deleteFile`, load `fusebase-gate`.
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
