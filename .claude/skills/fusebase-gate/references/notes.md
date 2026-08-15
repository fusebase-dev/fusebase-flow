---
version: "1.6.1"
mcp_prompt: notes
last_synced: "2026-08-12"
title: "Fusebase Gate Notes Operations"
category: specialized
---
# Fusebase Gate Notes Operations

> **MARKER**: `mcp-notes-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `notes` for latest content.

---
## Table of contents

- [Fusebase Gate Notes Operations](#fusebase-gate-notes-operations)
- [Relevant Operations](#relevant-operations)
- [Identity And Scoping Rules](#identity-and-scoping-rules)
- [Read Flow Rules](#read-flow-rules)
- [Create Flow Rules](#create-flow-rules)
- [Append Flow Rules](#append-flow-rules)
- [Attachment Flow Rules](#attachment-flow-rules)
- [Access Model](#access-model)
- [Markdown (v3) Note Rules](#markdown-v3-note-rules)
- [Directive Widgets (markdown-native UI)](#directive-widgets-markdown-native-ui)
- [Working Rules](#working-rules)

---
## Fusebase Gate Notes Operations

These operations manage workspace note folders, workspace notes, note reads, note creation, append-only note content updates, and stored-file attachment flows exposed by Gate.

## Relevant Operations

- listWorkspaceNoteFolders lists visible non-portal note folders for a workspace.
- listWorkspaceNotes lists visible non-portal notes for a workspace folder.
- getWorkspaceNote returns one workspace note together with markdown content.
- createWorkspaceNoteFolder creates a workspace note folder.
- createWorkspaceNote creates a workspace note and can optionally append initial content after creation.
- appendWorkspaceNoteContent appends text or html to the end of an existing workspace note without replacing existing content.
- addWorkspaceNoteAttachment attaches a `storedFileUUID` to a workspace note and appends the matching editor blot.
- createWorkspaceMarkdownNote creates a v3 note whose source of truth is markdown stored in note-service.
- getWorkspaceMarkdownNote reads a v3 note's markdown and current `revision`.
- updateWorkspaceMarkdownNoteContent replaces the whole markdown document of a v3 note using an optimistic `revision` lock.
- appendWorkspaceMarkdownNoteContent appends markdown to a v3 note with an optional `revision` lock.
- addWorkspaceMarkdownNoteAttachment attaches a `storedFileUUID` to a v3 note and appends the matching markdown image or link.

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
- `format` defaults to `text`, which stores content literally. Markdown syntax (`#`, `**`, `>`) sent as `text` appears as raw characters in the editor.
- When initial note content comes from Markdown, convert Markdown to HTML app-side and call `createWorkspaceNote` with `format: html`.
- Use `format: text` only for plain text where literal Markdown characters are intended.
- `createWorkspaceNote` returns note summary metadata, not the final note body. Call `getWorkspaceNote` afterward when you need the resulting markdown.

## Append Flow Rules

- `appendWorkspaceNoteContent` requires a known `noteId` and non-empty `content`.
- It always appends to the end of the existing note. Do not use it for replacement or full-document editing.
- `format` defaults to `text`, which stores content literally. Markdown syntax (`#`, `**`, `>`) sent as `text` appears as raw characters in the editor.
- Gate reads note bodies as markdown via `getWorkspaceNote`, but editor-server append writes currently accept text or html, not a dedicated md body.
- For Markdown input, convert Markdown to HTML in the app and call `appendWorkspaceNoteContent` with `format: html`. Do not send user-authored Markdown as `format: text` unless raw Markdown characters are the desired output.
- Editor fidelity is not 1:1: headings, bold, italic, inline code, ordered/unordered lists, and links survive normal HTML paste; markdown blockquotes (`>`, rendered as `<blockquote>`) can degrade to plain paragraphs because of editor limitations.
- `appendWorkspaceNoteContent` returns the refreshed note metadata and `note.md` after the append.

## Attachment Flow Rules

- Upload files with the files operations first. Complete the upload and use the returned `storedFileUUID` for attachment creation. In Gate file responses this is file-service `storedFile.uuid` exposed as `storedFileUUID`; `fileId` is only an alias. Use the completion `readUrl` for direct file reads or image `src`.
- `addWorkspaceNoteAttachment` creates the note-service attachment and then appends an editor blot. It is v2-only — for a v3 markdown note use `addWorkspaceMarkdownNoteAttachment`, which never touches the editor document.
- Image attachments are inserted as `image` blots. All other attachment types are inserted as `file` blots.
- The operation returns attachment metadata, not the full note body. Call `getWorkspaceNote` when you need refreshed markdown.

## Access Model

- Classic (v2) note reads require `notes.read` and org access.
- Classic (v2) note creation, content append, and attachment writes require `notes.write` and org access.
- Markdown (v3) note reads require `notes.markdown.read` and org access.
- Markdown (v3) note creation, content replacement, content append, and attachment writes require `notes.markdown.write` and org access.
- Markdown (v3) note operations also require the Gate env feature flag `notes_markdown`; when it is off, the operations fail closed.
- Tokens that only have `notes.read`/`notes.write` must use the classic (v2) note operations.
- If note-service or editor-server writes fail, verify caller permissions and workspace scope before assuming a schema mismatch.

