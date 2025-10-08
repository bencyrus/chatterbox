## Gateway File URL Injection

Status: current
Last verified: 2025-10-08

← Back to [`docs/gateway/README.md`](./README.md)

### Why this exists

- Provide user‑friendly file URLs without changing database schemas or PostgREST responses.

### How it works

- On successful JSON responses (`Content-Type` includes `application/json`), buffer and inspect the body.
- If a top‑level array named by `FILES_FIELD_NAME` exists and is non‑empty, POST `{ files: [...] }` to `FILE_SERVICE_URL + FILE_SIGNED_URL_PATH`.
- On success, add `PROCESSED_FILES_FIELD_NAME` with the service’s response while keeping the original JSON intact; on any error, restore the original body.

### Key code paths

- Body processing: [`gateway/internal/files/helpers.go`](../../gateway/internal/files/helpers.go)

  ```go
  fileops.ProcessFileURLsIfNeeded(ctx, cfg, resp)
  ```

- Injection logic: [`gateway/internal/files/processor.go`](../../gateway/internal/files/processor.go)

  ```go
  var generic map[string]any
  if err := json.Unmarshal(body, &generic); err != nil { return body, nil }
  filesRaw, ok := generic[cfg.FilesFieldName]
  if !ok { return body, nil }
  filesSlice, ok := filesRaw.([]any)
  if !ok || len(filesSlice) == 0 { return body, nil }
  // POST { files: [...] } to file service and inject cfg.ProcessedFilesFieldName
  ```

- Proxy integration: [`gateway/internal/proxy/proxy.go`](../../gateway/internal/proxy/proxy.go)

  ```go
  ModifyResponse: func(resp *http.Response) error {
      fileops.ProcessFileURLsIfNeeded(ctx, g.cfg, resp)
      return nil
  }
  ```

### Configuration (env)

- Required: `FILE_SERVICE_URL`, `FILE_SIGNED_URL_PATH`, `FILES_FIELD_NAME`, `PROCESSED_FILES_FIELD_NAME`.
- Optional: `HTTP_CLIENT_TIMEOUT_SECONDS` (default derived from config, e.g., `10`).

### Safety/behavior

- Only processes `application/json` responses containing the configured top‑level array.
- Does not fail the main request; original body is preserved on any error or non‑2xx from the files service.
- Updates `Content-Length` to match any mutated body.

### See also

- Auth refresh: [`./auth-refresh.md`](./auth-refresh.md)
- Files service: [`../files/README.md`](../files/README.md)
- Gateway index: [`./README.md`](./README.md)

### Example

```json
{
  "files": ["abc123", "def456"],
  "other": "fields"
}
// → Gateway adds { "processed_files": ... } while keeping "files"
```
