# Upload Lifecycle

This reference is the canonical source for the Fusebase file upload lifecycle.
Use the same terminology everywhere: `tempStoredFileName`, `storedFileUUID`, `readUrl`, `relative url`, and `file descriptor`.

## Canonical Flow

1. Create a temp file and capture `tempStoredFileName`.
2. Create a stored file from `tempStoredFileName` and capture `storedFileUUID`.
3. Build or read the display URL:
   - `readUrl` is an absolute URL returned by Gate completion flows.
   - `relative url` is a stored file path that must be prefixed before display.
4. Pass a file descriptor to the next layer.

<!-- CUSTOM:SKILL:BEGIN -->
## Flow Selection Rule

- Use the `web-editor/file/v2-upload` -> `bucket-files/create-relative` flow for files uploaded as note attachments.
- Use the Gate `startMultipartFileUpload` -> direct `PUT` -> `completeMultipartFileUpload` flow for non-note file uploads.
- When a note needs a readable image/file URL after upload, keep the note attachment lifecycle on the web-editor flow and use the resulting file descriptor or URL returned by that flow.
<!-- CUSTOM:SKILL:END -->

## Presigned PUT Headers

For every direct `PUT` to a presigned S3 URL, inspect `X-Amz-SignedHeaders` in the URL before adding request headers.

- If the URL has `X-Amz-SignedHeaders=host`, send a bare `PUT` with no custom headers:

  ```typescript
  await fetch(uploadUrl, { method: "PUT", body: bytes });
  ```

- Do not add `Content-Type`, storage-provider headers, or other custom headers unless they are explicitly listed in `X-Amz-SignedHeaders` or returned by the upload API as required headers.
- In browser code, prefer `ArrayBuffer`/raw bytes for the body. A typed `Blob` or an explicit `Content-Type` can cause the browser to include `Content-Type` in the CORS preflight request; if the bucket CORS rules do not allow that header, `fetch` may fail with a generic network error before the `PUT` response is visible.
- A cross-origin browser `PUT` can still preflight because `PUT` is not a CORS simple method. The important rule is to keep the requested headers aligned with the presigned URL and bucket CORS policy.

## Create A Temp File

For files smaller than 50 MB, send multipart/form-data to:

`POST https://app-api.{FUSEBASE_HOST}/v3/api/web-editor/file/v2-upload`

Required fields:

- `file`: the file bytes
- `folder`: `apps`

Response:

```json
{
  "name": "notes/119/1766749985-f5Ai3b/file.docx",
  "type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "filename": "file.docx",
  "size": 16511
}
```

The response includes `name`; treat it as `tempStoredFileName`.
Use that value for the stored-file step.

For files 50 MB or larger, use multipart upload against the same endpoint:

1. Start with `action=start`, `folder=apps`, `name`, `type`, and `size`.
2. Upload each chunk to the returned part URL with `PUT`.
3. Finish with `action=finish`, uploaded `parts`, `uploadingId`, and `tempStoredFileName`.

Start request fields:

- `action`: `start`
- `folder`: `apps`
- `name`: original file name
- `type`: MIME type
- `size`: file size in bytes

Start response:

```json
{
  "id": "rTuydPY3YaUR5rZ1kk3",
  "partsUrls": [
    "https://s3-bucket.s3-eu-central-1.amazonaws.com/notes/119/1766750238-wqXiUD/recording.mov?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=..."
  ],
  "partSize": 52428800,
  "tempStoredfileName": "notes/119/1766750238-wqXiUD/recording.mov"
}
```

API quirk: some legacy responses/fields spell this as `tempStoredfileName` with a lowercase `f`. Treat that value as canonical `tempStoredFileName` in guidance and handoffs, but send the exact field name required by the endpoint or SDK schema you are calling.

Finish request fields:

- `action`: `finish`
- `parts`: JSON array of uploaded parts, each with `etag` and `partNumber`
- `uploadingId`: `id` from the start response
- `tempStoredfileName`: temp name from the start response, if this endpoint expects the legacy casing

Each chunk should be retried up to 3 times before failing the upload.

Example large-file helper:

```typescript
const UPLOAD_URL =
  "https://app-api.{FUSEBASE_HOST}/v3/api/web-editor/file/v2-upload";
const CHUNK_RETRIES = 3;

async function uploadLargeFile(
  file: File,
  appToken: string,
  onProgress?: (loaded: number, total: number) => void,
): Promise<{ tempStoredFileName: string } | null> {
  const startForm = new FormData();
  startForm.append("action", "start");
  startForm.append("folder", "apps");
  startForm.append("name", file.name);
  startForm.append("type", file.type);
  startForm.append("size", String(file.size));

  const startRes = await fetch(UPLOAD_URL, {
    method: "POST",
    headers: { "x-app-feature-token": appToken },
    body: startForm,
  });
  if (!startRes.ok) return null;
  const { id, partsUrls, partSize, tempStoredfileName } =
    await startRes.json();

  const progress = new Array(partsUrls.length).fill(0);

  const uploadChunk = async (
    url: string,
    index: number,
  ): Promise<{ etag: string; partNumber: number }> => {
    const chunk = file.slice(index * partSize, (index + 1) * partSize);
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < CHUNK_RETRIES; attempt++) {
      try {
        const res = await fetch(url, { method: "PUT", body: chunk });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);

        const etag = JSON.parse(res.headers.get("etag") ?? '""');
        if (!etag) throw new Error("Missing etag");

        if (onProgress) {
          progress[index] = chunk.size;
          onProgress(
            progress.reduce((a, b) => a + b, 0),
            file.size,
          );
        }

        return { etag, partNumber: index + 1 };
      } catch (err) {
        lastError = err instanceof Error ? err : new Error(String(err));
      }
    }

    throw new Error(
      `Chunk ${index} failed after ${CHUNK_RETRIES} attempts: ${lastError?.message}`,
    );
  };

  const parts = await Promise.all(
    partsUrls.map((url: string, index: number) => uploadChunk(url, index)),
  );

  const finishForm = new FormData();
  finishForm.append("action", "finish");
  finishForm.append("parts", JSON.stringify(parts));
  finishForm.append("uploadingId", id);
  finishForm.append("tempStoredfileName", tempStoredfileName);

  const finishRes = await fetch(UPLOAD_URL, {
    method: "POST",
    headers: { "x-app-feature-token": appToken },
    body: finishForm,
  });
  if (!finishRes.ok) return null;

  const result = await finishRes.json();
  return {
    tempStoredFileName: result.tempStoredFileName ?? result.tempStoredfileName,
  };
}
```

## Create A Stored File

After temp upload, create the stored file:

`POST https://app-api.{FUSEBASE_HOST}/v4/api/bucket-files/create-relative`

JSON body:

```json
{
  "tempStoredFileName": "NAME_FROM_TEMP_STEP",
  "folder": "apps"
}
```

The response includes `attachment.storedFileUUID` and file metadata. Use `storedFileUUID` as the stored file id in downstream APIs.

Gate note: file-service stored-file JSON uses `uuid`; Gate file operations expose that same value as `storedFileUUID` and may also return `fileId` as an alias. In guidance and handoffs, prefer `storedFileUUID`.

Stored-file response shape:

```json
{
  "bucket": {
    "globalId": "string",
    "userId": 0,
    "workspaceId": "string",
    "target": "string",
    "targetId": "string",
    "groupId": "string",
    "activeItems": 0,
    "clock": 0,
    "deleted": false
  },
  "attachment": {
    "globalId": "string",
    "bucketId": "string",
    "userId": 0,
    "workspaceId": "string",
    "filename": "string",
    "storedFileUUID": "string",
    "kind": "file",
    "type": "string",
    "size": 0,
    "extra": {},
    "clock": 0,
    "deleted": false,
    "updatedAt": 0,
    "createdAt": 0,
    "noteServiceAttachment": true
  },
  "file": {
    "globalId": "string",
    "bucketId": "string",
    "target": "task",
    "targetId": "string",
    "portalId": "string",
    "orgId": "string",
    "workspaceId": "string",
    "filename": "string",
    "type": "image",
    "format": "string",
    "userId": 0,
    "size": 0,
    "createdAt": 0,
    "deleted": false,
    "url": "string",
    "extra": {}
  }
}
```

## Display URLs

If the upload API returns a `relative url` or a `file.url` that starts with `/`, prepend:

`https://app.{FUSEBASE_HOST}/box/file`

Never put a relative stored-file URL directly into an `<a href>`, image `src`, or persisted downstream `file descriptor.url`. Browsers resolve `/uuid/name.ext` against the current app host, which can point at the wrong service and return 404.

Example:

```typescript
function buildFileHref(url: string): string {
  if (/^https?:\/\//.test(url)) return url;
  return `https://app.{FUSEBASE_HOST}/box/file${url}`;
}
```

If Gate returns `readUrl`, use it as-is for reads, links, or image `src`.

## File Descriptor

A file descriptor is the object passed to downstream apps after upload. Include fields returned by the stored-file response when available:

- `name`
- `url`
- `type`
- `size`
- `globalId`
- `bucketId`
- `userId`
- `workspaceId`
- `storedFileUUID`
- `kind`

For `url`, store a display-ready URL. If the stored-file response gives a relative `file.url`, normalize it with `buildFileHref` before saving a new descriptor, and also apply the same helper when rendering already-saved descriptors so legacy relative URLs still open correctly.

The dashboard adapter uses this descriptor inside a `files` column value. Gate adapters may also expose `fileId`, `publicFileName`, and `readUrl`; those are Gate operation outputs, not a separate lifecycle.

## Handoffs

- Dashboard `files` column: use `fusebase-dashboards`; pass the file descriptor to `batchPutDashboardData`.
- Gate MCP/SDK upload operations: use `fusebase-gate`; it owns `startMultipartFileUpload`, `completeMultipartFileUpload`, `deleteFile`, and their auth/scope rules.