## Markdown (v3) Note Rules

- Markdown ops only work on notes created with `createWorkspaceMarkdownNote`. Classic (v2) notes keep using `getWorkspaceNote`, `createWorkspaceNote`, and `appendWorkspaceNoteContent`.
- Markdown is stored literally as the source of truth; no HTML conversion is needed or supported on these ops. Send real markdown, not HTML.
- Every markdown response includes `note.revision`. Save it: `updateWorkspaceMarkdownNoteContent` requires the last-read `revision`, and `appendWorkspaceMarkdownNoteContent` accepts it optionally.
- On HTTP 409 (`data.errorCode` = markdown_note_revision_conflict) the stored content changed since your read. Re-read with `getWorkspaceMarkdownNote` (or use `data.currentRevision`), reconcile, and retry the write.
- Use update for full-document rewrites and append for adding to the end; do not emulate append by rewriting the whole document.
- Attach files with `addWorkspaceMarkdownNoteAttachment`; it appends the markdown itself and returns the canonical attachment `url` plus the appended `markdown` snippet, so never hand-build the link format. To place the attachment somewhere other than the end, take that `url` and rewrite the document with `updateWorkspaceMarkdownNoteContent` using the returned `note.revision`.

## Directive Widgets (markdown-native UI)

Fusebase v3 notes may contain remark leaf/container directives that the Notes UI renders as widgets. Prefer these over inventing HTML or JSON blobs. The markdown string is the only widget state — there is no separate widget API.

**Scope:** widgets render only in v3 markdown notes. Write them with `createWorkspaceMarkdownNote`, `updateWorkspaceMarkdownNoteContent`, or `appendWorkspaceMarkdownNoteContent`. Never use classic v2 `createWorkspaceNote` / `appendWorkspaceNoteContent` (HTML) for widgets.

**How to edit:** `getWorkspaceMarkdownNote` → change the directive line's `[label]` and `{attrs}` in the markdown → `updateWorkspaceMarkdownNoteContent` with the last-read `revision`. To add widgets at the end of a note, append the directive lines with `appendWorkspaceMarkdownNoteContent`.

**Pick the right widget:**
- `::progress` — filled share toward a goal (`value` / `max`).
- `::rating` — discrete score (stars / hearts / thumbs).
- `::kpi` — a single metric number with optional `unit` and `trend`.
- `::badge` — short status chip with a tone.
- `:::collapse` — hide secondary markdown behind a title.

Syntax (put each leaf directive on its own line; container = `:::name[title]` … `:::`):

    ::progress[Label]{value=0 max=100 color="auto|neutral|info|success|warning|danger" thickness="thin|medium|thick"}
    ::rating[Label]{value=1 max=5 icon="star|heart|thumbsUp"}
    ::kpi[Label]{value=0 unit="items" trend="+1"}
    ::badge[Label]{tone="neutral|info|success|warning|danger"}

    :::collapse[Title]
    Hidden markdown body (lists, code, nested markdown OK).
    :::

- `[Label]` / `[Title]` is human-readable text stored in the directive itself; keep it short. For collapse, set the title only via markdown (the UI does not edit the summary).
- Keep `value` and `max` numeric. Omit attrs you do not need — do not write empty values like `unit=""`.
- Quoted and unquoted attrs both parse (`{value=72}` and `{value="72"}`); the editor may rewrite them with quotes on save.
- Defaults when an attr is omitted: progress `max=100`, `color`→neutral, `thickness`→medium; rating `max=5`, `icon`→star; badge `tone`→neutral. A rating `max` is capped at 10 in the UI.
- Prefer writing attrs the UI understands; unknown attrs still round-trip, and an unknown tone/colour/icon/thickness falls back to the default above instead of breaking the note.
- Do not convert these widgets to HTML; send the directive forms above in markdown ops only.
- `color="auto"` on progress picks danger (<34%), warning (<67%), or success from the filled percentage.
- kpi `unit` and `trend` are free text; `trend` reads as up when it starts with `+` and down when it starts with `-`; anything else is neutral.
- Collapse open/closed is editor UI state only — it is not written to markdown and resets on reload.
- Text directives (`:name`) and leaf `::name` directives other than progress/rating/kpi/badge are not widgets; leave them as literal text. Unknown `:::name` containers may render as callouts, not as collapse.

## Working Rules

- Always inspect the exact contract with `tools_describe` or `sdk_describe` before integration work.
- Before creating notes in an unspecified/default workspace, call `listWorkspaces` and use the default workspace's real `id` instead of building note URLs with `/workspaces/default`.
- For root note creation or listing, prefer omitting `parentId` instead of inventing a folder id.
- For v3 markdown notes (including directive widgets), use the markdown ops (`createWorkspaceMarkdownNote` / `getWorkspaceMarkdownNote` / `updateWorkspaceMarkdownNoteContent` / `appendWorkspaceMarkdownNoteContent`), not the classic v2 create/append ops.
- If the caller needs note content after a classic v2 create, follow `createWorkspaceNote` with `getWorkspaceNote`.
- If the caller wants to add content to an existing classic v2 note, use `appendWorkspaceNoteContent` instead of creating a replacement note.
---

## Version

- **Version**: 1.6.1
- **Category**: specialized
- **Last synced**: 2026-08-12
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
