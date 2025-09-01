Files Service

Purpose

- Accept a list of file IDs and return URLs for client use. Current implementation returns a placeholder URL per item; swap in real signing later.

Endpoints

- POST `/signed_url`: body contains `{ "files": [ ... ] }`; responds with an array of `{ file_id, url }`. Empty/invalid entries are ignored.
- GET `/healthz`: liveness probe; responds `ok`.

Behavior

- Supports string and numeric IDs.
- Returns `[]` when there are no valid inputs.
- Logs include `request_id` if provided by upstream.

Configuration

- Optional: `PORT` (default `8080`). See [`internal/config/config.go`](internal/config/config.go).

Integration

- Called by the gateway only when an upstream JSON response includes a top‑level `files` array. Gateway injects the service response as `processed_files`.

References

- Handlers: [`cmd/files/main.go`](cmd/files/main.go)
- Config: [`internal/config/config.go`](internal/config/config.go)
- Logging/middleware: [`shared/logger`](../shared/logger), [`shared/middleware`](../shared/middleware)
