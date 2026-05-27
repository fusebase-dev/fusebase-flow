---
version: "1.2.0"
mcp_prompt: notes
last_synced: "2026-04-28"
title: "Fusebase Gate Notes Operations"
category: specialized
---
# Fusebase Gate Notes Operations

> **MARKER**: `mcp-notes-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `notes` for latest content.

---
## Fusebase Gate Notes Operations

These operations manage workspace note folders, workspace notes, note reads, note creation, and stored-file attachment flows exposed by Gate.

## Relevant Operations

- listWorkspaceNoteFolders lists visible non-portal note folders for a workspace.
- listWorkspaceNotes lists visible non-portal notes for a workspace folder.
- getWorkspaceNote returns one workspace note together with markdown content.
- createWorkspaceNoteFolder creates a workspace note folder.
- createWorkspaceNote creates a workspace note and can optionally append initial content after creation.
- addWorkspaceNoteAttachment attaches a `storedFileUUID` to a workspace note and appends the matching editor blot.

## Identity And Scoping Rules

- Treat `orgId` and `workspaceId` as required path inputs for every notes operation.
- Treat `workspaceId`, `parentId`, and `noteId` as opaque ids. Reuse values returned by previous responses instead of inventing them.
- When a user says "default workspace", interpret that as the organization's default workspace id, not the literal string `default`.
- For notes operations, call `listWorkspaces`, find the workspace with `isDefault: true`, and use its real `id` value.
- Gate accepts the literal path alias `workspaceId: "default"` as a compatibility fallback, but do not choose it when you can discover the real workspace id.
- When `parentId` is omitted for list or create flows, Gate defaults to the workspace root folder id `default`.

## Read Flow Rules

- Use `listWorkspaceNoteFolders` before browsing nested folders when the caller does not already know a folder id.
- `listWorkspaceNotes` returns notes for one parent folder at a time. Omit `parentId` to read the root folder.
- `getWorkspaceNote` is the operation that returns note body content through `note.md`.
- Workspace attachment image links inside `note.md` remain editor attachment paths; use the files completion `readUrl` when you need the public object URL.
- Portal-shared and trashed notes are filtered out from these workspace note list operations.

## Create Flow Rules

- `createWorkspaceNoteFolder` requires a non-empty `title` and optionally accepts `parentId`.
- `createWorkspaceNote` requires a non-empty `title` and optionally accepts `parentId`, `content`, and `format`.
- `format` is only valid when `content` is provided.
- `format` defaults to `text`. Use `html` only when you are intentionally sending html content for the initial paste step.
- `createWorkspaceNote` returns note summary metadata, not the final note body. Call `getWorkspaceNote` afterward when you need the resulting markdown.

## Attachment Flow Rules

- Upload files with the files operations first. Complete the upload and use the returned `storedFileUUID` for attachment creation. In Gate file responses this is file-service `storedFile.uuid` exposed as `storedFileUUID`; `fileId` is only an alias. Use the completion `readUrl` for direct file reads or image `src`.
- `addWorkspaceNoteAttachment` creates the note-service attachment and then appends an editor blot.
- Image attachments are inserted as `image` blots. All other attachment types are inserted as `file` blots.
- The operation returns attachment metadata, not the full note body. Call `getWorkspaceNote` when you need refreshed markdown.

## Access Model

- Note reads require `notes.read` and org access.
- Note creation and attachment writes require `notes.write` and org access.
- If note-service or editor-server writes fail, verify caller permissions and workspace scope before assuming a schema mismatch.

## Working Rules

- Always inspect the exact contract with `tools_describe` or `sdk_describe` before integration work.
- Before creating notes in an unspecified/default workspace, call `listWorkspaces` and use the default workspace's real `id` instead of building note URLs with `/workspaces/default`.
- For root note creation or listing, prefer omitting `parentId` instead of inventing a folder id.
- If the caller needs note content after create, follow `createWorkspaceNote` with `getWorkspaceNote`.
---

## Version

- **Version**: 1.2.0
- **Category**: specialized
- **Last synced**: 2026-04-28
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
