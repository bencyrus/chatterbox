Gateway

Purpose

- Reverse proxy to PostgREST with two responsibilities:
  1. Best‑effort token refresh when access token is close to expiry
  2. Inject signed file URLs into JSON responses that contain a top‑level `files` array

Behavior

- Refresh: checks expiry and presence of refresh token header; runs a preflight refresh with a short timeout. Success or failure does not block the main request; new tokens (if any) are attached to response headers.
- File URLs: injects signed URLs when the upstream JSON includes `files`.
  - Object responses: `{ ..., "files": [...] }` → adds `{ ..., "processed_files": [...] }`.
  - Array responses: `[ { "files": [...] }, { ... }, ... ]` → adds `processed_files` to each object that contains `files`.

Headers

- Incoming refresh header: `REFRESH_TOKEN_HEADER_IN` (default `X-Refresh-Token`)
- Outgoing refreshed tokens: `NEW_ACCESS_TOKEN_HEADER_OUT` and `NEW_REFRESH_TOKEN_HEADER_OUT`
- Request correlation: `X-Request-ID` flows from Caddy and is logged

Configuration (env)

- Required: `POSTGREST_URL`, `JWT_SECRET`, `REFRESH_TOKENS_PATH`, `REFRESH_THRESHOLD_SECONDS`, `FILE_SERVICE_URL`, `FILE_SIGNED_URL_PATH`, `FILES_FIELD_NAME`, `PROCESSED_FILES_FIELD_NAME`
- Optional: `PORT`, `REFRESH_TOKEN_HEADER_IN`, `NEW_ACCESS_TOKEN_HEADER_OUT`, `NEW_REFRESH_TOKEN_HEADER_OUT`, `HTTP_CLIENT_TIMEOUT_SECONDS`
- See [`internal/config/config.go`](internal/config/config.go) for source of truth.

Flow

- Request → gateway (optional refresh) → PostgREST
- Response ← gateway (optional file URL injection) ← PostgREST

Notes

- Only processes `application/json` responses and looks for a top‑level field named by `FILES_FIELD_NAME` on objects. For top‑level arrays, each element is inspected for that field.
- Designed to be fail‑safe: token refresh and file URL processing never fail the main request.
- Code reference: [`internal/proxy`](internal/proxy), [`internal/auth`](internal/auth), [`internal/files`](internal/files).
