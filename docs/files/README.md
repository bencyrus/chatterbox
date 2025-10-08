## Files Service

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Resolve file identifiers into client‑consumable URLs without changing database schemas or PostgREST responses.
- Keep URL generation/signing concerns at the edge so the database remains focused on domain facts.

### Role in the system

- Stateless helper called by the gateway when upstream JSON includes a top‑level `files` array.
- Returns a JSON structure that the gateway injects as `processed_files` while preserving the original `files` field.

### How it works

- Endpoint behavior

  Source: [`files/cmd/files/main.go`](../../files/cmd/files/main.go)

  ```go
  mux := http.NewServeMux()
  mux.HandleFunc("/signed_url", handleSignedURL())
  mux.HandleFunc("/healthz", handleHealthz())
  handler := middleware.RequestIDMiddleware(mux)
  srv := &http.Server{Addr: ":" + cfg.Port, Handler: handler}
  ```

- Signed URL handler (placeholder implementation)

  Source: [`files/cmd/files/main.go`](../../files/cmd/files/main.go)

  ```go
  var body map[string]any
  if err := json.NewDecoder(r.Body).Decode(&body); err != nil { /* 400 */ }
  items, ok := body["files"].([]any)
  // Build [{ file_id, url }] with placeholder URL per item
  ```

### Behavior

- Supports string and numeric file IDs; ignores invalid/empty entries.
- Returns an empty array `[]` when no valid inputs are provided.
- Includes `request_id` in logs when forwarded by upstream via `X-Request-ID`.

### Operations

- Port: `PORT` (optional, default `8080`).
- Build/run: [`files/Dockerfile`](../../files/Dockerfile)

### Examples

- Request
  ```json
  { "files": ["abc123", 42] }
  ```
- Response (placeholder URLs)
  ```json
  [
    {
      "file_id": "abc123",
      "url": "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba"
    },
    {
      "file_id": 42,
      "url": "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba"
    }
  ]
  ```

### Future

- Replace placeholder URLs with real signing (e.g., S3, GCS, CDN). Not implemented.

### See also

- Gateway file URL injection: [`../gateway/files-injection.md`](../gateway/files-injection.md)
- Shared components: [`../shared/README.md`](../shared/README.md)
