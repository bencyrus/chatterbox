## Gateway

Status: current
Last verified: 2025-10-08

← Back to [`docs/README.md`](../README.md)

### Why this exists

- Keep PostgREST focused on exposing database state while handling edge concerns here.
- Improve UX by refreshing tokens opportunistically and enriching JSON responses with signed file URLs.

### Role in the system

- Reverse proxy in front of PostgREST.
- Responsibilities:
  - Best‑effort token refresh when access token is near expiry.
  - Inject signed file URLs into JSON responses that contain a configured top‑level files array.
- Fail‑safe: enhancements never block or fail the main proxied request.

### How it works

- At a high level, the gateway:
  - Proxies requests to PostgREST.
  - Optionally refreshes tokens preflight based on expiry.
  - Optionally enriches JSON responses with signed file URLs.
- For detailed flows, see the child pages below.

### Operations

- Port: `PORT` (default `8080`).
- Upstream: `POSTGREST_URL` (e.g., `http://postgrest:3000`).
- Env (required): `POSTGREST_URL`, `JWT_SECRET`, `REFRESH_TOKENS_PATH`, `REFRESH_THRESHOLD_SECONDS`, `FILE_SERVICE_URL`, `FILE_SIGNED_URL_PATH`, `FILES_FIELD_NAME`, `PROCESSED_FILES_FIELD_NAME`.
- Env (optional): `PORT`, `REFRESH_TOKEN_HEADER_IN` (default `X-Refresh-Token`), `NEW_ACCESS_TOKEN_HEADER_OUT` (default `X-New-Access-Token`), `NEW_REFRESH_TOKEN_HEADER_OUT` (default `X-New-Refresh-Token`), `HTTP_CLIENT_TIMEOUT_SECONDS` (default `10`).
- Configuration source: [`gateway/internal/config/config.go`](../../gateway/internal/config/config.go)
- Build/run: [`gateway/Dockerfile`](../../gateway/Dockerfile)

### Examples

- See detailed examples in:
  - Auth refresh: [`./auth-refresh.md`](./auth-refresh.md)
  - File URL injection: [`./files-injection.md`](./files-injection.md)

### Future

- None at this time.

### See also

- Auth refresh: [`./auth-refresh.md`](./auth-refresh.md)
- File URL injection: [`./files-injection.md`](./files-injection.md)
- Shared components: [`../shared/README.md`](../shared/README.md)
- Docs index: [`../README.md`](../README.md)
