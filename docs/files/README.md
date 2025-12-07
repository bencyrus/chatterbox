## Files Service

Status: current
Last verified: 2025-12-07

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Resolve file identifiers into client‑consumable, short‑lived URLs without changing database schemas or PostgREST responses.
- Keep URL generation/signing concerns at the edge so the database remains focused on domain facts.

### Role in the system

- HTTP service called by the gateway when upstream JSON includes a top‑level `files` array.
- Looks up file metadata in Postgres, generates signed Google Cloud Storage (GCS) download URLs, and returns a JSON structure that the gateway injects as `processed_files` while preserving the original `files` field.

### How it works

- HTTP server and routing

  Source: [`files/cmd/files/main.go`](../../files/cmd/files/main.go)

  - Initializes a `Server` from [`files/internal/httpserver/server.go`](../../files/internal/httpserver/server.go) with configuration and a DB client from [`files/internal/database/client.go`](../../files/internal/database/client.go).
  - Registers:
    - `GET /healthz` (public, no authentication).
    - `POST /signed_url` (protected by an internal API key).
  - Wraps the mux with:
    - `WithAPIKeyAuth` to enforce `FILE_SERVICE_API_KEY` on all non‑health requests.
    - Shared `RequestIDMiddleware` for consistent request IDs and logging.

- Signed URL flow

  - Gateway discovers a top‑level `files` array in a JSON response and POSTs:

    ```json
    { "files": [1, 2, 3] }
    ```

    to `FILE_SERVICE_URL + FILE_SIGNED_URL_PATH` with an `X-File-Service-Api-Key` header.

  - The files service:
    - Normalizes the `files` entries into a list of `int64` IDs.
    - Calls `files.lookup_files(bigint[])` (see [`postgres/migrations/1756075300_files_service.sql`](../../postgres/migrations/1756075300_files_service.sql)) to obtain per‑file metadata (placeholder implementation for now).
    - Uses a GCS service account (email + private key) and bucket config to generate V4 signed `GET` URLs via [`files/internal/gcs/gcs.go`](../../files/internal/gcs/gcs.go).
    - Returns an array of `{ "file_id": <id>, "url": "<signed_url>" }` objects.

### Behavior

- Supports numeric file IDs (e.g. `bigint` primary keys) and string IDs that can be parsed as integers; ignores invalid/empty entries.
- Returns an empty array `[]` when no valid inputs are provided or when no signed URLs can be generated.
- Includes `request_id` in logs when forwarded by upstream via `X-Request-ID`.
- Requires a valid `X-File-Service-Api-Key` header on all non‑health requests; callers without the key receive `403 Forbidden`.

### Operations

- Port: `PORT` (optional, default `8080` in the service; mapped to `9090` in `docker-compose`).
- Build/run: [`files/Dockerfile`](../../files/Dockerfile)
- Database:
  - `DATABASE_URL` points at Postgres as `files_service_user` (created in [`postgres/migrations/1756075300_files_service.sql`](../../postgres/migrations/1756075300_files_service.sql)).
  - Uses `files.lookup_files(bigint[])` to resolve IDs to metadata; today this is a stub that returns placeholder bucket/object information.
- GCS signing:
  - `GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_EMAIL`
  - `GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_PRIVATE_KEY`
  - `GCS_CHATTERBOX_BUCKET`
  - `GCS_CHATTERBOX_SIGNED_URL_TTL_SECONDS` (e.g. `900` seconds)
- Internal authentication:
  - `FILE_SERVICE_API_KEY` is a shared secret between gateway and files.
  - Gateway sends this value as `X-File-Service-Api-Key` on all `/signed_url` calls.

Example configuration template: [`secrets/.env.files.example`](../../secrets/.env.files.example)

### Examples

- Request from gateway to files:

  ```http
  POST /signed_url HTTP/1.1
  Host: files
  Content-Type: application/json
  X-File-Service-Api-Key: file_service_api_key

  { "files": [1, 2] }
  ```

- Response (shape)

  ```json
  [
    {
      "file_id": 1,
      "url": "https://storage.googleapis.com/<bucket>/<object_key>?X-Goog-Algorithm=GOOG4-RSA-SHA256&..."
    },
    {
      "file_id": 2,
      "url": "https://storage.googleapis.com/<bucket>/<object_key>?X-Goog-Algorithm=GOOG4-RSA-SHA256&..."
    }
  ]
  ```

### Future

- Extend the `files.file` / `files.file_metadata` model to cover more asset types (user uploads, etc.).
- Support additional operations such as generating upload URLs directly from the files service if needed.

### See also

- Gateway file URL injection: [`../gateway/files-injection.md`](../gateway/files-injection.md)
- Shared components: [`../shared/README.md`](../shared/README.md)
