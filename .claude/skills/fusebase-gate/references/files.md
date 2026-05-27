---
version: "1.10.0"
mcp_prompt: files
last_synced: "2026-04-29"
title: "Fusebase Gate Files Flows"
category: specialized
---
# Fusebase Gate Files Flows

> **MARKER**: `mcp-files-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `files` for latest content.

---
## Fusebase Gate Files Flows

This reference covers only Gate file operations and their auth/scope behavior. For the canonical low-level upload lifecycle, shared terminology, relative display URL normalization, and file descriptor construction, use `file-upload/references/upload-lifecycle.md`.

## Relevant Operations

- startMultipartFileUpload: start a public file-service multipart upload and return direct PUT metadata.
- completeMultipartFileUpload: finish the file-service multipart upload from ETags and create the stored-file record. Gate maps file-service `storedFile.uuid` to response `storedFileUUID`; `fileId` is the same stored-file id alias. Use `storedFileUUID` for notes attachments. The returned `readUrl` is the public file URL.
- deleteFile: delete a file-service stored file by `storedFileUUID`.

## Working Rules

- `startMultipartFileUpload` requires `filename` and byte `size`; `contentType` defaults to `application/octet-stream`, and `folder` defaults to `apps`.
- Gate never handles upload bytes. PUT the file bytes directly to the returned `uploadUrl` using the returned `method`.
- **Presigned URL headers rule**: Inspect `X-Amz-SignedHeaders` in each `uploadUrl` / `partsUrls` value. Send only headers listed there. If it is `X-Amz-SignedHeaders=host`, send a bare PUT with no custom headers.
- In browser code, avoid `Content-Type` on the direct PUT unless it is signed. Prefer an `ArrayBuffer`/raw bytes body instead of a typed `Blob` so the browser does not include `Content-Type` in the CORS preflight request.
- A cross-origin browser `PUT` can still preflight because `PUT` is not a CORS simple method. Keep requested headers aligned with the presigned URL and bucket CORS policy.
- Capture the direct PUT response ETag, strip wrapping quotes if present, and send it to `completeMultipartFileUpload` as `parts: [{ etag, partNumber: 1 }]` for one-part uploads.
- Treat the temp upload name as `tempStoredFileName` in guidance and handoffs. Follow `tools_describe`/SDK schema for the exact request field name required by the current Gate contract.
- `completeMultipartFileUpload` always creates the stored-file record after file-service finish succeeds. Persist `storedFileUUID` as the canonical stored-file id, plus `publicFileName` and `readUrl`.
- Use the returned Gate `readUrl` for reads or image `src`. If another upload flow returns a relative `file.url` such as `/uuid/name.ext`, do not render or persist it as a browser href directly; normalize it through the file-upload display URL rule before saving descriptors or rendering existing descriptors.
- Use the returned `storedFileUUID` with notes `addWorkspaceNoteAttachment` to attach the file to a note.
- `deleteFile` calls file-service as `DELETE /storedfiles/{uuid}`. Use the `storedFileUUID` returned by completion, not `tempStoredFileName`.
- Do not send block ids, storage-provider-specific headers, unsigned `Content-Type`, visibility, public URL, or read access mode fields.
- Do not describe dashboard `files` column payloads here; after Gate completion, hand off the file descriptor or `readUrl` to the owning skill.

## Access Model

- Upload, multipart, and delete flows require `files.write` and org access.
- Gate delegates upload URLs to file-service and returns `readUrl` from the completion flow; actual bytes never flow through Gate.
---

## Version

- **Version**: 1.10.0
- **Category**: specialized
- **Last synced**: 2026-04-29
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
