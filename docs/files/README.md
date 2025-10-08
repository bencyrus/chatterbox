## Files Service

Purpose

- Resolve file identifiers into URLs for client use; called by the gateway when upstream JSON includes a top‑level files array.

Philosophy

- Keep business state and orchestration in Postgres; keep edge concerns (auth, URL shaping) at the boundary.
- The gateway sees the full JSON responses and is the best place to enrich them non‑intrusively. By passing just a `files` array to a dedicated helper, we:
  - Avoid coupling API schemas to provider details for signing.
  - Keep the worker and supervisors focused on domain facts, not file IO.
  - Allow swapping URL signing strategies (S3, GCS, CDN) without changing database functions.
- This small service is intentionally stateless and easy to harden; it produces URLs based on IDs the API already surfaced.

Endpoints

- POST `/signed_url`: body `{ "files": [ ... ] }` → returns an array of `{ file_id, url }`.
- GET `/healthz`: liveness probe; returns `ok`.

Behavior

- Supports string and numeric IDs; ignores invalid/empty entries.
- Returns `[]` when no valid inputs are provided.
- Logs include `request_id` when forwarded from the gateway.

Integration with PostgREST flow

- The database (via PostgREST) returns response objects that may include a top‑level `files` array of opaque IDs.
- The gateway, after proxying the request to PostgREST, inspects JSON and, if `files` exists, calls this service.
- The gateway then injects `processed_files` into the same JSON payload and forwards the response.
- No DB schema changes are required to add or remove URL enrichment; it’s a pure edge concern.

Configuration

- `PORT` (optional, default `8080`).

Navigate

- Gateway file URL injection: [`../gateway/files-injection.md`](../gateway/files-injection.md)
- Shared components: [`../shared/README.md`](../shared/README.md)
- Docs index: [`../README.md`](../README.md)
