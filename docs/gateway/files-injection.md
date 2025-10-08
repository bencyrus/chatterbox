## Gateway File URL Injection

Purpose

- Enrich JSON responses by resolving file IDs to URLs when the payload includes a top‑level files array.

How it works

- The reverse proxy inspects successful JSON responses; if `Content-Type` includes `application/json`, it buffers the body.
- It unmarshals to a generic object and checks for a top‑level array named by `FILES_FIELD_NAME`.
- If present (and non‑empty), it POSTs `{ files: [...] }` to the files service at `FILE_SERVICE_URL + FILE_SIGNED_URL_PATH`.
- On success, it adds a field named by `PROCESSED_FILES_FIELD_NAME` to the original object with the service’s JSON response and re‑serializes the body.
- On any error, it restores the original body unmodified.

Key code paths

- Body processing: `internal/files/helpers.go` → `ProcessFileURLsIfNeeded` (safely replace/restore body and `Content-Length`).
- Injection logic: `internal/files/processor.go` → `InjectSignedFileURLs` (detects field, calls service, mutates JSON object).
- Proxy integration: `internal/proxy/proxy.go` → `ModifyResponse` calls the helpers.

Configuration (env)

- `FILE_SERVICE_URL` (required): files service base URL.
- `FILE_SIGNED_URL_PATH` (required): path to signed URL endpoint (e.g., `/signed_url`).
- `FILES_FIELD_NAME` (required): name of the top‑level array (e.g., `files`).
- `PROCESSED_FILES_FIELD_NAME` (required): field name to inject (e.g., `processed_files`).
- `HTTP_CLIENT_TIMEOUT_SECONDS` (optional): timeout for the call to the files service.

Safety/behavior

- Only processes `application/json` responses containing the configured top‑level array.
- Does not fail the main request; on any error or non‑2xx from the files service, the original body is preserved.
- `Content-Length` header is updated to match any mutated body.

Navigate

- Auth refresh: [`./auth-refresh.md`](./auth-refresh.md)
- Files service: [`../files/README.md`](../files/README.md)
- Gateway index: [`./README.md`](./README.md)
